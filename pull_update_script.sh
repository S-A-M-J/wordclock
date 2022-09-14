
#!/bin/bash
#wordclock update python files script
echo "deleting old files if existent"
if [ -d wordclock]; then
	sudo rm -r wordclock
fi
mkdir -m 777 wordclock
echo "Updating python files from github..."
echo "downloading new files..."
cd wordclock
sudo curl \-H 'Authorization: Bearer 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' \-H 'Accept: application/vnd.github.v3.raw' \ -L https://api.github.com/repos/S-A-M-J/wordclock/contents/changeToWifi.sh >changeToWifi.sh
sudo curl \-H 'Authorization: Bearer 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' \-H 'Accept: application/vnd.github.v3.raw' \ -L https://api.github.com/repos/S-A-M-J/wordclock/contents/changeToAp.sh >changeToAp.sh
sudo curl \-H 'Authorization: Bearer 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' \-H 'Accept: application/vnd.github.v3.raw' \ -L https://api.github.com/repos/S-A-M-J/wordclock/contents/wordclock.py >wordclock.py 
cd
echo "downloading flow file..."
cd /home/pi/.node-red
sudo rm flows.json
cd
curl \-H 'Authorization: Bearer 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' \-H 'Accept: application/vnd.github.v3.raw' \ -L https://api.github.com/repos/S-A-M-J/wordclock/contents/node-red-flows-wordclock.json >flows.json

sudo touch flows.json
sudo mv flows.json /home/pi/.node-red/flows.json
cd 

node-red-restart


