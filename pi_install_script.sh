
#!/bin/bash
# wordclock install script - improved for Raspberry Pi
set -e

# Function to handle script exit
cleanup() {
    echo "Script exited at line $1 with exit code $2"
    echo "Last command was: $BASH_COMMAND"
}
trap 'cleanup $LINENO $?' EXIT

echo "Running raspi wordclock config script..."

# Set environment variables for non-interactive installation
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Update and upgrade system
echo "=== STEP 1: Updating packages ==="
sudo apt-get update
sudo apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
echo "Package update completed successfully."

# Install required packages
echo "=== STEP 2: Installing required packages ==="
sudo apt-get install -y python3-pip scons curl npm iptables-persistent -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
echo "Required packages installed successfully."

# Install Node-RED
echo "=== STEP 3: Installing Node-RED ==="
curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered -o /tmp/update-nodejs-and-nodered.sh
if [ -f /tmp/update-nodejs-and-nodered.sh ]; then
    echo "Running Node-RED installer..."
    # Temporarily disable exit on error for this section
    set +e
    sudo -u pi bash /tmp/update-nodejs-and-nodered.sh --confirm-install --confirm-pi --nodered-user=pi
    NODERED_EXIT_CODE=$?
    set -e
    
    rm /tmp/update-nodejs-and-nodered.sh
    
    if [ $NODERED_EXIT_CODE -ne 0 ]; then
        echo "Warning: Node-RED installation returned exit code $NODERED_EXIT_CODE, but continuing..."
    else
        echo "Node-RED installation completed successfully."
    fi
else
    echo "Error: Failed to download Node-RED installer script."
    exit 1
fi

# Install Node-RED nodes
echo "=== STEP 4: Installing Node-RED nodes ==="
if [ -d /home/pi/.node-red ]; then
    cd /home/pi/.node-red
    echo "Installing node-red-dashboard..."
    sudo -u pi npm install node-red-dashboard || echo "Warning: Failed to install node-red-dashboard"
    echo "Installing node-red-contrib-amazon-echo..."
    sudo -u pi npm install node-red-contrib-amazon-echo || echo "Warning: Failed to install node-red-contrib-amazon-echo"
else
    echo "Warning: Node-RED directory not found, creating it..."
    sudo -u pi mkdir -p /home/pi/.node-red
    cd /home/pi/.node-red
    sudo -u pi npm init -y
    sudo -u pi npm install node-red-dashboard node-red-contrib-amazon-echo || echo "Warning: Failed to install some Node-RED nodes"
fi

echo "Enabling Node-RED service..."
sudo systemctl enable nodered.service || echo "Warning: Failed to enable Node-RED service"

# Install Python package for LEDs
echo "=== STEP 5: Installing Python rpi_ws281x ==="
echo "Installing Python rpi_ws281x..."
# Try pip3 with --break-system-packages flag for Raspberry Pi OS
sudo pip3 install rpi_ws281x --break-system-packages || {
    echo "Warning: pip3 installation failed, trying alternative method..."
    # Alternative: try installing via apt if available
    sudo apt-get install -y python3-rpi-ws281x || {
        echo "Warning: apt installation also failed, trying virtual environment approach..."
        # Create a system-wide virtual environment as fallback
        sudo python3 -m venv /opt/wordclock-venv
        sudo /opt/wordclock-venv/bin/pip install rpi_ws281x || echo "Warning: All Python installation methods failed"
    }
}

# Configure iptables
echo "=== STEP 6: Configuring iptables ==="
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo iptables -t nat -A OUTPUT -o lo -p tcp --dport 80 -j REDIRECT --to-port 8980
sudo bash -c "iptables-save > /etc/iptables/rules.v4"
sudo bash -c "ip6tables-save  > /etc/iptables/rules.v6"
echo "iptables configuration completed successfully."

# Download wordclock scripts
echo "=== STEP 7: Setting up wordclock scripts ==="
mkdir -p /home/pi/wordclock
cd /home/pi/wordclock
curl -o changeToWifi.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/changeToWifi.sh
curl -o changeToAp.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/changeToAp.sh
chmod +x changeToWifi.sh changeToAp.sh
echo "Wordclock scripts downloaded successfully."

# Create persistent config file if it doesn't exist
CONFIG_FILE="/home/pi/wordclock/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  echo '{
  "wifi_ssid": "",
  "wifi_password": "",
  "ap_ssid": "WordclockNet",
  "ap_password": "WCKey2580",
  "timezone": "Europe/Berlin",
  "brightness": 100
}' > "$CONFIG_FILE"
  chown pi:pi "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  echo "Created default config at $CONFIG_FILE"
else
  echo "Config file $CONFIG_FILE already exists, not overwriting."
fi

# Download update script
echo "=== STEP 8: Downloading update script ==="
cd /home/pi
curl -o pull_update.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/pull_update.sh
chmod +x pull_update.sh
echo "Update script downloaded successfully."

# Download and run setup script for hotspot and wlan
echo "=== STEP 9: Creating hotspot and wlan services ==="
curl -o setup_wlan_and_AP_modes.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/setup_wlan_and_AP_modes.sh
chmod +x setup_wlan_and_AP_modes.sh
sudo bash setup_wlan_and_AP_modes.sh -s KamelZuVermieten -p 1235813213455.81 -a WordclockNet -r WCKey2580 -d
echo "Hotspot and wlan services configured successfully."

echo "=== INSTALLATION COMPLETE ==="
echo "Installation complete. Please reboot now by entering: sudo reboot now"
