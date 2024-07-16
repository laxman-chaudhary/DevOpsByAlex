#!/bin/bash

# Get the current directory
WORK_DIR="$(pwd)"
PROMETHEUS_DIR="$WORK_DIR/prometheus"
GRAFANA_DIR="$WORK_DIR/grafana/data"
PROMETHEUS_CONFIG="$PROMETHEUS_DIR/prometheus.yml"

# Function to prompt the user for including Node Exporter
function prompt_for_node_exporter() {
  echo ""
  read -p "Do you want to include Node Exporter? (y/n): " include_node_exporter
  echo ""
  if [[ "$include_node_exporter" =~ ^[Yy]$ ]]; then
    INCLUDE_NODE_EXPORTER=true
  else
    INCLUDE_NODE_EXPORTER=false
  fi
}

# Function to print colored messages
function print_message() {
  COLOR=$1
  MESSAGE=$2
  echo -e "${COLOR}${MESSAGE}\033[0m"
}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'

# Prompt for Node Exporter inclusion
prompt_for_node_exporter

# Step 1: Create necessary directories
print_message $CYAN "\nStep 1: Checking and creating necessary directories..."
print_message $CYAN "-----------------------------------------------"
if [ ! -d "$PROMETHEUS_DIR" ]; then
  mkdir -p $PROMETHEUS_DIR
  print_message $GREEN "Created Prometheus directory."
else
  print_message $YELLOW "Prometheus directory already exists, skipping creation."
fi

if [ ! -d "$GRAFANA_DIR" ]; then
  mkdir -p $GRAFANA_DIR
  print_message $GREEN "Created Grafana directory."
else
  print_message $YELLOW "Grafana directory already exists, skipping creation."
fi
sleep 2

# Step 2: Fix Permissions
print_message $CYAN "\nStep 2: Setting permissions for directories..."
print_message $CYAN "-----------------------------------------------"
print_message $CYAN "Setting permissions for Prometheus directory..."
sudo chown -R 472:472 $PROMETHEUS_DIR
sudo chmod -R 775 $PROMETHEUS_DIR
print_message $GREEN "Permissions set for Prometheus directory:"
ls -l $PROMETHEUS_DIR

print_message $CYAN "\nSetting permissions for Grafana directory..."
sudo chown -R 472:472 $GRAFANA_DIR
sudo chmod -R 775 $GRAFANA_DIR
print_message $GREEN "Permissions set for Grafana directory:"
ls -l $GRAFANA_DIR
sleep 2

# Step 3: Create Prometheus Configuration File
print_message $CYAN "\nStep 3: Checking and creating Prometheus configuration file..."
print_message $CYAN "------------------------------------------------------------"
if [ ! -f "$PROMETHEUS_CONFIG" ]; then
  cat <<EOL > $PROMETHEUS_CONFIG
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOL
  if [ "$INCLUDE_NODE_EXPORTER" = "true" ]; then
    cat <<EOL >> $PROMETHEUS_CONFIG
  - job_name: 'localhost'
    static_configs:
      - targets: ['localhost:9100']
EOL
  fi
  print_message $GREEN "Prometheus configuration file created."
else
  print_message $YELLOW "Prometheus configuration file already exists, skipping creation."
fi
sleep 2

# Step 4: Create Docker Compose File
print_message $CYAN "\nStep 4: Creating Docker Compose file..."
print_message $CYAN "---------------------------------------"
cat <<EOL > $WORK_DIR/docker-compose.yml
services:
  grafana:
    image: grafana/grafana
    container_name: grafana
    user: "472"
    ports:
      - "3000:3000"
    volumes:
      - ./grafana/data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_SECURITY_ADMIN_USER=admin
    networks:
      - monitoring

  prometheus:
    image: prom/prometheus
    container_name: prometheus
    user: "472"
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus:/etc/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/etc/prometheus/data'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    restart: unless-stopped
    networks:
      - monitoring
EOL

if [ "$INCLUDE_NODE_EXPORTER" = "true" ]; then
  cat <<EOL >> $WORK_DIR/docker-compose.yml

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - monitoring

EOL
  print_message $GREEN "Node Exporter service added to Docker Compose file."
else
  print_message $YELLOW "Node Exporter service not included."
fi

cat <<EOL >> $WORK_DIR/docker-compose.yml

networks:
  monitoring:
    driver: bridge
EOL
sleep 2

# Prompt to run Docker Compose
echo ""
read -p "Do you want to run Docker Compose now? (y/n): " run_docker_compose
echo ""
if [[ "$run_docker_compose" =~ ^[Yy]$ ]]; then
  # Step 5: Run Docker Compose
  print_message $CYAN "\nStep 5: Starting Docker Compose services..."
  print_message $CYAN "------------------------------------------"
  if docker compose up -d; then
    print_message $GREEN "Docker Compose services started successfully."
  else
    print_message $RED "Failed to start Docker Compose services."
    exit 1
  fi
else
  print_message $YELLOW "You chose not to run Docker Compose now. You can start the services later with the command:"
  print_message $YELLOW "\033[1m\ndocker compose up -d\033[0m"
fi

print_message $GREEN "\nScript execution completed successfully."
