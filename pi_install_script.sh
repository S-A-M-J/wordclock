
#!/bin/bash
#wordclock install script
echo "Running raspi wordclock config script..."
echo "updating packages..."
sudo apt-get update && sudo apt-get upgrade -y
echo "installing node-red..."
curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered >tmp.sh
sudo -u pi bash tmp.sh
rm tmp.sh
sudo -u pi node-red-start
wait(60)
sudo -u pi node-red-stop
cd
cd /home/pi/.node-red
echo "installing node red nodes..."
npm i node-red-dashboard
npm install node-red-contrib-amazon-echo
sudo systemctl enable nodered.service

#node-red-start

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
# disable debian networking and dhcpcd
sudo systemctl mask networking.service dhcpcd.service
sudo mv /etc/network/interfaces /etc/network/interfaces~
sudo sed -i '1i resolvconf=NO' /etc/resolvconf.conf

# enable systemd-networkd
sudo systemctl enable systemd-networkd.service systemd-resolved.service
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

#setup wlan0
sudo bash -c 'cat >/etc/wpa_supplicant/wpa_supplicant-wlan0.conf' <<EOF
country=DE
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="KamelZuVermieten"
    psk="1235813213455.81"
}
EOF
sudo chmod 600 /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
sudo systemctl disable wpa_supplicant.service
sudo systemctl enable wpa_supplicant@wlan0.service

#setup ap0
sudo bash -c 'cat > /etc/wpa_supplicant/wpa_supplicant-ap0.conf' <<EOF
country=DE
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="WordclockNet"
    mode=2
    key_mgmt=WPA-PSK
    proto=RSN WPA
    psk="wclpasskey"
    frequency=2412
}
EOF

sudo chmod 600 /etc/wpa_supplicant/wpa_supplicant-ap0.conf

sudo bash -c 'cat > /etc/systemd/network/08-wlan0.network' <<EOF
[Match]
Name=wlan0
[Network]
DHCP=yes
EOF

sudo bash -c 'cat > /etc/systemd/network/12-ap0.network' <<EOF
[Match]
Name=ap0
[Network]
Address=192.168.4.1/24
DHCPServer=yes
[DHCPServer]
DNS=84.200.69.80 1.1.1.1
EOF

sudo systemctl disable wpa_supplicant@ap0.service
sudo systemctl edit --full wpa_supplicant@ap0.service

# insert modification of file 
#sudo mkdir -p /etc/systemd/system/wpa_supplicant@ap0.service.d/
#sudo sh -c "cat > /etc/systemd/system/wpa_supplicant@ap0.service.d/override.conf <<EOF
#[Unit]
#Description=WPA supplicant daemon (interface-specific version)
#Requires=sys-subsystem-net-devices-wlan0.device
#After=sys-subsystem-net-devices-wlan0.device
#Conflicts=wpa_supplicant@wlan0.service
#Before=network.target
#Wants=network.target

# NetworkManager users will probably want the dbus version instead.

#[Service]
#Type=simple
#ExecStartPre=/sbin/iw dev wlan0 interface add ap0 type __ap
#ExecStart=
#ExecStart=/sbin/wpa_supplicant -c/etc/wpa_supplicant/wpa_supplicant-%I.conf -Dnl80211,wext -i%I
#ExecStopPost=/sbin/iw dev ap0 del

#[Install]
#Alias=multi-user.target.wants/wpa_supplicant@%i.service
#EOF"

#sudo systemctl daemon-reload

#sudo systemctl disable wpa_supplicant@ap0.service
#sudo systemctl enable wpa_supplicant@wlan0.service

#echo "rebooting so set changes..."
#sudo reboot
