
#!/bin/bash
# wordclock install script - improved for Raspberry Pi
set -e

echo "Running raspi wordclock config script..."

# Update and upgrade system
echo "Updating packages..."
sudo apt-get update && sudo apt-get upgrade -y

# Install required packages
echo "Installing required packages..."
sudo apt-get install -y python3-pip scons curl npm iptables-persistent

# Install Node-RED
echo "Installing Node-RED..."
curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered -o /tmp/update-nodejs-and-nodered.sh
sudo -u pi bash /tmp/update-nodejs-and-nodered.sh --confirm-install --confirm-pi --nodered-user=pi
rm /tmp/update-nodejs-and-nodered.sh

# Install Node-RED nodes
echo "Installing Node-RED nodes..."
cd /home/pi/.node-red
sudo -u pi npm install node-red-dashboard node-red-contrib-amazon-echo
sudo systemctl enable nodered.service

# Install Python package for LEDs
echo "Installing Python rpi_ws281x..."
sudo pip3 install rpi_ws281x

# Configure iptables
echo "Configuring iptables..."
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo iptables -t nat -A OUTPUT -o lo -p tcp --dport 80 -j REDIRECT --to-port 8980
sudo bash -c "iptables-save > /etc/iptables/rules.v4"
sudo bash -c "ip6tables-save  > /etc/iptables/rules.v6"

# Download wordclock scripts
echo "Setting up wordclock scripts..."
mkdir -p /home/pi/wordclock
cd /home/pi/wordclock
curl -o changeToWifi.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/changeToWifi.sh
curl -o changeToAp.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/changeToAp.sh
chmod +x changeToWifi.sh changeToAp.sh

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
echo "Downloading update script..."
cd /home/pi
curl -o pull_update.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/pull_update.sh
chmod +x pull_update.sh

# Download and run setup script for hotspot and wlan
echo "Creating hotspot and wlan services..."
curl -o setup_wlan_and_AP_modes.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/setup_wlan_and_AP_modes.sh
chmod +x setup_wlan_and_AP_modes.sh
sudo bash setup_wlan_and_AP_modes.sh -s KamelZuVermieten -p 1235813213455.81 -a WordclockNet -r WCKey2580 -d

echo "Installation complete. Please reboot now by entering: sudo reboot now"
