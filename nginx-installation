
#!/bin/bash

# 🚀 Update package lists
echo "🔄 Updating package lists..."
sudo apt-get update -qq -y

# 📦 Install necessary dependencies quietly
echo "📥 Installing dependencies..."
sudo apt install -qq -y curl gnupg2 ca-certificates lsb-release ubuntu-keyring

# 🔑 Import Nginx GPG signing key and store it in a secure keyring
echo "🔐 Importing Nginx signing key..."
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | \
sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

# ✅ Verify the imported key and display its details
echo "🛡️ Verifying imported key..."
gpg --dry-run --quiet --no-keyring --import --import-options import-show \
/usr/share/keyrings/nginx-archive-keyring.gpg

# 📄 Add the official Nginx repository to APT sources
echo "📝 Adding the official Nginx repository..."
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" | \
sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null

# 🔄 Update package lists again to include the new repository
echo "🔄 Updating package lists again..."
sudo apt update -qq -y

# 🚀 Install Nginx quietly
echo "📦 Installing Nginx..."
sudo apt install -qq -y nginx

# ✅ Verify installation
echo "✅ Nginx installation complete!"
nginx -v
