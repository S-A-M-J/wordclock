
#!/bin/bash
#wordclock update python files script
echo "deleting old files if existent"
if [ -d wordclock]; then
	sudo rm -r wordclock
fi
sudo mkdir wordclock
echo "Updating python files from github..."
echo "downloading new files..."
curl \-H 'Authorization: Bearer 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' \-H 'Accept: application/vnd.github.v3.raw' \ -L https://api.github.com/repos/S-A-M-J/wordclock/contents/changeToWifi.sh >wordclock/changeToWifi.sh
curl \-H 'Authorization: Bearer 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' \-H 'Accept: application/vnd.github.v3.raw' \ -L https://api.github.com/repos/S-A-M-J/wordclock/contents/changeToAp.sh >wordclock/changeToAp.sh
curl \-H 'Authorization: Bearer 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' \-H 'Accept: application/vnd.github.v3.raw' \ -L https://api.github.com/repos/S-A-M-J/wordclock/contents/wordclock.py >wordclock/wordclock.py 

cd
echo "downloading flow file..."
cd ~/.node-red
rm flows.json
cd
curl \-H 'Authorization: Bearer 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' \-H 'Accept: application/vnd.github.v3.raw' \ -L https://api.github.com/repos/S-A-M-J/wordclock/contents/node-red-flows-wordclock.json >flows.json

touch flows.json
mv flows.json ~/.node-red/flows.json
cd 
cd wordclock
rm changeToWifi


