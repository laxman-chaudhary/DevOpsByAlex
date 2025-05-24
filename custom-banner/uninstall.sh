#!/bin/bash

set -e

# Paths
BANNER_SCRIPT="/etc/update-motd.d/99-custom-banner"
CONFIG_FILE="/etc/custom-banner.conf"
LOG_FILE="/var/log/custom-banner.log"
LOGROTATE_CONF="/etc/logrotate.d/custom-banner"

echo "🧹 Starting uninstallation of custom login banner..."

# Remove MOTD script
if [ -f "$BANNER_SCRIPT" ]; then
    echo "❌ Removing MOTD banner script..."
    sudo rm -f "$BANNER_SCRIPT"
else
    echo "✅ Banner script already removed."
fi

# Remove config file
if [ -f "$CONFIG_FILE" ]; then
    echo "🗑 Removing config file..."
    sudo rm -f "$CONFIG_FILE"
fi

# Remove banner log file
if [ -f "$LOG_FILE" ]; then
    echo "🗑 Removing banner log file..."
    sudo rm -f "$LOG_FILE"
fi

# Remove logrotate config
if [ -f "$LOGROTATE_CONF" ]; then
    echo "🗑 Removing logrotate config..."
    sudo rm -f "$LOGROTATE_CONF"
fi

# Fixing Permission
sudo chmod -x "/etc/update-motd.d/*"
# Optional: reload UFW if desired (just a safeguard step)
# sudo ufw reload

echo "✅ Custom login banner successfully uninstalled."
