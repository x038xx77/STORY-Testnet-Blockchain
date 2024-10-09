#!/bin/bash

# Define color codes for console output to improve readability
green="\e[32m"  # Green color for successful messages
reset="\e[0m"   # Reset color to default

# Step 1: Update and upgrade the system
echo -e "${green}************* Update and upgrade the system *************${reset}"
apt-get update -y  # Update the package lists
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y  # Upgrade installed packages without prompting

# Step 2: Install necessary dependencies
echo -e "${green}************* Install necessary dependencies *************${reset}"
apt-get install -y curl tar wget original-awk gawk netcat jq  # Install required packages

# Step 3: Exit the script on any error
set -e  # Exit immediately if a command exits with a non-zero status

# Step 4: Ensure the script is run as root
echo -e "${green}************* Ensure the script is run as root *************${reset}"
if [ "$EUID" -ne 0 ]; then  # Check if the user is root
  echo "Please run as root"  # Prompt to run as root if not
  exit 1  # Exit the script with an error
fi

# Step 5: Fetch the node status from the configuration file
echo -e "${green}************* Receive status of node *************${reset}"
port=$(awk '/\[rpc\]/ {f=1} f && /laddr/ {match($0, /127.0.0.1:([0-9]+)/, arr); print arr[1]; f=0}' "$HOME/.story/story/config/config.toml")
json_data=$(curl -s "http://localhost:$port/status")  # Fetch node status using curl
story_address=$(echo "$json_data" | jq -r '.result.validator_info.address')  # Extract validator address using jq
network=$(echo "$json_data" | jq -r '.result.node_info.network')  # Extract network information

# Step 6: Source the bash profile if it exists
touch .bash_profile  # Ensure the bash profile file exists
source .bash_profile  # Load the bash profile

# Function to check service status
check_service_status() {
  service_name="$1"  # Accept service name as an argument
  if systemctl is-active --quiet "$service_name"; then  # Check if the service is active
    echo "$service_name is running."  # Service is running
  else
    echo "$service_name is not running."  # Service is not running
  fi
}

# Step 7: Create necessary directories if they don't exist or are empty
echo -e "${green}************* Create necessary directories *************${reset}"
directories=("/var/lib/prometheus" "/etc/prometheus/rules" "/etc/prometheus/rules.d" "/etc/prometheus/files_sd")  # List of directories to create

for dir in "${directories[@]}"; do  # Iterate over each directory
  if [ -d "$dir" ] && [ "$(ls -A "$dir")" ]; then  # Check if the directory exists and is not empty
    echo "$dir already exists and is not empty. Skipping..."  # Skip if directory exists and is not empty
  else
    mkdir -p "$dir"  # Create the directory if it does not exist or is empty
    echo "Created directory: $dir"  # Confirm directory creation
  fi
done

# Step 8: Download and extract Prometheus
echo -e "${green}************* Download and extract Prometheus *************${reset}"
cd "$HOME"  # Change to home directory
rm -rf prometheus*  # Remove any previous Prometheus files
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz  # Download Prometheus tarball
sleep 1  # Pause for a moment
tar xvf prometheus-2.45.0.linux-amd64.tar.gz  # Extract the downloaded tarball
rm prometheus-2.45.0.linux-amd64.tar.gz  # Remove the tarball after extraction
cd prometheus*/  # Change to the extracted Prometheus directory

# Step 9: Move necessary directories to Prometheus locations if they don't exist or are empty
if [ -d "/etc/prometheus/consoles" ] && [ "$(ls -A /etc/prometheus/consoles)" ]; then
  echo "/etc/prometheus/consoles directory exists and is not empty. Skipping..."  # Skip if the directory exists and is not empty
else
  mv consoles /etc/prometheus/  # Move consoles directory to the Prometheus location
fi

if [ -d "/etc/prometheus/console_libraries" ] && [ "$(ls -A /etc/prometheus/console_libraries)" ]; then
  echo "/etc/prometheus/console_libraries directory exists and is not empty. Skipping..."  # Skip if the directory exists and is not empty
else
  mv console_libraries /etc/prometheus/  # Move console_libraries to the Prometheus location
fi

# Step 10: Move binaries to the appropriate location
mv prometheus promtool /usr/local/bin/  # Move Prometheus binaries to /usr/local/bin

# Step 11: Define Prometheus configuration
echo -e "${green}************* Define Prometheus config *************${reset}"
if [ -f "/etc/prometheus/prometheus.yml" ]; then
  rm "/etc/prometheus/prometheus.yml"  # Remove existing Prometheus config if it exists
fi
# Create new Prometheus configuration file
sudo tee /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s  # Set global scrape interval for metrics
  evaluation_interval: 15s  # Set global evaluation interval for rules
alerting:
  alertmanagers:
    - static_configs:
        - targets: []  # Define targets for alert manager
rule_files: []  # No rule files by default
scrape_configs:
  - job_name: "prometheus"  # Job name for Prometheus metrics
    metrics_path: /metrics  # Metrics path for Prometheus
    static_configs:
      - targets: ["localhost:9345"]  # Target for Prometheus metrics
  - job_name: "story"  # Job name for story metrics
    scrape_interval: 5s  # Scrape interval for story
    metrics_path: /  # Metrics path for story
    static_configs:
      - targets: ['localhost:26660']  # Target for story metrics
EOF

# Step 12: Create Prometheus systemd service
echo -e "${green}************* Create Prometheus service *************${reset}"
sudo tee /etc/systemd/system/prometheus.service <<EOF
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

# Step 13: Reload systemd, enable, and start Prometheus
echo -e "${green}************* Reload systemd, enable, and start Prometheus *************${reset}"
systemctl daemon-reload  # Reload systemd to recognize new service
systemctl enable prometheus  # Enable Prometheus to start at boot
systemctl start prometheus  # Start the Prometheus service

check_service_status "prometheus"  # Check and display the status of Prometheus service

# Step 14: Install Grafana
echo -e "${green}************* Install Grafana *************${reset}"
apt-get install -y apt-transport-https software-properties-common wget  # Install required packages
wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -  # Add Grafana GPG key
echo "deb https://packages.grafana.com/enterprise/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list  # Add Grafana repository
apt-get update -y  # Update package lists
apt-get install grafana-enterprise -y  # Install Grafana enterprise version
systemctl daemon-reload  # Reload systemd manager configuration
systemctl enable grafana-server  # Enable Grafana to start at boot
systemctl start grafana-server  # Start the Grafana service

check_service_status "grafana-server"  # Check and display the status of Grafana service

# Final message indicating installation completion
echo -e "${green}************* Installation completed successfully! *************${reset}"
