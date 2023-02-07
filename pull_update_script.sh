
#!/bin/bash
#wordclock update python files script
echo "deleting old files if existent"
cd /home/pi
if [ -d wordclock]; then
	sudo rm -r wordclock
fi
mkdir -m 777 /home/pi/wordclock
echo "Updating python files from github..."
echo "downloading new files..."
cd
cd /home/pi/wordclock
sudo bash -c "curl \-H 'Authorization: Bearer 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' \-H 'Accept: application/vnd.github.v3.raw' \ -L https://api.github.com/repos/S-A-M-J/wordclock/contents/changeToWifi.sh >changeToWifi.sh"
sudo bash -c "\-H 'Authorization: Bearer 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' \-H 'Accept: application/vnd.github.v3.raw' \ -L https://api.github.com/repos/S-A-M-J/wordclock/contents/changeToAp.sh >changeToAp.sh"
sudo bash -c "\-H 'Authorization: Bearer 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' \-H 'Accept: application/vnd.github.v3.raw' \ -L https://api.github.com/repos/S-A-M-J/wordclock/contents/wordclock.py >wordclock.py" 
cd
echo "downloading flow file..."
cd /home/pi/.node-red
sudo rm flows.json
cd
sudo bash -c "curl \-H 'Authorization: Bearer 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' \-H 'Accept: application/vnd.github.v3.raw' \ -L https://api.github.com/repos/S-A-M-J/wordclock/contents/node-red-flows-wordclock.json >flows.json"

sudo touch flows.json
sudo mv flows.json /home/pi/.node-red/flows.json
cd 

node-red-restart


