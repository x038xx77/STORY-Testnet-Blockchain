# STORY-Testnet-Blockchain

# Installation and Configuration of Grafana for Story v0.11.0 Release

This guide will help you set up and launch Grafana on your system to monitor Story.

Before proceeding, ensure that the Story node is installed on the server you want to monitor:
[Story Testnet Snapshot](https://service.josephtran.xyz/testnet/story/snapshot/)

### Register on GitHub
- Register on GitHub: https://github.com/
- Create a new repository and add two files:
  - `dashboardStory.json` for the Grafana dashboard
  - `installer_grafana_story.sh` for the installation script.

You can launch the installation using the following single command:
```bash
cd $HOME && wget -q -O installer_grafana_story.sh https://raw.githubusercontent.com/x038xx77/STORY-Testnet-Blockchain/main/installer_grafana_story.sh && chmod +x installer_grafana_story.sh && ./installer_grafana_story.sh
```

## Server Requirements

Before starting, ensure that:

- You are using **Ubuntu**.
- You have **root access** to the server (or can use `sudo`).


Run the following commands to update and upgrade your system:
## Step 1: Update Your System

Begin by updating your system to ensure compatibility with the following steps.


1. Open a terminal.
2. Run the following commands to update and upgrade your system:

    ```bash
    #!/bin/bash
    green="\e[32m"
    reset="\e[0m"
    # Update and upgrade system
    echo -e "${green}Updating and upgrading the system...${reset}"
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    
    ```


---

## Step 2: Install Required Dependencies

For Prometheus and Grafana to function properly, the following packages are required:

1. Run the following command:

    ```bash
    echo -e "${green}Installing required dependencies...${reset}"
    apt-get install -y curl tar wget original-awk gawk netcat jq
    ```

During the installation process, the system will download and configure any missing packages and their dependencies (such as `jq`, `netcat`, `original-awk`, and others).

**Result**: After running the command, all necessary tools for working with Prometheus and Grafana will be installed, and the system will be ready for further configuration.


---

## Step 3: Ensure Root Access


This step checks if the script is running with root privileges. If not, the script will exit with a message.

1. Add the following code to check for root access:

    ```bash
    echo -e "${green}Checking user privileges...${reset}"
    if [ "$EUID" -ne 0 ]; then
        echo "Error: This script must be run as root. Please restart it with administrative privileges."
        exit 1
    else
        echo -e "${green}User privileges confirmed: Running as root.${reset}"
    fi

    ```

2. If you run the script without root privileges, you will see the message:  
   **"Error: This script must be run as root. Please restart it with administrative privileges."**

   In this case, the script execution will be halted.

3. If the script is run with root privileges, you will see the message:  
   **"User privileges confirmed: Running as root."**

**Result**: The check for root privileges has been successfully completed, and you can proceed with the next steps.



## Step 4: Get Story Node Status

This step extracts the Story node status from the config.toml file to retrieve important information such as the validator address and network data.

1. Use the following code:

    ``` bash
    echo -e "${green}Fetching Story node status...${reset}"
    port=$(awk '/\[rpc\]/ {f=1} f && /laddr/ {match($0, /127.0.0.1:([0-9]+)/, arr); print arr[1]; f=0}' $HOME/.story/story/config/config.toml)
    json_data=$(curl -s http://localhost:$port/status)
    story_address=$(echo "$json_data" | jq -r '.result.validator_info.address')
    network=$(echo "$json_data" | jq -r '.result.node_info.network')
   
    ```

2. This code performs the following actions:
   - Extracts the port number on which the Story node is running from the `config.toml` configuration file.
   - Sends a request to the node using `curl` to retrieve the node's status.
   - Extracts the validator address and network information from the received JSON response using `jq`.

**Result**: After completing this step, you will have access to the status of the Story node, including the validator address and network information. You can use this data for further configuration or monitoring.




## Step 5: Install Prometheus

Prometheus will collect metrics from your Story node.


### Download and Extract Prometheus


1. Add this code to the script:

    ```bash
    echo -e "${green}Downloading and extracting Prometheus...${reset}"
    cd $HOME
    rm -rf prometheus*
    wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
    tar xvf prometheus-2.45.0.linux-amd64.tar.gz
    ```

2. This code performs the following actions:
   - Navigates to the home directory.
   - Removes any previous versions of Prometheus if they exist.
   - Downloads the archive containing the latest version of Prometheus.
   - Extracts the contents of the downloaded archive.


### Create Prometheus Service

Create a service to run Prometheus in the background and ensure it starts on boot:

1. Add this code to the script:

    ```bash
    echo -e "${green}Creating Prometheus service...${reset}"
    sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
    [Unit]
    Description=Prometheus
    Wants=network-online.target
    After=network-online.target

    [Service]
    Type=simple
    User=root
    ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus \
    --web.listen-address=0.0.0.0:9344
    Restart=always

    [Install]
    WantedBy=multi-user.target
    EOF

    sudo systemctl daemon-reload
    sudo systemctl enable prometheus
    sudo systemctl start prometheus
    ```

   
2. This code performs the following actions:
   - Creates a service file `prometheus.service` in the `/etc/systemd/system/` directory.
   - Defines parameters for the service, such as description, startup settings, and paths to the configuration file and data storage.
   - Reloads the `systemd` service configuration using `systemctl daemon-reload`.
   - Enables the Prometheus service to start automatically on system boot.
   - Starts the Prometheus service.

**Conclusion**: After completing this step, you have successfully downloaded, extracted, and configured Prometheus to run as a service. Now, Prometheus will automatically start at system boot and collect metrics from your Story node. Ensure that your Story node is running and accessible to Prometheus so it can begin data collection.



## Step 6: Install Grafana

Grafana will visualize the metrics collected by Prometheus.



1.Install Grafana using the following code:

    ```bash
    echo -e "${green}Installing Grafana...${reset}"
    apt-get install -y apt-transport-https software-properties-common wget

    echo -e "${green}Adding Grafana GPG key...${reset}"
    wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -

    echo -e "${green}Adding Grafana repository...${reset}"
    echo "deb https://packages.grafana.com/enterprise/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list

    echo -e "${green}Updating package list...${reset}"
    apt-get update -y

    echo -e "${green}Installing Grafana Enterprise...${reset}"
    apt-get install grafana-enterprise -y

    echo -e "${green}Configuring Grafana service...${reset}"
    systemctl daemon-reload
    systemctl enable grafana-server
    systemctl start grafana-server

    ```

2. This code performs the following actions:
   - Installs the necessary packages for repository management and downloading.
   - Downloads and adds the Grafana GPG key for package authentication.
   - Adds the Grafana repository to the list of package sources.
   - Updates the package list to retrieve information about new packages.
   - Installs Grafana Enterprise.
   - Reloads the `systemd` service configuration using `systemctl daemon-reload`.
   - Enables the Grafana service to start automatically on system boot.
   - Starts the Grafana service.

**Conclusion**: After completing this step, you have successfully installed Grafana and configured it to start automatically at system boot. Grafana will be ready to visualize metrics collected by Prometheus from your Story node. After installation, you can access the Grafana interface at `http://<your_IP>:3000`, where `<your_IP>` is the IP address of your server.

## Step 7: Set Up Grafana to Work with Prometheus

After successfully installing Grafana, the next step is to configure Prometheus as your data source and import the Story dashboard.

### Configure Prometheus as a Data Source

```bash
echo -e "${green}Setting up Prometheus as a data source in Grafana...${reset}"
curl -X POST "http://localhost:9346/api/datasources" \
-H "Content-Type: application/json" \
-u "admin:admin" \
-d '{
  "name": "Prometheus",
  "type": "prometheus",
  "url": "http://localhost:9344",
  "access": "proxy",
  "isDefault": true
}'
```

## Step 8: Open Your Grafana Dashboard
Once the setup is complete, you can access your Grafana dashboard by navigating to the following URL:

```bash

echo -e "${green}Grafana can be accessed at: http://$real_ip:9346/d/UJyurCTWz/${reset}"
echo -e "Login credentials: admin / admin"
Conclusion
By following these steps, you will have established a fully functional Grafana dashboard that tracks metrics from your Story Network node through Prometheus. If you encounter any issues, you can verify the status of your services by running these commands:
```

```bash
systemctl status grafana-server
systemctl status prometheus
systemctl status prometheus-node-exporter
```

### URL Dashboard Grafana!

[<img alt="final" src="https://github.com/x038xx77/STORY-Testnet-Blockchain/blob/main/setupСomplete.png" width="160px">paceX038i](http://$real_ip:9346/d/UJyurCTWz/${reset}) - url dasboard grafana.
