#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run this script as root (use sudo)."
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# Function to uninstall Docker
uninstall_docker() {
    echo "🗑️ Removing Docker..."
    sudo apt-get remove -yqq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo rm -rf /var/lib/docker /etc/docker
    echo "✅ Docker has been completely removed."
    exit 0
}

# Ask user if they want to install or remove Docker
while true; do
    echo "🔧 Docker Installation Menu:"
    echo "1️⃣  Install Docker"
    echo "2️⃣  Uninstall Docker"
    echo "3️⃣  Exit"

    read -p "👉 Enter your choice: " choice

    case $choice in
        1) break ;;  # Proceed with installation
        2) uninstall_docker ;;  # Uninstall Docker
        3) echo "🚫 Exiting..."; exit 1 ;;  # Exit the script
        *) echo "❌ Invalid input! Please select 1, 2, or 3." ;;
    esac
done

# Update system packages
echo "🔄 Updating system packages..."
sudo apt-get update -qq

# Install necessary dependencies
echo "📦 Installing required packages..."
sudo apt-get install -yqq --no-install-recommends ca-certificates curl gnupg

# Set up Docker GPG key
echo "🔑 Setting up Docker GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository
echo "📦 Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package list
echo "🔄 Updating package list (Docker repo added)..."
sudo apt-get update -qq

# Install Docker
echo "🐳 Installing Docker (CE, CLI, Containerd, Buildx, Compose)..."
sudo apt-get install -yqq --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker service
echo "🔄 Enabling and starting Docker service..."
sudo systemctl enable --now docker

# Add current user to the Docker group
echo "👤 Adding current user to the Docker group..."
sudo usermod -aG docker $USER

# Ask user to log out and log back in
echo "🔔 Please log out and log back in for Docker group changes to take effect."

# Verify Docker installation
echo "🚀 Verifying Docker installation..."
docker run --rm hello-world

# Installation Complete
echo "🎉 Docker installation complete! Run 'docker -v' to verify."
