#!/bin/bash
sudo systemctl start wordclock-station
sleep 10
node-red-restart
