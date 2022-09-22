
#!/bin/bash
#wordclock install script
echo "Running raspi wordclock config script..."
echo "updating packages..."
sudo apt-get update && sudo apt-get upgrade -y
echo "installing node-red..."
curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered >tmp.sh
sudo -u pi bash tmp.sh --confirm-install --confirm-pi
rm tmp.sh
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
sudo iptables -t nat -A OUTPUT -o lo -p tcp --dport 80 -j REDIRECT --to-port 8980
sudo apt-get install iptables-persistent -y


echo "downloading github files..."
cd
curl \-H 'Authorization: Bearer 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' \-H 'Accept: application/vnd.github.v3.raw' \ -L https://api.github.com/repos/S-A-M-J/wordclock/contents/pull_update_script.sh >pull-update.sh
echo "creating hotspot and wlan services"

