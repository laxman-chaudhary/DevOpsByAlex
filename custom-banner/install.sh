#!/bin/bash

set -e

# === Paths ===
SCRIPT_NAME="99-custom-banner"
SRC_DIR="$(dirname "$(realpath "$0")")"
DEST_MOTD="/etc/update-motd.d/${SCRIPT_NAME}"
DEST_CONFIG="/etc/custom-banner.conf"
DEST_LOGROTATE="/etc/logrotate.d/custom-banner"

# === Step 1: Install dependencies ===
echo "🔧 Installing dependencies (figlet, bc, lolcat, ufw)..."
sudo apt update
sudo apt install -y figlet bc lolcat ufw

# === Step 2: Install MOTD banner script ===
echo "📄 Installing MOTD script to ${DEST_MOTD}..."
sudo cp "$SRC_DIR/$SCRIPT_NAME" "$DEST_MOTD"
sudo chmod -x "/etc/update-motd.d/*"
sudo chmod +x "$DEST_MOTD"

# === Step 3: Copy configuration file (if exists) ===
if [ -f "$SRC_DIR/custom-banner.conf" ]; then
    echo "⚙️  Copying config to $DEST_CONFIG..."
    sudo cp "$SRC_DIR/custom-banner.conf" "$DEST_CONFIG"
fi

# === Step 4: Set up logrotate config ===
if [ -f "$SRC_DIR/logrotate-custom-banner" ]; then
    echo "🔁 Setting up logrotate..."
    sudo cp "$SRC_DIR/logrotate-custom-banner" "$DEST_LOGROTATE"
fi

# === Step 5: Finish ===
echo "✅ Custom banner installed successfully."
echo "ℹ️  Logout and log back in to see the new banner."
