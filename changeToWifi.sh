#!/bin/bash
sudo systemctl start wpa_supplicant@wlan0.service
sleep 10
node-red-restart
