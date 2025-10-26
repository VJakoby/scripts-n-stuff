#!/bin/bash
# dynamic-router.sh — Fully dynamic WAN + static LAN router for VMs with persistence

set -e

# === Configurable fixed LAN interface ===
LAN_IFACE="ens34"
LAN_IP="192.168.100.1"

# === Detect initial WAN dynamically ===
WAN_IFACE=$(ip route | awk '/^default/ {print $5; exit}')
if [ -z "$WAN_IFACE" ]; then
    echo "[ERROR] No default route found. Connect WAN first."
    exit 1
fi
echo "[INFO] Detected WAN interface: $WAN_IFACE"

# === Enable IP forwarding ===
sudo sysctl -w net.ipv4.ip_forward=1

# === Flush existing iptables rules ===
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X

# === Default policies ===
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

# === INPUT rules ===
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -i $LAN_IFACE -j ACCEPT
sudo iptables -A INPUT -i $WAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -p icmp -j ACCEPT

# === OUTPUT rules for router itself ===
sudo iptables -A OUTPUT -o $WAN_IFACE -j ACCEPT
sudo iptables -A OUTPUT -o $LAN_IFACE -j ACCEPT

# === FORWARD rules (LAN → WAN) ===
sudo iptables -A FORWARD -i $LAN_IFACE -o $WAN_IFACE -j ACCEPT
sudo iptables -A FORWARD -i $WAN_IFACE -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT

# === NAT ===
sudo iptables -t nat -A POSTROUTING -o $WAN_IFACE -j MASQUERADE

# === dnsmasq for LAN DNS only ===
if command -v dnsmasq &> /dev/null; then
    echo "[INFO] Ensuring dnsmasq is running for LAN DNS..."
    
    # Stop any running instance first
    sudo systemctl stop dnsmasq || true
    
    # Restart dnsmasq (assumes lan.conf is already in /etc/dnsmasq.d/)
    sudo systemctl restart dnsmasq
fi

# === Save iptables rules for persistence ===
sudo mkdir -p /etc/iptables
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null

echo "[INFO] Router setup complete. LAN=$LAN_IP via $LAN_IFACE, WAN=$WAN_IFACE"

# === WAN watcher loop ===
CURRENT_WAN=$WAN_IFACE
while true; do
    NEW_WAN=$(ip route | awk '/^default/ {print $5; exit}')
    if [ "$NEW_WAN" != "$CURRENT_WAN" ]; then
        echo "[INFO] WAN interface changed: $CURRENT_WAN -> $NEW_WAN"

        # Remove old NAT & forwarding for previous WAN
        sudo iptables -t nat -D POSTROUTING -o $CURRENT_WAN -j MASQUERADE
        sudo iptables -D FORWARD -i $LAN_IFACE -o $CURRENT_WAN -j ACCEPT
        sudo iptables -D FORWARD -i $CURRENT_WAN -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
        sudo iptables -D OUTPUT -o $CURRENT_WAN -j ACCEPT

        # Apply rules for new WAN
        sudo iptables -A FORWARD -i $LAN_IFACE -o $NEW_WAN -j ACCEPT
        sudo iptables -A FORWARD -i $NEW_WAN -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
        sudo iptables -t nat -A POSTROUTING -o $NEW_WAN -j MASQUERADE
        sudo iptables -A OUTPUT -o $NEW_WAN -j ACCEPT

        CURRENT_WAN=$NEW_WAN
        echo "[INFO] WAN rules updated for $NEW_WAN"
    fi
    sleep 10
done
