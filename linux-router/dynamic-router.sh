#!/bin/bash
# dynamic-router.sh — Automatic Dynamic WAN + static LAN router for VMs
# Usage: ./dynamic-router.sh --install-service <LAN_IFACE> <LAN_IP/CIDR>
#        ./dynamic-router.sh --run <LAN_IFACE> <LAN_IP/CIDR>

set -e
                                                                                                                       
# Hardcoded DNS servers                                                                                                
PRIMARY_DNS="1.1.1.1"                                                                                                  
SECONDARY_DNS="8.8.8.8"                                                                                                
                                                                                                               
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

# === Run mode (executed by systemd or manual testing) ===
if [ "$MODE" != "--run" ]; then
    echo "[ERROR] Invalid mode: $MODE"
    exit 1
fi

echo "[INFO] Starting dynamic router setup..."
echo "[INFO] LAN Interface: $LAN_IFACE"
echo "[INFO] LAN IP: $LAN_IP_CIDR"

# === Ensure required packages are installed ===
REQUIRED_PKGS=(dnsmasq iptables iptables-persistent curl)
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        echo "[INFO] Installing missing package: $pkg"
        sudo apt-get update
        sudo apt-get install -y "$pkg"
    fi
done

# === Fix systemd-resolved conflict with dnsmasq ===
echo "[INFO] Configuring DNS resolution to avoid conflicts..."

# Stop systemd-resolved from binding to port 53
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/no-stub.conf > /dev/null <<EOF
[Resolve]
DNSStubListener=no
DNS=$PRIMARY_DNS $SECONDARY_DNS
EOF

# Restart systemd-resolved
sudo systemctl restart systemd-resolved

# Set router's own DNS resolution to use upstream DNS directly
# Remove immutable flag if it exists, then update
sudo chattr -i /etc/resolv.conf 2>/dev/null || true
sudo rm -f /etc/resolv.conf
sudo tee /etc/resolv.conf > /dev/null <<EOF
# Router's own DNS (managed by dynamic-router)
nameserver $PRIMARY_DNS
nameserver $SECONDARY_DNS
EOF

# Make it immutable to prevent overwriting
sudo chattr +i /etc/resolv.conf

# === Wait for LAN interface to be available ===
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

# Flush existing rules
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X

# Default policies
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

# INPUT rules
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -i $LAN_IFACE -j ACCEPT
sudo iptables -A INPUT -i $WAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -p icmp -j ACCEPT

# OUTPUT rules (router's own traffic)
sudo iptables -A OUTPUT -j ACCEPT

# FORWARD rules (LAN → WAN)
sudo iptables -A FORWARD -i $LAN_IFACE -o $WAN_IFACE -j ACCEPT
sudo iptables -A FORWARD -i $WAN_IFACE -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT

# NAT
sudo iptables -t nat -A POSTROUTING -o $WAN_IFACE -j MASQUERADE

# Save iptables rules
sudo mkdir -p /etc/iptables
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null

echo "[INFO] Iptables configured and saved"

# === Configure dnsmasq for LAN DNS only ===
echo "[INFO] Configuring dnsmasq for LAN DNS..."
sudo systemctl stop dnsmasq 2>/dev/null || true

sudo tee /etc/dnsmasq.d/lan.conf > /dev/null <<EOF
# Bind only to LAN interface
interface=$LAN_IFACE
listen-address=$LAN_IP
bind-interfaces

# Upstream DNS servers
server=$PRIMARY_DNS
server=$SECONDARY_DNS

# Don't read /etc/resolv.conf
no-resolv

# Basic security
domain-needed
bogus-priv

# Cache settings
cache-size=1000

# DHCP configuration
# Automatically serve DHCP in the same subnet as the router
# Example: if router is 192.168.100.1/24 → range is 192.168.100.50–192.168.100.150
dhcp-range=${LAN_IP%.*}.50,${LAN_IP%.*}.150,12h

# Gateway and DNS offered to clients
dhcp-option=3,$LAN_IP      # Default gateway
dhcp-option=6,$LAN_IP      # DNS server

# Allow static IPs outside the DHCP range without interference
EOF

# Disable default dnsmasq config that might conflict
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.backup 2>/dev/null || true
sudo touch /etc/dnsmasq.conf

sudo systemctl restart dnsmasq
echo "[INFO] dnsmasq configured and started"

# === Verify router's own internet connectivity ===
echo "[INFO] Testing router's own internet connectivity..."
if curl -s --connect-timeout 5 https://1.1.1.1 > /dev/null; then
    echo "[INFO] ✓ Router has internet access"
else
    echo "[WARNING] Router may not have internet access yet"
fi

echo "[INFO] =========================================="
echo "[INFO] Router setup complete!"
echo "[INFO] =========================================="
echo "[INFO] LAN Interface: $LAN_IFACE"
echo "[INFO] LAN IP: $LAN_IP"
echo "[INFO] WAN Interface: $WAN_IFACE"
echo "[INFO] DNS Servers: $PRIMARY_DNS, $SECONDARY_DNS"
echo "[INFO] =========================================="
echo "[INFO] Configure LAN VMs with:"
echo "[INFO]   IP: 192.168.x.x (same subnet as $LAN_IP_CIDR)"
echo "[INFO]   Gateway: $LAN_IP"
echo "[INFO]   DNS: $LAN_IP"
echo "[INFO] =========================================="

# === WAN watcher loop ===
CURRENT_WAN=$WAN_IFACE
echo "[INFO] Starting WAN interface monitor..."

while true; do
    sleep 10
    
    NEW_WAN=$(ip route | awk '/^default/ {print $5; exit}')
    
    # Skip if no WAN or if it's the LAN interface
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
        
        # Save updated rules
        sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
        
        CURRENT_WAN=$NEW_WAN
        echo "[INFO] WAN rules updated for $NEW_WAN"
    fi
done
