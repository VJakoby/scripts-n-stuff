#!/bin/bash
# dynamic-router.sh — Automatic Dynamic WAN + static LAN router for VMs with VPN support
# Usage: ./dynamic-router.sh --install-service <LAN_IFACE> <LAN_IP/CIDR> [--vpn] [--subnets <file>]
#        ./dynamic-router.sh --run <LAN_IFACE> <LAN_IP/CIDR> [--vpn] [--subnets <file>]
#        ./dynamic-router.sh --reset

set -e

# Hardcoded fallback DNS servers
FALLBACK_DNS1="1.1.1.1"
FALLBACK_DNS2="8.8.8.8"

# Default VPN subnets file location
VPN_SUBNETS_FILE="/etc/router/vpn-subnets.txt"

# VPN routing disabled by default
ENABLE_VPN_ROUTING=false

# === Reset mode ===
if [ "$1" == "--reset" ]; then
    echo "[INFO] ============================================"
    echo "[INFO] RESETTING ROUTER CONFIGURATION"
    echo "[INFO] ============================================"
    
    echo "[INFO] Stopping dynamic-router service if running..."
    sudo systemctl stop dynamic-router.service 2>/dev/null || true
    sudo systemctl disable dynamic-router.service 2>/dev/null || true
    
    echo "[INFO] Flushing iptables rules..."
    sudo iptables -F
    sudo iptables -t nat -F
    sudo iptables -t mangle -F
    sudo iptables -X
    sudo iptables -P INPUT ACCEPT
    sudo iptables -P FORWARD ACCEPT
    sudo iptables -P OUTPUT ACCEPT
    sudo rm -f /etc/iptables/rules.v4
    
    echo "[INFO] Stopping dnsmasq and cleaning config..."
    sudo systemctl stop dnsmasq
    sudo rm -f /etc/dnsmasq.d/lan.conf
    sudo systemctl restart dnsmasq
    
    echo "[INFO] Restoring system DNS to default upstream provided by network..."
    # Remove any forced /etc/resolv.conf immutability
    sudo chattr -i /etc/resolv.conf 2>/dev/null || true
    # Remove manual overrides from dnsmasq or systemd-resolved
    sudo rm -f /etc/dnsmasq.d/lan.conf
    sudo rm -f /etc/systemd/resolved.conf.d/no-stub.conf 2>/dev/null
    # Restart resolvers
    sudo systemctl restart systemd-resolved 2>/dev/null || true
    sudo systemctl restart NetworkManager 2>/dev/null || true
    # If /etc/resolv.conf is still a static file, link it to systemd stub
    if [ ! -L /etc/resolv.conf ]; then
        sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    fi
    echo "[INFO] System DNS restored to default upstream."
    
    echo "[INFO] Flushing LAN interfaces..."
    for iface in $(ip -o link show | awk -F': ' '{print $2}'); do
        sudo ip addr flush dev $iface 2>/dev/null || true
    done
    
    echo "[INFO] Removing custom netplan LAN configuration..."
    sudo rm -f /etc/netplan/99-router-lan.yaml
    sudo netplan apply || true
    
    echo "[INFO] Disabling IP forwarding..."
    sudo sysctl -w net.ipv4.ip_forward=0 2>/dev/null || true
    sudo rm -f /etc/sysctl.d/99-router.conf
    
    echo "[INFO] ============================================"
    echo "[INFO] RESET COMPLETE"
    echo "[INFO] ============================================"
    echo "[INFO] Cleanup complete. System is ready for fresh router script."
    echo "[INFO] You can now run: $0 --install-service <LAN_IFACE> <LAN_IP/CIDR>"
    exit 0
fi

# === Parse arguments ===
if [ $# -lt 3 ]; then
    echo "Usage:"
    echo "  $0 --install-service <LAN_IFACE> <LAN_IP/CIDR> [OPTIONS]"
    echo "  $0 --run <LAN_IFACE> <LAN_IP/CIDR> [OPTIONS]"
    echo "  $0 --reset"
    echo ""
    echo "Options:"
    echo "  --vpn                 Enable VPN routing (monitors and routes VPN interfaces)"
    echo "  --subnets <file>      Path to file containing VPN subnets (one per line)"
    echo "                        Default: /etc/router/vpn-subnets.txt"
    echo ""
    echo "Examples:"
    echo "  $0 --install-service eth1 10.0.0.1/24"
    echo "  $0 --install-service eth1 10.0.0.1/24 --vpn"
    echo "  $0 --run eth1 10.0.0.1/24 --vpn --subnets /etc/openvpn/subnets.txt"
    echo "  $0 --reset"
    exit 1
fi

MODE="$1"
LAN_IFACE="$2"
LAN_IP_CIDR="$3"
LAN_IP="${LAN_IP_CIDR%/*}"

# Parse optional arguments
shift 3
while [ $# -gt 0 ]; do
    case "$1" in
        --vpn)
            ENABLE_VPN_ROUTING=true
            shift
            ;;
        --subnets)
            VPN_SUBNETS_FILE="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] Unknown option: $1"
            exit 1
            ;;
    esac
done

# === Install service mode ===
if [ "$MODE" == "--install-service" ]; then
    echo "[INFO] Installing dynamic-router service..."
    
    SCRIPT_PATH="$(readlink -f "$0")"
    sudo cp "$SCRIPT_PATH" /usr/local/bin/dynamic-router.sh
    sudo chmod +x /usr/local/bin/dynamic-router.sh
    
    sudo mkdir -p /etc/router
    
    if [ ! -f "$VPN_SUBNETS_FILE" ]; then
        sudo tee "$VPN_SUBNETS_FILE" > /dev/null <<EOF
# VPN Subnets Configuration
# Add one subnet per line (CIDR notation)
# Example:
# 10.8.0.0/24
# 192.168.100.0/24
EOF
        echo "[INFO] Created empty VPN subnets file at $VPN_SUBNETS_FILE"
    fi
    
    EXEC_START_CMD="/usr/local/bin/dynamic-router.sh --run $LAN_IFACE $LAN_IP_CIDR"
    if [ "$ENABLE_VPN_ROUTING" = true ]; then
        EXEC_START_CMD="$EXEC_START_CMD --vpn"
        if [ "$VPN_SUBNETS_FILE" != "/etc/router/vpn-subnets.txt" ]; then
            EXEC_START_CMD="$EXEC_START_CMD --subnets $VPN_SUBNETS_FILE"
        fi
    fi
    
    sudo tee /etc/systemd/system/dynamic-router.service > /dev/null <<EOF
[Unit]
Description=Dynamic VM Router with VPN Support
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$EXEC_START_CMD
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable dynamic-router.service
    sudo systemctl start dynamic-router.service
    
    echo "[INFO] Service installed and started."
    if [ "$ENABLE_VPN_ROUTING" = true ]; then
        echo "[INFO] VPN routing: ENABLED"
        echo "[INFO] VPN subnets file: $VPN_SUBNETS_FILE"
        echo "[INFO] Edit VPN subnets with: sudo nano $VPN_SUBNETS_FILE"
        echo "[INFO] Reload config with: sudo systemctl restart dynamic-router.service"
    else
        echo "[INFO] VPN routing: DISABLED"
        echo "[INFO] To enable VPN routing, reinstall with --vpn flag"
    fi
    echo "[INFO] Check status with: sudo systemctl status dynamic-router.service"
    echo "[INFO] View logs with: sudo journalctl -u dynamic-router.service -f"
    echo "[INFO] To reset everything: sudo /usr/local/bin/dynamic-router.sh --reset"
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
echo "[INFO] LAN Gateway (DNS): $LAN_IP"
if [ "$ENABLE_VPN_ROUTING" = true ]; then
    echo "[INFO] VPN Routing: ENABLED"
    echo "[INFO] VPN Subnets File: $VPN_SUBNETS_FILE"
else
    echo "[INFO] VPN Routing: DISABLED (use --vpn to enable)"
fi

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

# === Detect VPN interfaces ===
detect_vpn_interfaces() {
    ip link show | grep -E '^[0-9]+: (tun|tap|ppp|wg|ipsec)[0-9]*:' | awk -F': ' '{print $2}' | awk '{print $1}'
}

# === Read VPN subnets ===
read_vpn_subnets() {
    local subnets_file="$VPN_SUBNETS_FILE"
    local line
    local subnets=()
    if [ -f "$subnets_file" ]; then
        while IFS= read -r line; do
            # Remove comments and whitespace
            line=$(echo "$line" | sed 's/#.*//' | xargs)
            if [ -n "$line" ]; then
                if [[ "$line" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]]; then
                    subnets+=("$line")
                else
                    echo "[WARNING] Invalid CIDR, skipping: $line"
                fi
            fi
        done < "$subnets_file"
    fi
    # Output one subnet per line
    for subnet in "${subnets[@]}"; do
        echo "$subnet"
    done
}

# === Configure VPN routing ===
configure_vpn_routing() {
    echo "[DEBUG] Starting VPN routing configuration..."
    local vpn_ifaces=($(detect_vpn_interfaces))
    local vpn_subnets=($(read_vpn_subnets))
    
    if [ ${#vpn_ifaces[@]} -eq 0 ]; then
        echo "[INFO] No VPN interfaces detected"
        return
    fi
    
    echo "[INFO] Detected VPN interfaces: ${vpn_ifaces[*]}"
    
    if [ ${#vpn_subnets[@]} -eq 0 ]; then
        echo "[WARNING] No VPN subnets configured in $VPN_SUBNETS_FILE"
        echo "[INFO] VPN routing will use automatic route detection only"
    else
        echo "[INFO] Configured VPN subnets: ${vpn_subnets[*]}"
    fi
    
    for vpn_iface in "${vpn_ifaces[@]}"; do
        echo "[INFO] Configuring routes for VPN interface: $vpn_iface"
        sudo iptables -A FORWARD -i "$LAN_IFACE" -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
        sudo iptables -A FORWARD -i "$vpn_iface" -o "$LAN_IFACE" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        sudo iptables -A INPUT -i "$vpn_iface" -j ACCEPT 2>/dev/null || true
        sudo iptables -A OUTPUT -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
        sudo iptables -t nat -A POSTROUTING -o "$vpn_iface" -j MASQUERADE 2>/dev/null || true
        
        for subnet in "${vpn_subnets[@]}"; do
            if ! ip route show "$subnet" | grep -q "$vpn_iface"; then
                echo "[INFO] Adding route: $subnet via $vpn_iface"
                sudo ip route add "$subnet" dev "$vpn_iface" 2>/dev/null || echo "[WARNING] Route may already exist"
            fi
            sudo iptables -A FORWARD -s "$subnet" -i "$vpn_iface" -o "$LAN_IFACE" -j ACCEPT 2>/dev/null || true
            sudo iptables -A FORWARD -d "$subnet" -i "$LAN_IFACE" -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
        done
    done
    
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
    echo "[INFO] VPN routing configured"
}

# === Clean up old VPN rules ===
cleanup_vpn_rules() {
    local old_vpn_ifaces="$1"
    if [ -z "$old_vpn_ifaces" ]; then
        return
    fi
    echo "[INFO] Cleaning up old VPN routes..."
    for vpn_iface in $old_vpn_ifaces; do
        if ! ip link show "$vpn_iface" &> /dev/null; then
            echo "[INFO] Removing rules for defunct VPN interface: $vpn_iface"
            sudo iptables -D FORWARD -i "$LAN_IFACE" -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
            sudo iptables -D FORWARD -i "$vpn_iface" -o "$LAN_IFACE" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
            sudo iptables -D INPUT -i "$vpn_iface" -j ACCEPT 2>/dev/null || true
            sudo iptables -D OUTPUT -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
            sudo iptables -t nat -D POSTROUTING -o "$vpn_iface" -j MASQUERADE 2>/dev/null || true
        fi
    done
}

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

if [ "$ENABLE_VPN_ROUTING" = true ]; then
    configure_vpn_routing
fi

sudo mkdir -p /etc/iptables
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
echo "[INFO] Iptables configured and saved"

# === Configure router's own DNS resolution ===
configure_router_dns() {
    echo "[INFO] Configuring router's own DNS resolution..."
    
    # Get WAN DNS servers
    WAN_DNS_SERVERS=""
    if command -v nmcli &> /dev/null; then
        WAN_DNS_SERVERS=$(nmcli dev show "$CURRENT_WAN" 2>/dev/null | awk '/IP4.DNS/ {print $2}')
    fi
    if [ -z "$WAN_DNS_SERVERS" ] && command -v resolvectl &> /dev/null; then
        WAN_DNS_SERVERS=$(resolvectl dns "$CURRENT_WAN" 2>/dev/null | awk '{for(i=2;i<=NF;i++) print $i}')
    fi
    
    # Collect DNS servers in array
    declare -a DNS_ARRAY
    if [ -n "$WAN_DNS_SERVERS" ]; then
        for dns in $WAN_DNS_SERVERS; do
            if [[ "$dns" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
                DNS_ARRAY+=("$dns")
            fi
        done
    fi
    
    # Add fallback DNS if no WAN DNS found
    if [ ${#DNS_ARRAY[@]} -eq 0 ]; then
        DNS_ARRAY+=("$FALLBACK_DNS1")
        DNS_ARRAY+=("$FALLBACK_DNS2")
        echo "[WARNING] No WAN DNS servers found, using fallback DNS"
    else
        # Add fallback as backup
        DNS_ARRAY+=("$FALLBACK_DNS1")
        DNS_ARRAY+=("$FALLBACK_DNS2")
    fi
    
    # Configure the router's own /etc/resolv.conf
    # Make sure it's not immutable
    sudo chattr -i /etc/resolv.conf 2>/dev/null || true
    
    # Write directly to /etc/resolv.conf for the router itself
    {
        echo "# Router's own DNS resolution (managed by dynamic-router.sh)"
        echo "# LAN clients will use dnsmasq at $LAN_IP"
        echo ""
        for dns in "${DNS_ARRAY[@]}"; do
            echo "nameserver $dns"
        done
    } | sudo tee /etc/resolv.conf > /dev/null
    
    echo "[INFO] Router DNS configured: ${DNS_ARRAY[*]}"
}

# === Update dnsmasq based on WAN DNS ===
update_dnsmasq_upstream() {
    WAN_DNS_SERVERS=""
    if command -v nmcli &> /dev/null; then
        WAN_DNS_SERVERS=$(nmcli dev show "$CURRENT_WAN" 2>/dev/null | awk '/IP4.DNS/ {print $2}')
    fi
    if [ -z "$WAN_DNS_SERVERS" ] && command -v resolvectl &> /dev/null; then
        WAN_DNS_SERVERS=$(resolvectl dns "$CURRENT_WAN" 2>/dev/null | awk '{for(i=2;i<=NF;i++) print $i}')
    fi
    
    declare -a SERVER_LINES
    if [ -n "$WAN_DNS_SERVERS" ]; then
        for dns in $WAN_DNS_SERVERS; do
            if [[ "$dns" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
                SERVER_LINES+=("server=$dns")
            fi
        done
    fi
    SERVER_LINES+=("server=$FALLBACK_DNS1")
    SERVER_LINES+=("server=$FALLBACK_DNS2")
    if [ ${#SERVER_LINES[@]} -eq 2 ]; then
        echo "[WARNING] No WAN DNS servers found, using fallback only"
    fi
    {
        echo "interface=$LAN_IFACE"
        echo "listen-address=$LAN_IP"
        echo "bind-interfaces"
        echo ""
        echo "# Upstream DNS servers"
        for line in "${SERVER_LINES[@]}"; do
            echo "$line"
        done
        echo ""
        echo "no-resolv"
        echo "domain-needed"
        echo "bogus-priv"
        echo "cache-size=1000"
        echo ""
        echo "# DHCP settings"
        echo "dhcp-range=${LAN_IP%.*}.100,${LAN_IP%.*}.250,12h"
        echo "dhcp-option=option:router,$LAN_IP"
        echo "dhcp-option=option:dns-server,$LAN_IP"
        echo "dhcp-authoritative"
        echo ""
        echo "log-dhcp"
    } | sudo tee /etc/dnsmasq.d/lan.conf > /dev/null
    sudo systemctl restart dnsmasq || sudo journalctl -u dnsmasq -n 20 --no-pager
    echo "[INFO] dnsmasq configured:"
    echo "[INFO]   - LAN clients will use $LAN_IP as DNS server (gateway)"
    echo "[INFO]   - LAN clients will use $LAN_IP as default gateway"
    echo "[INFO]   - Upstream DNS: ${WAN_DNS_SERVERS:-$FALLBACK_DNS1 $FALLBACK_DNS2}"
    
    # Also configure the router's own DNS
    configure_router_dns
}

# === WAN and VPN monitoring ===
CURRENT_WAN=$WAN_IFACE
CURRENT_VPN_IFACES=""
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

echo "[INFO] Starting WAN and VPN interface monitor..."
while true; do
    sleep 10
    ensure_lan_ip

    NEW_WAN=$(ip route | awk '/^default/ {print $5; exit}')
    if [ "$NEW_WAN" != "$CURRENT_WAN" ] && [ -n "$NEW_WAN" ]; then
        echo "[INFO] WAN interface changed: $CURRENT_WAN -> $NEW_WAN"
        CURRENT_WAN="$NEW_WAN"
        update_dnsmasq_upstream  # This also updates router's own DNS
        sudo iptables -t nat -D POSTROUTING -o "$CURRENT_WAN" -j MASQUERADE 2>/dev/null || true
        sudo iptables -t nat -A POSTROUTING -o "$CURRENT_WAN" -j MASQUERADE
    fi

    if [ "$ENABLE_VPN_ROUTING" = true ]; then
        VPN_IFACES=$(detect_vpn_interfaces)
        if [ "$VPN_IFACES" != "$CURRENT_VPN_IFACES" ]; then
            echo "[INFO] VPN interfaces changed: $CURRENT_VPN_IFACES -> $VPN_IFACES"
            cleanup_vpn_rules "$CURRENT_VPN_IFACES"
            CURRENT_VPN_IFACES="$VPN_IFACES"
            configure_vpn_routing
        fi
    fi
done
