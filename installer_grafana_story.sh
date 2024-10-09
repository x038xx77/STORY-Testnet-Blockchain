#!/bin/bash

# Define color codes for output messages
green="\e[32m"  # Green color for success messages
pink="\e[35m"   # Pink color for additional messages
reset="\e[0m"   # Reset color

# Update and upgrade the system packages
echo -e "${green}************* Updating and upgrading the system *************${reset}"
apt-get update -y             # Update package lists
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y  # Upgrade packages without user interaction

# Install necessary dependencies for the script execution
echo -e "${green}************* Installing necessary dependencies *************${reset}"
apt-get install -y curl tar wget gawk netcat jq  # Install essential tools

# Exit the script if any command fails
set -e

# Ensure the script is executed with root privileges
echo -e "${green}************* Checking for root privileges *************${reset}"
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root."
  exit 1  # Exit if not run as root
fi

# Fetch the status of the Story node to gather information
echo -e "${green}************* Retrieving status of the Story node *************${reset}"
# Extract the RPC port from the configuration file
port=$(awk '/\[rpc\]/ {f=1} f && /laddr/ {match($0, /127.0.0.1:([0-9]+)/, arr); print arr[1]; f=0}' $HOME/.story/story/config/config.toml)
# Fetch JSON data from the node status endpoint
json_data=$(curl -s http://localhost:$port/status)
story_address=$(echo "$json_data" | jq -r '.result.validator_info.address')  # Extract validator address
network=$(echo "$json_data" | jq -r '.result.node_info.network')  # Extract network name

# Source the user's bash profile if it exists
touch .bash_profile  # Create the file if it doesn't exist
source .bash_profile  # Load environment variables from the profile

# Function to check the status of a systemd service
check_service_status() {
  service_name="$1"  # Name of the service to check
  if systemctl is-active --quiet "$service_name"; then
    echo "$service_name is running."  # Service is active
  else
    echo "$service_name is not running."  # Service is inactive
  fi
}

# Create necessary directories for Prometheus if they don't exist or are empty
echo -e "${green}************* Creating necessary directories *************${reset}"
directories=("/var/lib/prometheus" "/etc/prometheus/rules" "/etc/prometheus/rules.d" "/etc/prometheus/files_sd")  # List of required directories

# Loop through each directory in the list
for dir in "${directories[@]}"; do
  if [ -d "$dir" ] && [ "$(ls -A $dir)" ]; then
    echo "$dir already exists and is not empty. Skipping..."  # Skip if directory is non-empty
  else
    mkdir -p "$dir"  # Create the directory
    echo "Created directory: $dir"  # Confirmation message
  fi
done

# Download and extract Prometheus binary
echo -e "${green}************* Downloading and extracting Prometheus *************${reset}"
cd $HOME  # Change to home directory
rm -rf prometheus*  # Remove any previous Prometheus installations
# Download the Prometheus tarball from the official release
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
sleep 1  # Pause for a second to ensure download completion
tar xvf prometheus-2.45.0.linux-amd64.tar.gz  # Extract the downloaded tarball
rm prometheus-2.45.0.linux-amd64.tar.gz  # Remove the tarball after extraction
cd prometheus*/  # Change to the extracted directory

# Move console directories to the appropriate Prometheus locations if they don't exist or are empty
if [ -d "/etc/prometheus/consoles" ] && [ "$(ls -A /etc/prometheus/consoles)" ]; then
  echo "/etc/prometheus/consoles directory exists and is not empty. Skipping..."  # Skip if directory is non-empty
else
  mv consoles /etc/prometheus/  # Move consoles directory
fi

if [ -d "/etc/prometheus/console_libraries" ] && [ "$(ls -A /etc/prometheus/console_libraries)" ]; then
  echo "/etc/prometheus/console_libraries directory exists and is not empty. Skipping..."  # Skip if directory is non-empty
else
  mv console_libraries /etc/prometheus/  # Move console libraries directory
fi

# Move Prometheus and promtool binaries to /usr/local/bin
mv prometheus promtool /usr/local/bin/

# Define the Prometheus configuration file
echo -e "${green}************* Defining Prometheus configuration *************${reset}"
if [ -f "/etc/prometheus/prometheus.yml" ]; then
  rm "/etc/prometheus/prometheus.yml"  # Remove existing config if it exists
fi
# Create a new Prometheus configuration
sudo tee /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s  # Interval between scraping targets
  evaluation_interval: 15s  # Interval for evaluating rules
alerting:
  alertmanagers:
    - static_configs:
        - targets: []  # List of alert manager targets
rule_files: []  # List of rule files
scrape_configs:
  - job_name: "prometheus"  # Job name for the Prometheus server
    metrics_path: /metrics  # Path to scrape metrics
    static_configs:
      - targets: ["localhost:9345"]  # Target for scraping
  - job_name: "story"  # Job name for Story metrics
    scrape_interval: 5s  # Scraping interval for Story metrics
    metrics_path: /  # Path to scrape Story metrics
    static_configs:
      - targets: ['localhost:26660']  # Target for scraping Story
EOF

# Create a systemd service file for Prometheus
echo -e "${green}************* Creating Prometheus systemd service *************${reset}"
sudo tee /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus  # Service description
Wants=network-online.target  # Ensure network is online
After=network-online.target  # Start after network is online

[Service]
Type=simple
User=root  # Run as root user
ExecReload=/bin/kill -HUP \$MAINPID  # Reload service
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9344  # Address for Prometheus web UI
Restart=always  # Always restart the service

[Install]
WantedBy=multi-user.target  # Service target
EOF

# Reload systemd to recognize the new service and enable/start it
echo -e "${green}************* Reloading systemd, enabling, and starting Prometheus *************${reset}"
systemctl daemon-reload  # Reload systemd manager configuration
systemctl enable prometheus  # Enable Prometheus to start on boot
systemctl start prometheus  # Start the Prometheus service

# Check the status of the Prometheus service
check_service_status "prometheus"

# Install Grafana for visualization
echo -e "${green}************* Installing Grafana *************${reset}"
apt-get install -y apt-transport-https software-properties-common wget  # Install dependencies
wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -  # Add Grafana GPG key
# Add Grafana repository to the sources list
echo "deb https://packages.grafana.com/enterprise/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list
apt-get update -y  # Update package lists
apt-get install grafana-enterprise -y  # Install Grafana Enterprise
systemctl daemon-reload  # Reload systemd
systemctl enable grafana-server  # Enable Grafana to start on boot
systemctl start grafana-server  # Start the Grafana service

# Check the status of the Grafana service
check_service_status "grafana-server"

# Install and configure Prometheus Node Exporter
echo -e "${green}************* Installing and starting Prometheus Node Exporter *************${reset}"
apt install prometheus-node-exporter -y  # Install Node Exporter

service_file="/etc/systemd/system/prometheus-node-exporter.service"  # Service file path

# Remove existing Node Exporter service file if it exists
if [ -e "$service_file" ]; then
    rm "$service_file"  # Remove the file
    echo "File $service_file removed."  # Confirmation message
else
    echo "File $service_file does not exist."  # Informative message
fi

# Create a new systemd service file for Node Exporter
sudo tee /etc/systemd/system/prometheus-node-exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter  # Service description
Wants=network-online.target  # Ensure network is online
After=network-online.target  # Start after network is online

[Service]
Type=simple
User=root  # Run as root user
ExecStart=/usr/bin/prometheus-node-exporter  # Start Node Exporter
Restart=always  # Always restart the service

[Install]
WantedBy=multi-user.target  # Service target
EOF

# Enable and start the Node Exporter service
systemctl enable prometheus-node-exporter  # Enable Node Exporter to start on boot
systemctl start prometheus-node-exporter  # Start the Node Exporter service

# Check the status of the Node Exporter service
check_service_status "prometheus-node-exporter"

# Conclusion message
echo -e "${pink}************* Installation and configuration completed! *************${reset}"
echo -e "${pink}Prometheus and Grafana are now set up and running on your server!${reset}"
