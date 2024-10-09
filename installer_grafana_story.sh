#!/bin/bash

green="\e[32m"
pink="\e[35m"
reset="\e[0m"

echo -e "${green}*************Update and upgrade the system*************${reset}"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo -e "${green}*************Install necessary dependencies*************${reset}"
apt-get install -y curl tar wget original-awk gawk netcat jq

set -e

echo -e "${green}*************Ensure the script is run as root*************${reset}"
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo -e "${green}*************Recieve status of node*************${reset}"
port=$(awk '/\[rpc\]/ {f=1} f && /laddr/ {match($0, /127.0.0.1:([0-9]+)/, arr); print arr[1]; f=0}' $HOME/.story/story/config/config.toml)
json_data=$(curl -s http://localhost:$port/status)
story_address=$(echo "$json_data" | jq -r '.result.validator_info.address')
network=$(echo "$json_data" | jq -r '.result.node_info.network')

touch .bash_profile
source .bash_profile
echo -e "${green}************************${reset}"

check_service_status() {
  service_name="$1"
  if systemctl is-active --quiet "$service_name"; then
    echo "$service_name is running."
  else
    echo "$service_name is not running."
  fi
}

echo -e "${green}*************Create necessary directories***********${reset}"
directories=("/var/lib/prometheus" "/etc/prometheus/rules" "/etc/prometheus/rules.d" "/etc/prometheus/files_sd")

for dir in "${directories[@]}"; do
  if [ -d "$dir" ] && [ "$(ls -A $dir)" ]; then
    echo "$dir already exists and is not empty. Skipping..."
  else
    mkdir -p "$dir"
    echo "Created directory: $dir"
  fi
done

echo -e "${green}*************Download and extract Prometheus***********${reset}"
cd $HOME
rm -rf prometheus*
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
sleep 1
tar xvf prometheus-2.45.0.linux-amd64.tar.gz
rm prometheus-2.45.0.linux-amd64.tar.gz
cd prometheus*/

if [ -d "/etc/prometheus/consoles" ] && [ "$(ls -A /etc/prometheus/consoles)" ]; then
  echo "/etc/prometheus/consoles directory exists and is not empty. Skipping..."
else
  mv consoles /etc/prometheus/
fi

if [ -d "/etc/prometheus/console_libraries" ] && [ "$(ls -A /etc/prometheus/console_libraries)" ]; then
  echo "/etc/prometheus/console_libraries directory exists and is not empty. Skipping..."
else
  mv console_libraries /etc/prometheus/
fi

mv prometheus promtool /usr/local/bin/

echo -e "${green}**************Define Prometheus config**********${reset}"
if [ -f "/etc/prometheus/prometheus.yml" ]; then
  rm "/etc/prometheus/prometheus.yml"
fi
sudo tee /etc/prometheus/prometheus.yml<<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
alerting:
  alertmanagers:
    - static_configs:
        - targets: []
rule_files: []
scrape_configs:
  - job_name: "prometheus"
    metrics_path: /metrics
    static_configs:
      - targets: ["localhost:9345"]
  - job_name: "story"
    scrape_interval: 5s
    metrics_path: /
    static_configs:
      - targets: ['localhost:26660']
EOF

echo -e "${green}************Create Prometheus service***********${reset}"

sudo tee /etc/systemd/system/prometheus.service<<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
User=root
ExecReload=/bin/kill -HUP \$MAINPID
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9344
Restart=always
[Install]
WantedBy=multi-user.target
EOF

echo -e "${green}**************Reload systemd, enable, and start Prometheus**********${reset}"
systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

check_service_status "prometheus"

echo -e "${green}**************Install Grafana**********${reset}"
apt-get install -y apt-transport-https software-properties-common wget
wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
echo "deb https://packages.grafana.com/enterprise/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list
apt-get update -y
apt-get install grafana-enterprise -y
systemctl daemon-reload
systemctl enable grafana-server
systemctl start grafana-server

check_service_status "grafana-server"

real_ip=$(hostname -I | awk '{print $1}')

echo -e "${green}*************Install and start Prometheus Node Exporter***********${reset}"
apt install prometheus-node-exporter -y

service_file="/etc/systemd/system/prometheus-node-exporter.service"

if [ -e "$service_file" ]; then
    rm "$service_file"
    echo "File $service_file removed."
else
    echo "File $service_file does not exist."
fi

sudo tee /etc/systemd/system/prometheus-node-exporter.service<<EOF
[Unit]
Description=prometheus-node-exporter
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
User=$USER
ExecStart=/usr/bin/prometheus-node-exporter --web.listen-address=0.0.0.0:9345
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

echo -e "${green}*************New port number for Grafana***********${reset}"
grafana_config_file="/etc/grafana/grafana.ini"
new_port="9346"

if [ ! -f "$grafana_config_file" ]; then
  echo "Grafana configuration file not found: $grafana_config_file"
  exit 1
fi

sed -i "s/^;http_port = .*/http_port = $new_port/" "$grafana_config_file"
systemctl restart grafana-server
check_service_status "grafana-server"

echo -e "${green}*************Change config prometheus ON ***********${reset}"
file_path="$HOME/.story/story/config/config.toml"
search_text="prometheus = false"
replacement_text="prometheus = true"

if grep -qFx "$replacement_text" "$file_path"; then
  echo "Replacement text already exists. No changes needed."
else
  sed -i "s/$search_text/$replacement_text/g" "$file_path"
  echo "Text replaced successfully."
fi

systemctl restart prometheus-node-exporter
systemctl restart prometheus
systemctl restart grafana-server
systemctl restart story

sleep 3

check_service_status "prometheus-node-exporter"
check_service_status "prometheus"
check_service_status "grafana-server"
check_service_status "story"

grafana_host="http://localhost:9346"
admin_user="admin"
admin_password="admin"
prometheus_url="http://localhost:9344"
dashboard_url="https://raw.githubusercontent.com/encipher88/story-grafana/main/dashboard_story.json"

echo -e "${green}***********Downloading and modifying the dashboard_story.json*************${reset}"
curl -s "$dashboard_url" -o $HOME/dashboard_story.json

echo -e "${green}***********Replacing validator address in the dashboard_story.json*************${reset}"
sed -i "s/FCB1BF9FBACE6819137DFC999255175B7CA23C5D/$story_address/g" $HOME/dashboard_story.json

echo -e "${green}***********Configuring Prometheus data source in Grafana*************${reset}"
curl -X POST "$grafana_host/api/datasources" \
    -H "Content-Type: application/json" \
    -u "$admin_user:$admin_password" \
    -d '{
          "name": "Prometheus",
          "type": "prometheus",
          "access": "proxy",
          "url": "'"$prometheus_url"'",
          "basicAuth": false,
          "isDefault": true,
          "jsonData": {}
        }'

echo -e "${green}***********Importing the dashboard into Grafana*************${reset}"
curl -X POST "$grafana_host/api/dashboards/db" \
    -H "Content-Type: application/json" \
    -u "$admin_user:$admin_password" \
    -d '{
          "dashboard": '$(cat $HOME/dashboard_story.json)',
          "overwrite": true,
          "inputs": [
            {
              "name": "DS_PROMETHEUS",
              "type": "datasource",
              "pluginId": "prometheus",
              "value": "Prometheus"
            }
          ]
        }'

echo -e "${pink}************* Setup complete! *************${reset}"
