
sudo apt update -y && sudo apt upgrade -y && \
sudo apt install -y wget curl git net-tools apt-transport-https software-properties-common && \

###### This is Prometheus Script ######
sudo useradd --no-create-home --shell /bin/false prometheus && \
sudo mkdir /etc/prometheus && \
sudo mkdir /var/lib/prometheus && \
sudo chown prometheus:prometheus /var/lib/prometheus && \
wget https://github.com/prometheus/prometheus/releases/download/v2.51.1/prometheus-2.51.1.linux-amd64.tar.gz && \
tar -xvf prometheus-* && sudo chown -R prometheus:prometheus prometheus-* && cd prometheus-* && \
sudo mv console* /etc/prometheus && \
sudo mv prometheus.yml /etc/prometheus && \
sudo mv prometheus promtool /usr/local/bin/ && \
echo -e "[Unit]\nDescription=Prometheus\nWants=network-online.target\nAfter=network-online.target\n\n[Service]\nUser=prometheus\nGroup=prometheus\nType=simple\nExecStart=/usr/local/bin/prometheus --config.file /etc/prometheus/prometheus.yml --storage.tsdb.path /var/lib/prometheus/ --web.console.templates=/etc/prometheus/consoles --web.console.libraries=/etc/prometheus/console_libraries --web.listen-address=127.0.0.1:9090\n\n[Install]\nWantedBy=multi-user.target" | sudo tee /etc/systemd/system/prometheus.service && \

sudo systemctl daemon-reload && systemctl enable --now prometheus.service && \
netstat -tlnp | grep 9090 && \


###### This is Graphaha Server Script ######
sudo mkdir -p /etc/apt/keyrings/ && \
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null && \
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list && \
sudo apt update && \
sudo apt install grafana -y && systemctl enable grafana-server --now && \
netstat -tlnp | grep 3000 \

###### This is Node Expoter Script ######
sudo useradd --no-create-home --shell /bin/false node_exporter
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz && \
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz && \
cd node_exporter-1.7.0.linux-amd64 && \
sudo mv node_exporter /usr/local/bin/ && \
sudo echo -e "[Unit]\nDescription=Node Exporter\nWants=network-online.target\nAfter=network-online.target\n\n[Service]\nUser=node_exporter\nGroup=node_exporter\nType=simple\nExecStart=/usr/local/bin/node_exporter  --web.listen-address=127.0.0.1:9100\nRestart=always\nRestartSec=3\n\n[Install]\nWantedBy=multi-user.target" | sudo tee /etc/systemd/system/node_exporter.service && \
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter && \
sudo systemctl daemon-reload && sudo systemctl enable --now node_exporter.service
