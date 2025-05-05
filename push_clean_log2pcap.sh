#!/bin/bash

# === CONFIG ===
REPO_NAME="log2pcap"
GIT_USER="DadOpsMateoMaddox"
KEY_PATH="$HOME/.ssh/mateomaddoxnamechange"
WORK_DIR="$HOME/cleanhoneypot"

# === 1. Clean old git repo ===
cd "$WORK_DIR" || exit 1
rm -rf .git

# === 2. Init clean repo ===
git init
git branch -m main
git remote add origin git@github.com:$GIT_USER/$REPO_NAME.git

# === 3. Strip secrets from disk ===
rm -f $(find . -type f \( -iname "*.pem" -o -iname "*.key" -o -iname "*.priv*" -o -iname "*.rsa*" -o -iname "secrets.txt" \))

# === 4. Stage and commit everything ===
git add .
git commit -m "🔥 Rebuilt & scrubbed: fresh, clean log2pcap deploy"

# === 5. Force push with SSH key ===
GIT_SSH_COMMAND="ssh -i $KEY_PATH -o IdentitiesOnly=yes" \
git push -u origin main --force

