#!/bin/bash

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

INTERFACE="wlan0"
MON_INTERFACE="mon0"

# Kill interfering processes
echo "[*] Killing interfering processes..."
airmon-ng check kill

# Enable monitor mode
echo "[*] Enabling monitor mode on $INTERFACE..."
airmon-ng start $INTERFACE

# Confirm monitor interface
MON_INTERFACE=$(iwconfig 2>/dev/null | grep "Mode:Monitor" | awk '{print $1}')

if [ -z "$MON_INTERFACE" ]; then
    echo "[!] Failed to enable monitor mode."
    exit 1
fi

echo "[*] Monitor mode enabled on $MON_INTERFACE"

# Start airodump-ng
echo "[*] Starting airodump-ng..."
airodump-ng $MON_INTERFACE
