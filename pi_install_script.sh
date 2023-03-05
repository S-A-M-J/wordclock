
#!/bin/bash
#wordclock install script
echo "Running raspi wordclock config script..."
echo "updating packages..."
sudo apt-get update && sudo apt-get upgrade -y
echo "installing node-red..."
curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered >tmp.sh
sudo -u pi bash tmp.sh --confirm-install --confirm-pi --nodered-user=pi
sudo rm tmp.sh
cd
cd /home/pi/.node-red
echo "installing node red nodes..."
npm i node-red-dashboard
npm install node-red-contrib-amazon-echo
sudo systemctl enable nodered.service
cd
echo "installing packages..."
PACKAGES="python3-pip"
sudo apt-get install $PACKAGES -y
sudo apt-get install scons
sudo pip install rpi_ws281x

#iptables install
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo apt-get -y install iptables-persistent

sudo iptables -t nat -A OUTPUT -o lo -p tcp --dport 80 -j REDIRECT --to-port 8980
sudo bash -c "iptables-save > /etc/iptables/rules.v4"
sudo bash -c "ip6tables-save  > /etc/iptables/rules.v6"

cd
mkdir /home/pi/wordclock
cd /home/pi/wordclock
sudo curl -o changeToWifi.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/changeToWifi.sh
sudo curl -o changeToAp.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/changeToAp.sh

cd
echo "downloading github files..."
cd /home/pi
sudo curl -o pull-update.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/pull_update.sh
echo "creating hotspot and wlan services"
cd
curl -o setup_wlan_and_AP_modes.sh h https://raw.githubusercontent.com/S-A-M-J/wordclock/main/setup_wlan_and_AP_modes.sh
sudo bash setup_wlan_and_AP_modes.sh -s KamelZuVermieten -p 1235813213455.81 -a WordclockNet -r WCKey2580 -d
echo "installing change scripts...."
echo "please reboot now by entering sudo reboot now"
