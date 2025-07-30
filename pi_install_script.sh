
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
sudo apt-get install -y python3-pip scons curl npm iptables-persistent network-manager uuid-runtime -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"


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

# Ensure iptables-persistent is properly configured
echo "Configuring iptables-persistent..."
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

# Reconfigure the package to apply the debconf settings
sudo dpkg-reconfigure -f noninteractive iptables-persistent

# Create iptables directory if it doesn't exist
sudo mkdir -p /etc/iptables

# Add the NAT rules for port redirection
echo "Adding iptables NAT rules..."

# Redirect external traffic from port 80 to Node-RED dashboard (port 1880)
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 1880

# Redirect local loopback traffic from port 80 to Node-RED dashboard (port 1880)  
sudo iptables -t nat -A OUTPUT -o lo -p tcp --dport 80 -j REDIRECT --to-port 1880

# Allow traffic to Node-RED dashboard port
sudo iptables -A INPUT -p tcp --dport 1880 -j ACCEPT

# Allow traffic to Amazon Echo hub port (if needed)
sudo iptables -A INPUT -p tcp --dport 8980 -j ACCEPT

# Verify the rules were added
if sudo iptables -t nat -L PREROUTING | grep -q "REDIRECT.*1880"; then
    echo "✓ External port 80→1880 redirect rule added successfully."
else
    echo "✗ Warning: Failed to add external redirect rule."
fi

if sudo iptables -t nat -L OUTPUT | grep -q "REDIRECT.*1880"; then
    echo "✓ Local port 80→1880 redirect rule added successfully."
else
    echo "✗ Warning: Failed to add local redirect rule."
fi

# Save the rules
echo "Saving iptables rules..."
if sudo iptables-save > /tmp/rules.v4.tmp && sudo mv /tmp/rules.v4.tmp /etc/iptables/rules.v4; then
    echo "IPv4 iptables rules saved successfully."
else
    echo "Warning: Failed to save IPv4 iptables rules."
fi

if sudo ip6tables-save > /tmp/rules.v6.tmp && sudo mv /tmp/rules.v6.tmp /etc/iptables/rules.v6; then
    echo "IPv6 iptables rules saved successfully."
else
    echo "Warning: Failed to save IPv6 iptables rules."
fi

# Ensure proper permissions
sudo chmod 644 /etc/iptables/rules.v4 /etc/iptables/rules.v6 2>/dev/null || echo "Warning: Could not set iptables file permissions."

# Restart netfilter-persistent to load the rules
sudo systemctl restart netfilter-persistent || echo "Warning: Failed to restart netfilter-persistent service."

echo "iptables configuration completed."


# Download update script
echo "=== STEP 7: Downloading update script ==="
cd /home/pi
curl -o pull_update.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/pull_update.sh
chmod +x pull_update.sh
echo "Update script downloaded successfully."

# Download and run setup script for hotspot and wlan
echo "=== STEP 8: Creating hotspot and wlan services ==="
curl -o setup_wlan_and_AP_modes.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/setup_wlan_and_AP_modes.sh
chmod +x setup_wlan_and_AP_modes.sh

# Detect current WiFi connection for display purposes
CURRENT_WIFI=""
if systemctl is-active --quiet NetworkManager; then
    echo "Detecting current WiFi connection via NetworkManager..."
    CURRENT_WIFI=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2 2>/dev/null || echo "")
fi

# Fallback to iwgetid if NetworkManager doesn't show connection
if [ -z "$CURRENT_WIFI" ]; then
    CURRENT_WIFI=$(iwgetid -r 2>/dev/null || echo "Unknown")
fi

echo "Setting up wordclock services using existing WiFi configuration..."
echo "Current WiFi network: $CURRENT_WIFI"

# Run setup script without WiFi credentials (will use existing NetworkManager config)
sudo bash setup_wlan_and_AP_modes.sh
echo "Wordclock services setup completed successfully."

echo ""
echo "=== SETUP SUMMARY ==="
echo "The wordclock is now configured with automatic WiFi management:"
echo "• Home WiFi: $CURRENT_WIFI (using existing configuration)"
echo "• Fallback Hotspot: WordclockNet (password: WCKey2580)"
echo "• Network Manager: $(systemctl is-active NetworkManager)"
echo "• After reboot, it will automatically try to connect to your existing WiFi"
echo "• If WiFi fails, it will create the hotspot automatically"
echo "• Access the wordclock at http://wordclock.local or http://192.168.4.1 (in hotspot mode)"

# pull update script
echo "=== STEP 10: Downloading and running pull update script ==="
sudo bash pull_update.sh

echo ""
echo "=== FINAL VERIFICATION ==="
echo "Checking iptables configuration..."

if sudo iptables -t nat -L PREROUTING | grep -q "REDIRECT.*1880"; then
    echo "✓ External port 80→1880 redirect rule is active"
else
    echo "✗ External port 80→1880 redirect rule is missing"
fi

if sudo iptables -t nat -L OUTPUT | grep -q "REDIRECT.*1880"; then
    echo "✓ Local port 80→1880 redirect rule is active"
else
    echo "✗ Local port 80→1880 redirect rule is missing"
fi

if sudo iptables -L INPUT | grep -q "ACCEPT.*1880"; then
    echo "✓ Node-RED dashboard port 1880 is open"
else
    echo "✗ Node-RED dashboard port 1880 access rule missing"
fi

if [ -f /etc/iptables/rules.v4 ]; then
    echo "✓ iptables rules file exists"
else
    echo "✗ iptables rules file missing"
fi

echo "Checking services..."
echo "• NetworkManager: $(systemctl is-active NetworkManager)"
echo "• avahi-daemon: $(systemctl is-active avahi-daemon)"
echo "• netfilter-persistent: $(systemctl is-active netfilter-persistent)"

echo ""
echo "=== INSTALLATION COMPLETE ==="
echo "Installation complete. Please reboot now by entering: sudo reboot now"
echo ""
echo "After reboot, you should be able to access:"
echo "• http://wordclock.local (if on same network) - redirects to Node-RED dashboard"
echo "• http://wordclock.local:1880 (direct Node-RED dashboard access)"
echo "• http://192.168.4.1 (if connected to WordclockNet hotspot)"
echo "• Port 8980 is used for Amazon Echo/Alexa integration"
