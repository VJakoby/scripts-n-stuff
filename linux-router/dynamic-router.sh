#!/bin/bash
# dynamic-router.sh — Dynamic WAN + static LAN router for VMs
# Usage: ./dynamic-router.sh <LAN_IFACE> <LAN_IP/CIDR> <PRIMARY_DNS> <SECONDARY_DNS>

set -e

# === Script arguments ===
if [ $# -ne 4 ]; then
    echo "Usage: $0 <LAN_IFACE> <LAN_IP/CIDR> <PRIMARY_DNS> <SECONDARY_DNS>"
    exit 1
fi

LAN_IFACE="$1"
LAN_IP_CIDR="$2"
PRIMARY_DNS="$3"
SECONDARY_DNS="$4"

# === Ensure required packages are installed ===
REQUIRED_PKGS=(dnsmasq iptables iptables-persistent curl)
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        echo "[INFO] Installing missing package: $pkg"
        sudo apt-get update
        sudo apt-get install -y "$pkg"
    fi
done

# === Detect WAN dynamically ===
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

# === OUTPUT rules ===
sudo iptables -A OUTPUT -o $WAN_IFACE -j ACCEPT
sudo iptables -A OUTPUT -o $LAN_IFACE -j ACCEPT

# === FORWARD rules (LAN → WAN) ===
sudo iptables -A FORWARD -i $LAN_IFACE -o $WAN_IFACE -j ACCEPT
sudo iptables -A FORWARD -i $WAN_IFACE -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT

# === NAT ===
sudo iptables -t nat -A POSTROUTING -o $WAN_IFACE -j MASQUERADE

# === Netplan config for LAN interface + upstream DNS ===
sudo tee /etc/netplan/99-dynamic-router.yaml > /dev/null <<EOF
network:
  version: 2
  ethernets:
    $LAN_IFACE:
      addresses:
        - $LAN_IP_CIDR
      dhcp4: no
    $WAN_IFACE:
      dhcp4: yes
      nameservers:
        addresses:
          - $PRIMARY_DNS
          - $SECONDARY_DNS
EOF

sudo netplan apply

# === dnsmasq for LAN DNS only ===
if command -v dnsmasq &> /dev/null; then
    echo "[INFO] Configuring dnsmasq for LAN DNS..."
    sudo systemctl stop dnsmasq || true
    sudo tee /etc/dnsmasq.d/lan.conf > /dev/null <<EOF
interface=$LAN_IFACE
listen-address=${LAN_IP_CIDR%/*}
bind-interfaces
server=$PRIMARY_DNS
server=$SECONDARY_DNS
domain-needed
bogus-priv
EOF
    sudo systemctl restart dnsmasq
fi

# === Save iptables rules ===
sudo mkdir -p /etc/iptables
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null

echo "[INFO] Router setup complete. LAN=${LAN_IP_CIDR%/*} via $LAN_IFACE, WAN=$WAN_IFACE"

# === Optional: WAN watcher loop ===
CURRENT_WAN=$WAN_IFACE
while true; do
    NEW_WAN=$(ip route | awk '/^default/ {print $5; exit}')
    if [ "$NEW_WAN" != "$CURRENT_WAN" ]; then
        echo "[INFO] WAN interface changed: $CURRENT_WAN -> $NEW_WAN"
        # Remove old NAT & forwarding
        sudo iptables -t nat -D POSTROUTING -o $CURRENT_WAN -j MASQUERADE
        sudo iptables -D FORWARD -i $LAN_IFACE -o $CURRENT_WAN -j ACCEPT
        sudo iptables -D FORWARD -i $CURRENT_WAN -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
        sudo iptables -D OUTPUT -o $CURRENT_WAN -j ACCEPT
        # Apply rules for new WAN
        sudo iptables -t nat -A POSTROUTING -o $NEW_WAN -j MASQUERADE
        sudo iptables -A FORWARD -i $LAN_IFACE -o $NEW_WAN -j ACCEPT
        sudo iptables -A FORWARD -i $NEW_WAN -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
        sudo iptables -A OUTPUT -o $NEW_WAN -j ACCEPT
        CURRENT_WAN=$NEW_WAN
        echo "[INFO] WAN rules updated for $NEW_WAN"
    fi
    sleep 10
done
