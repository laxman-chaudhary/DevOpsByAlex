#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run this script as root (use sudo)."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# Function to uninstall Composer
uninstall_composer() {
    echo "🗑️ Removing Composer..."
    sudo rm -f /usr/local/bin/composer
    echo "✅ Composer has been completely removed."
    exit 0
}

# Ask user if they want to install or remove Composer
while true; do
    echo "🔧 Composer Installation Menu:"
    echo "1️⃣  Install Composer"
    echo "2️⃣  Uninstall Composer"
    echo "3️⃣  Exit"

    read -p "👉 Enter your choice: " choice

    case $choice in
        1) break ;;  # Proceed with installation
        2) uninstall_composer ;;  # Uninstall Composer
        3) echo "🚫 Exiting..."; exit 1 ;;  # Exit the script
        *) echo "❌ Invalid input! Please select 1, 2, or 3." ;;
    esac
done

# Check if PHP is installed
if ! command -v php &>/dev/null; then
    echo "❌ PHP is not installed. Please install PHP first and rerun the script."
    exit 1
else
    echo "✅ PHP is already installed."
fi

# Download the Composer installer
echo "🌍 Downloading Composer installer..."
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"

# Get the latest Composer setup SHA-384 hash from the official website
HASH=$(curl -fsSL https://composer.github.io/installer.sig)

# Verify the installer
echo "🔍 Verifying Composer installer..."
if php -r "exit(hash_file('sha384', 'composer-setup.php') === '$HASH' ? 0 : 1);"; then
    echo "✅ Installer verified."
else
    echo "❌ Installer corrupt. Exiting..."
    rm composer-setup.php
    exit 1
fi

# Install Composer
echo "📦 Installing Composer..."
php composer-setup.php --quiet

# Remove installer file
rm composer-setup.php

# Move Composer to global binary location
mv composer.phar /usr/local/bin/composer

# Verify installation
echo "🚀 Verifying Composer installation..."
composer --version

# Installation complete
echo "🎉 Composer installation complete! Run 'composer --version' to verify."
