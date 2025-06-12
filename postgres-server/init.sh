#!/bin/bash

# Exit on error
set -e

# Create required directories
mkdir -p ./logs ./data
sudo chown 999:999 ./logs ./data
sudo chmod 2770 ./logs ./data

# Check if psql from version 16 is installed
if ! psql --version 2>/dev/null | grep -q "psql (PostgreSQL) 16"; then
  echo "PostgreSQL 16 client not found. Installing..."

  sudo apt update
  sudo apt install -y curl ca-certificates

  sudo install -d /usr/share/postgresql-common/pgdg
  sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc

  sudo sh -c "echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt \$(lsb_release -cs)-pgdg main' > /etc/apt/sources.list.d/pgdg.list"

  sudo apt update
  sudo apt install -y postgresql-client-16

  echo "PostgreSQL 16 client installed."
else
  echo "PostgreSQL 16 client already installed."
fi

# Start Docker Compose
docker compose up -d && echo && docker compose ps
