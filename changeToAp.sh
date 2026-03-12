#!/bin/bash
sudo systemctl start wordclock-ap
sleep 10
node-red-restart
