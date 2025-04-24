#!/bin/bash

# Ensure script runs in non-interactive mode
export DEBIAN_FRONTEND=noninteractive

# Avoid interactive pop-ups during installation
sudo apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade -yqq

# Short delay for better readability
sleep 2

echo "🔄 Checking for existing Node.js installation..."
if command -v node &>/dev/null; then
    NODE_VERSION_INSTALLED=$(node -v)
    echo "⚠️ Node.js is already installed: $NODE_VERSION_INSTALLED"

    # Ask user whether to remove it
    while true; do
        read -p "❓ Do you want to remove Node.js before installing a new version? (y/n): " REMOVE_NODE
        case $REMOVE_NODE in
            [Yy]* ) 
                echo "🗑️ Removing existing Node.js installation..."
                sudo apt-get remove --purge -yqq nodejs npm
                sudo rm -rf /usr/local/lib/node_modules ~/.npm ~/.node-gyp /usr/local/bin/npm /usr/local/bin/node
                echo "✅ Node.js has been removed."
                sleep 2
                break
                ;;
            [Nn]* )
                echo "🚫 Node.js removal skipped. Exiting..."
                exit 1
                ;;
            * ) echo "❌ Invalid input! Please enter 'y' for Yes or 'n' for No." ;;
        esac
    done
else
    echo "✅ No existing Node.js installation found. Proceeding..."
fi

# Display interactive menu for Node.js version selection
while true; do
    echo "🔧 Select the Node.js version to install:"
    echo "1️⃣  Node.js 18.x"
    echo "2️⃣  Node.js 20.x"
    echo "3️⃣  Node.js 22.x"
    echo "4️⃣  Node.js 23.x"
    echo "🔴  Press 'q' to exit"

    read -p "👉 Enter your choice: " choice

    case $choice in
        1) NODE_VERSION="18"; break ;;
        2) NODE_VERSION="20"; break ;;
        3) NODE_VERSION="22"; break ;;
        4) NODE_VERSION="23"; break ;;
        q|Q) echo "🚫 Exiting..."; exit 1 ;;
        *) echo "❌ Invalid input! Please select 1, 2, 3, 4, or 'q' to quit." ;;
    esac
done

# Confirm selection
echo "✅ You selected Node.js $NODE_VERSION.x"

# Install curl if not installed
echo "🔄 Checking for curl..."
if ! command -v curl &>/dev/null; then
    echo "📦 Installing curl..."
    sudo apt-get install -yqq curl
else
    echo "✅ Curl is already installed."
fi

# Download and run the Node.js setup script quietly
echo "🌍 Installing Node.js $NODE_VERSION.x..."
curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | sudo -E bash - > /dev/null 2>&1

# Install Node.js silently
sudo apt-get install -yqq --no-install-recommends nodejs

# Install global npm packages silently
echo "🚀 Installing global npm packages (pm2, yarn, pnpm)..."
sudo npm i -g pm2 yarn pnpm > /dev/null 2>&1

# Cleanup
sleep 2
echo "🎉 Installation complete! Use 'node -v' and 'npm -v' to verify."