#!/bin/bash

# Check if two arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <SSID> <PASSWORD>"
    exit 1
fi

ssid=$1
pass=$2

sudo service NetworkManager start &
sudo ifconfig wlan0 up
sudo nmcli dev wifi connect $ssid password $pass ifname wlan0
