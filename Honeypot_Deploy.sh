#!/bin/bash

# ==============================
# Cowrie Honeypot Deployment Script
# Operation: SitBackAndAttack
# Author: MaddoxsDad
# ==============================

# === CONFIGURATION ===
EMAIL="kevinlandrycyber@gmail.com"
GIT_REPO="git@github.com:MaddoxsDad/log2pcap.git"
BRANCH="master"
REPO_NAME="log2pcap"
SOURCE_DIR="$HOME/Honeypot"
CLEAN_DIR="$HOME/cleanhoneypot"
LOGFILE="/var/log/log2pcap_deploy_$(date +%Y-%m-%d_%H-%M-%S).log"
VT_API_KEY="00639fce87a66d649e1609be113f961cc705066649ae6722ea1c9223e4a06e4f"
IP_LOG="/var/log/honeypot_ips.txt"
HEATMAP_DATA="/var/log/honeypot_geo.json"
SHODAN_API_KEY="f2tDR9wnvwvGMeFX5NyQzqgYFjYcv7l6"  # <-- your actual key

# Telegram Bot Info
BOT_TOKEN="6103737792:AAFbVbYrJLa-czH1mEKzQEXn-RhCr93LDmg"
CHAT_ID="-1001882871529"

mkdir -p /var/log

declare -a NEW_IPS

log() {
  echo -e "$1" | tee -a "$LOGFILE"
}

send_telegram_alert() {
  local message="$1"
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$message" \
    -d parse_mode="Markdown" >> "$LOGFILE"
}

log_vt_ip() {
  local ip="$1"
  log "\n🌍 Submitting $ip to VirusTotal..."
  response=$(curl -s --request POST \
    --url https://www.virustotal.com/api/v3/ip_addresses/$ip \
    --header "x-apikey: $VT_API_KEY")
  echo -e "$response" >> "$LOGFILE"
  send_telegram_alert "\[VT Intel Drop 🧠\] Attacker IP: *$ip* submitted to VirusTotal."
  echo "$ip" >> "$IP_LOG"
  fetch_geo_data "$ip"
}

fetch_geo_data() {
  local ip="$1"
  geo_json=$(curl -s "https://api.shodan.io/shodan/host/$ip?key=$SHODAN_API_KEY")

  city=$(echo $geo_json | jq -r '.city // ""')
  country=$(echo $geo_json | jq -r '.country_name // ""')
  lat=$(echo $geo_json | jq -r '.latitude // 0')
  lon=$(echo $geo_json | jq -r '.longitude // 0')
  ports=$(echo $geo_json | jq -r '.ports | join(", ")')
  org=$(echo $geo_json | jq -r '.org // "Unknown"')
  tags=$(echo $geo_json | jq -r '.tags | join(", ")')

  timestamp=$(date -u +%FT%TZ)

  echo "{" >> "$HEATMAP_DATA"
  echo "  \"ip\": \"$ip\"," >> "$HEATMAP_DATA"
  echo "  \"city\": \"$city\"," >> "$HEATMAP_DATA"
  echo "  \"country_name\": \"$country\"," >> "$HEATMAP_DATA"
  echo "  \"latitude\": $lat," >> "$HEATMAP_DATA"
  echo "  \"longitude\": $lon," >> "$HEATMAP_DATA"
  echo "  \"timestamp\": \"$timestamp\"," >> "$HEATMAP_DATA"
  echo "  \"notes\": \"From $org | Open Ports: $ports | Tags: $tags\"" >> "$HEATMAP_DATA"
  echo "}," >> "$HEATMAP_DATA"

  send_telegram_alert "📍 *Heatmap Update:* $ip seen from *$city, $country*. Ports: $ports. Tags: $tags."
}

parse_and_log_ips() {
  log "\n🕵️‍♂️ Parsing Cowrie logs for new IPs..."
  grep -aoE "New connection: ([0-9]{1,3}\.){3}[0-9]{1,3}" "$SOURCE_DIR/var/log/cowrie/cowrie.log" | awk '{print $3}' | sort -u > /tmp/current_ips.txt

  for ip in $(cat /tmp/current_ips.txt); do
    if ! grep -q "$ip" "$IP_LOG" 2>/dev/null; then
      NEW_IPS+=("$ip")
      log_vt_ip "$ip"
    fi
  done
}

# === SSH FIX ===
log "\n🔐 [1/9] Fixing SSH key permissions..."
chmod 600 ~/.ssh/id_rsa 2>/dev/null
chmod 700 ~/.ssh
cat > ~/.ssh/config <<EOF
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_rsa
    IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config

# === CHECK GITHUB AUTH ===
log "\n🔗 [2/9] Checking GitHub SSH access..."
ssh -T git@github.com | tee -a "$LOGFILE"

# === CLEAN REPO INIT ===
log "\n🧨 [3/9] Nuking old clean dir & rebuilding from source..."
rm -rf "$CLEAN_DIR"
mkdir -p "$CLEAN_DIR"
rsync -av --exclude '.git' "$SOURCE_DIR"/ "$CLEAN_DIR"/ >> "$LOGFILE" 2>&1
cd "$CLEAN_DIR"

# === GIT REINIT ===
log "\n🧱 [4/9] Initializing new repo in $CLEAN_DIR"
git init

git checkout -b "$BRANCH"
git config user.email "$EMAIL"
git config user.name "Honeypot AutoDeployer"
git add .
git commit -m "Clean deploy: no secrets, fresh from $SOURCE_DIR"
git remote add origin "$GIT_REPO"

# === PUSH TO GITHUB ===
log "\n🚀 [5/9] Force pushing clean tree to $GIT_REPO"
git push -u origin "$BRANCH" --force | tee -a "$LOGFILE"

# === TELEGRAM ALERT ===
log "\n📢 [6/9] Sending Telegram alert..."
ALERT_MSG="\[Cowrie Alert 🚨\] `date -u +%FT%TZ` - Honeypot redeployed to GitHub: *$REPO_NAME*"
send_telegram_alert "$ALERT_MSG"

# === PARSE & SUBMIT IPS ===
log "\n🧠 [7/9] Hunting attackers in logs and submitting to VirusTotal..."
parse_and_log_ips

# === GEOIP HEATMAP BUILD ===
log "\n🗺️ [8/9] Updating Shodan-sourced heatmap geo feed..."
# heatmap auto-populated via fetch_geo_data per IP

# === WRAP UP ===
log "\n✅ [9/9] Deployment complete. Logs written to $LOGFILE. IPs: $IP_LOG | GeoJSON: $HEATMAP_DATA"

