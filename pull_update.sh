
#!/bin/bash
#wordclock update python files script
echo "deleting old files if existent"
cd /home/pi
if [ -d wordclock ]; then
	sudo rm -r wordclock
fi
mkdir -m 777 /home/pi/wordclock
echo "Updating python files from github..."
echo "downloading new files..."
cd
cd /home/pi/wordclock
sudo bash -c "curl -o changeToWifi.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/changeToWifi.sh"
sudo bash -c "curl -o changeToAp.sh https://raw.githubusercontent.com/S-A-M-J/wordclock/main/changeToAp.sh"
sudo bash -c "curl -o wordclock.py https://raw.githubusercontent.com/S-A-M-J/wordclock/main/wordclock.py" 
cd
echo "downloading flow file..."
cd /home/pi/.node-red
sudo rm flows.json
cd
sudo bash -c "curl -o flows.json https://raw.githubusercontent.com/S-A-M-J/wordclock/main/node-red-flows-wordclock.json"

sudo touch flows.json
sudo mv flows.json /home/pi/.node-red/flows.json
cd 

node-red-restart


