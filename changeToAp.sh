#!/bin/bash
sudo systemctl start wpa_supplicant@ap0.service
sleep 10
node-red-restart
