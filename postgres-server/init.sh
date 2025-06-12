#!/bin/bash

# Exit on error
set -e

# Create required directories
mkdir -p ./logs ./data
sudo chown 999:999 ./logs ./data
sudo chmod 2770 ./logs ./data

# Ensure pwgen is installed
if ! command -v pwgen >/dev/null; then
  echo "pwgen not found. Installing..."
  sudo apt update
  sudo apt install -y pwgen
fi

# Generate a secure password
echo "Generating secure password for PostgreSQL..."
DB_PASS=$(pwgen 12 1)

# Update the .env file
echo "Updating .env file..."
cat > .env <<EOF
# .env file
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$DB_PASS
POSTGRES_DB=postgres
EOF

# Store password in hidden file in /root/
echo "$DB_PASS" | sudo tee /root/.pg_password >/dev/null
sudo chmod 600 /root/.pg_password

echo ".env and /root/.pg_password updated with generated password."

# Install PostgreSQL client 16 if not already installed
if ! psql --version 2>/dev/null | grep -q "psql (PostgreSQL) 16"; then
  echo "PostgreSQL 16 client not found. Installing..."

  sudo apt update
  sudo apt install -y curl ca-certificates

  sudo install -d /usr/share/postgresql-common/pgdg
  sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc

  # Add PostgreSQL APT repo properly
  echo "Adding PostgreSQL APT repository..."
  echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null


  sudo apt update
  sudo apt install -y postgresql-client-16

  echo "PostgreSQL 16 client installed."
else
  echo "PostgreSQL 16 client already installed."
fi

# Start Docker containers
docker compose up -d && echo && docker compose ps
