#!/bin/bash
sudo systemctl enable wordclock-ap.service
sleep 10
node-red-restart
