#!/bin/bash
sudo systemctl disable wordclock-station.service
sleep 10
node-red-restart
