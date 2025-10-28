#!/bin/bash
# dynamic-router.sh — Automatic Dynamic WAN + static LAN router for VMs
# Usage: ./dynamic-router.sh --install-service <LAN_IFACE> <LAN_IP/CIDR>                                  
#        ./dynamic-router.sh --run <LAN_IFACE> <LAN_IP/CIDR>                                                

set -e

# Hardcoded fallback DNS servers
FALLBACK_DNS1="1.1.1.1"
FALLBACK_DNS2="8.8.8.8"

# === Parse arguments ===
if [ $# -lt 3 ]; then
    echo "Usage:"
    echo "  $0 --install-service <LAN_IFACE> <LAN_IP/CIDR>"
    echo "  $0 --run <LAN_IFACE> <LAN_IP/CIDR>"
    exit 1
fi

MODE="$1"
LAN_IFACE="$2"
LAN_IP_CIDR="$3"
LAN_IP="${LAN_IP_CIDR%/*}"

# === Install service mode ===
if [ "$MODE" == "--install-service" ]; then
    echo "[INFO] Installing dynamic-router service..."
    
    # Copy script to /usr/local/bin
    SCRIPT_PATH="$(readlink -f "$0")"
    sudo cp "$SCRIPT_PATH" /usr/local/bin/dynamic-router.sh
    sudo chmod +x /usr/local/bin/dynamic-router.sh
    
    # Create systemd service
    sudo tee /etc/systemd/system/dynamic-router.service > /dev/null <<EOF
[Unit]
Description=Dynamic VM Router
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/dynamic-router.sh --run $LAN_IFACE $LAN_IP_CIDR
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start
    sudo systemctl daemon-reload
    sudo systemctl enable dynamic-router.service
    sudo systemctl start dynamic-router.service
    
    echo "[INFO] Service installed and started."
    echo "[INFO] Check status with: sudo systemctl status dynamic-router.service"
    echo "[INFO] View logs with: sudo journalctl -u dynamic-router.service -f"
    exit 0
fi

# === Run mode ===
if [ "$MODE" != "--run" ]; then
    echo "[ERROR] Invalid mode: $MODE"
    exit 1
fi

echo "[INFO] Starting dynamic router setup..."
echo "[INFO] LAN Interface: $LAN_IFACE"
echo "[INFO] LAN IP: $LAN_IP_CIDR"

# === Ensure required packages are installed ===
REQUIRED_PKGS=(dnsmasq iptables iptables-persistent curl net-tools)
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        echo "[INFO] Installing missing package: $pkg"
        sudo apt-get update
        sudo apt-get install -y "$pkg"
    fi
done

# === Wait for LAN interface ===
echo "[INFO] Waiting for LAN interface $LAN_IFACE..."
timeout=30
while [ $timeout -gt 0 ]; do
    if ip link show "$LAN_IFACE" &> /dev/null; then
        echo "[INFO] LAN interface $LAN_IFACE is available"
        break
    fi
    sleep 1
    ((timeout--))
done
if [ $timeout -eq 0 ]; then
    echo "[ERROR] LAN interface $LAN_IFACE not found after 30 seconds"
    exit 1
fi

# === Configure LAN interface with static IP ===
echo "[INFO] Configuring static IP on $LAN_IFACE..."
sudo ip addr flush dev "$LAN_IFACE"
sudo ip addr add "$LAN_IP_CIDR" dev "$LAN_IFACE"
sudo ip link set "$LAN_IFACE" up

# Persistent netplan config
echo "[INFO] Creating persistent netplan configuration..."
sudo tee /etc/netplan/99-router-lan.yaml > /dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $LAN_IFACE:
      addresses:
        - $LAN_IP_CIDR
      dhcp4: no
      dhcp6: no
      optional: false
EOF
sudo netplan apply

# === Detect WAN dynamically ===
echo "[INFO] Detecting WAN interface..."
timeout=30
while [ $timeout -gt 0 ]; do
    WAN_IFACE=$(ip route | awk '/^default/ {print $5; exit}')
    if [ -n "$WAN_IFACE" ] && [ "$WAN_IFACE" != "$LAN_IFACE" ]; then
        echo "[INFO] Detected WAN interface: $WAN_IFACE"
        break
    fi
    sleep 1
    ((timeout--))
done
if [ -z "$WAN_IFACE" ]; then
    echo "[ERROR] No WAN interface with default route found after 30 seconds"
    exit 1
fi

# === Enable IP forwarding ===
echo "[INFO] Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-router.conf > /dev/null

# === Configure iptables ===
echo "[INFO] Configuring iptables..."
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -i $LAN_IFACE -j ACCEPT
sudo iptables -A INPUT -i $WAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -p icmp -j ACCEPT
sudo iptables -A FORWARD -i $LAN_IFACE -o $WAN_IFACE -j ACCEPT
sudo iptables -A FORWARD -i $WAN_IFACE -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o $WAN_IFACE -j MASQUERADE
sudo mkdir -p /etc/iptables
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
echo "[INFO] Iptables configured and saved"

# === Function to update dnsmasq upstream based on WAN DNS ===
update_dnsmasq_upstream() {
    WAN_DNS_SERVERS=$(nmcli dev show "$CURRENT_WAN" | awk '/IP4.DNS/ {print $2}')
    DNSMASQ_SERVERS=""
    for dns in $WAN_DNS_SERVERS; do
        DNSMASQ_SERVERS+="server=$dns\n"
    done

    sudo tee /etc/dnsmasq.d/lan.conf > /dev/null <<EOF
interface=$LAN_IFACE
listen-address=$LAN_IP
bind-interfaces

# Upstream DNS (dynamic from WAN)
$DNSMASQ_SERVERS

# Static fallback
server=$FALLBACK_DNS1
server=$FALLBACK_DNS2

no-resolv
domain-needed
bogus-priv
cache-size=1000

# DHCP settings
dhcp-range=${LAN_IP%.*}.100,${LAN_IP%.*}.250,12h
dhcp-option=option:router,$LAN_IP
dhcp-option=option:dns-server,$LAN_IP
dhcp-authoritative

log-dhcp
EOF

    sudo systemctl restart dnsmasq
    echo "[INFO] dnsmasq upstream DNS updated for WAN: $CURRENT_WAN"
}

# === WAN watcher and LAN IP enforcement ===
CURRENT_WAN=$WAN_IFACE
update_dnsmasq_upstream

ensure_lan_ip() {
    CURRENT_LAN_IP=$(ip addr show "$LAN_IFACE" 2>/dev/null | grep "inet " | awk '{print $2}')
    if [ "$CURRENT_LAN_IP" != "$LAN_IP_CIDR" ]; then
        echo "[WARNING] LAN IP missing or incorrect. Reapplying..."
        sudo ip addr flush dev "$LAN_IFACE" 2>/dev/null || true
        sudo ip addr add "$LAN_IP_CIDR" dev "$LAN_IFACE"
        sudo ip link set "$LAN_IFACE" up
        echo "[INFO] LAN IP restored: $LAN_IP_CIDR"
    fi
}

echo "[INFO] Starting WAN interface monitor..."
while true; do
    sleep 10

    ensure_lan_ip

    NEW_WAN=$(ip route | awk '/^default/ {print $5; exit}')

    if [ -z "$NEW_WAN" ] || [ "$NEW_WAN" == "$LAN_IFACE" ]; then
        continue
    fi

    if [ "$NEW_WAN" != "$CURRENT_WAN" ]; then
        echo "[INFO] WAN interface changed: $CURRENT_WAN -> $NEW_WAN"

        # Remove old NAT & forwarding rules
        sudo iptables -t nat -D POSTROUTING -o $CURRENT_WAN -j MASQUERADE 2>/dev/null || true
        sudo iptables -D FORWARD -i $LAN_IFACE -o $CURRENT_WAN -j ACCEPT 2>/dev/null || true
        sudo iptables -D FORWARD -i $CURRENT_WAN -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

        # Apply rules for new WAN
        sudo iptables -t nat -A POSTROUTING -o $NEW_WAN -j MASQUERADE
        sudo iptables -A FORWARD -i $LAN_IFACE -o $NEW_WAN -j ACCEPT
        sudo iptables -A FORWARD -i $NEW_WAN -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT

        sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null

        # Update dnsmasq for new WAN
        CURRENT_WAN=$NEW_WAN
        update_dnsmasq_upstream
    fi
done
