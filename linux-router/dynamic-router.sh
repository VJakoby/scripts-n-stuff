#!/bin/bash
# dynamic-router.sh — Automatic Dynamic WAN + static LAN router for VMs with VPN support
# Usage: ./dynamic-router.sh --install-service <LAN_IFACE> <LAN_IP/CIDR> [--vpn] [--vpn-subnets <file>]
#        ./dynamic-router.sh --run <LAN_IFACE> <LAN_IP/CIDR> [--vpn] [--vpn-subnets <file>]

set -e

# Hardcoded fallback DNS servers
FALLBACK_DNS1="1.1.1.1"
FALLBACK_DNS2="8.8.8.8"

# Default VPN subnets file location
VPN_SUBNETS_FILE="/etc/router/vpn-subnets.txt"

# VPN routing disabled by default
ENABLE_VPN_ROUTING=false

# === Parse arguments ===
if [ $# -lt 3 ]; then
    echo "Usage:"
    echo "  $0 --install-service <LAN_IFACE> <LAN_IP/CIDR> [OPTIONS]"
    echo "  $0 --run <LAN_IFACE> <LAN_IP/CIDR> [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --vpn                 Enable VPN routing (monitors and routes VPN interfaces)"
    echo "  --vpn-subnets <file>  Path to file containing VPN subnets (one per line)"
    echo "                        Default: /etc/router/vpn-subnets.txt"
    echo ""
    echo "Examples:"
    echo "  # Install without VPN routing (e.g., for Tailscale you don't want routed)"
    echo "  $0 --install-service eth1 10.0.0.1/24"
    echo ""
    echo "  # Install with VPN routing enabled"
    echo "  $0 --install-service eth1 10.0.0.1/24 --vpn"
    echo ""
    echo "  # Run directly with VPN routing and custom subnets file"
    echo "  $0 --run eth1 10.0.0.1/24 --vpn --vpn-subnets /etc/openvpn/subnets.txt"
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
        --vpn-subnets)
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
    
    # Copy script to /usr/local/bin
    SCRIPT_PATH="$(readlink -f "$0")"
    sudo cp "$SCRIPT_PATH" /usr/local/bin/dynamic-router.sh
    sudo chmod +x /usr/local/bin/dynamic-router.sh
    
    # Create config directory
    sudo mkdir -p /etc/router
    
    # Create empty VPN subnets file if it doesn't exist
    if [ ! -f "$VPN_SUBNETS_FILE" ]; then
        sudo tee "$VPN_SUBNETS_FILE" > /dev/null <<EOF
# VPN Subnets Configuration
# Add one subnet per line (CIDR notation)
# These subnets will be routed through detected VPN interfaces
# Example:
# 10.8.0.0/24
# 192.168.100.0/24
EOF
        echo "[INFO] Created empty VPN subnets file at $VPN_SUBNETS_FILE"
    fi
    
    # Build ExecStart command with VPN flag if enabled
    EXEC_START_CMD="/usr/local/bin/dynamic-router.sh --run $LAN_IFACE $LAN_IP_CIDR"
    if [ "$ENABLE_VPN_ROUTING" = true ]; then
        EXEC_START_CMD="$EXEC_START_CMD --vpn"
        # Only add custom subnets path if it's not the default
        if [ "$VPN_SUBNETS_FILE" != "/etc/router/vpn-subnets.txt" ]; then
            EXEC_START_CMD="$EXEC_START_CMD --subnets $VPN_SUBNETS_FILE"
        fi
    fi
    
    # Create systemd service
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
    
    # Enable and start
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

# === Function to detect VPN interfaces ===
detect_vpn_interfaces() {
    # Common VPN interface patterns
    ip link show | grep -E '^[0-9]+: (tun|tap|ppp|wg|ipsec)[0-9]*:' | awk -F': ' '{print $2}' | awk '{print $1}'
}

# === Function to read VPN subnets from file ===
read_vpn_subnets() {
    local subnets=()
    if [ -f "$VPN_SUBNETS_FILE" ]; then
        echo "[INFO] Reading VPN subnets from: $VPN_SUBNETS_FILE"
        while IFS= read -r line; do
            # Skip empty lines and comments
            line=$(echo "$line" | sed 's/#.*//' | xargs)
            if [ -n "$line" ]; then
                # Validate CIDR format
                if echo "$line" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$'

# === Function to configure VPN routes and iptables ===
configure_vpn_routing() {
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
    
    # Configure routing for each VPN interface
    for vpn_iface in "${vpn_ifaces[@]}"; do
        echo "[INFO] Configuring routes for VPN interface: $vpn_iface"
        
        # Allow forwarding between LAN and VPN interface
        sudo iptables -A FORWARD -i "$LAN_IFACE" -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
        sudo iptables -A FORWARD -i "$vpn_iface" -o "$LAN_IFACE" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        
        # Allow VPN traffic through this router
        sudo iptables -A INPUT -i "$vpn_iface" -j ACCEPT 2>/dev/null || true
        sudo iptables -A OUTPUT -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
        
        # Enable NAT for VPN interface (needed for some VPN configurations)
        sudo iptables -t nat -A POSTROUTING -o "$vpn_iface" -j MASQUERADE 2>/dev/null || true
        
        # Configure routes for explicitly defined subnets
        for subnet in "${vpn_subnets[@]}"; do
            # Add route via VPN interface if not already present
            if ! ip route show "$subnet" | grep -q "$vpn_iface"; then
                echo "[INFO] Adding route: $subnet via $vpn_iface"
                sudo ip route add "$subnet" dev "$vpn_iface" 2>/dev/null || echo "[WARNING] Route may already exist"
            fi
            
            # Allow specific subnet traffic
            sudo iptables -A FORWARD -s "$subnet" -i "$vpn_iface" -o "$LAN_IFACE" -j ACCEPT 2>/dev/null || true
            sudo iptables -A FORWARD -d "$subnet" -i "$LAN_IFACE" -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
        done
    done
    
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
    echo "[INFO] VPN routing configured"
}

# === Function to clean up old VPN rules ===
cleanup_vpn_rules() {
    local old_vpn_ifaces="$1"
    
    if [ -z "$old_vpn_ifaces" ]; then
        return
    fi
    
    echo "[INFO] Cleaning up old VPN routes..."
    
    for vpn_iface in $old_vpn_ifaces; do
        # Check if interface still exists
        if ! ip link show "$vpn_iface" &> /dev/null; then
            echo "[INFO] Removing rules for defunct VPN interface: $vpn_iface"
            
            # Remove forwarding rules
            sudo iptables -D FORWARD -i "$LAN_IFACE" -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
            sudo iptables -D FORWARD -i "$vpn_iface" -o "$LAN_IFACE" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
            
            # Remove INPUT/OUTPUT rules
            sudo iptables -D INPUT -i "$vpn_iface" -j ACCEPT 2>/dev/null || true
            sudo iptables -D OUTPUT -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
            
            # Remove NAT rules
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

# Configure VPN routing on startup if enabled
if [ "$ENABLE_VPN_ROUTING" = true ]; then
    configure_vpn_routing
else
    echo "[INFO] VPN routing disabled - skipping VPN configuration"
fi

sudo mkdir -p /etc/iptables
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
echo "[INFO] Iptables configured and saved"

# === Function to update dnsmasq upstream based on WAN DNS ===
update_dnsmasq_upstream() {
    WAN_DNS_SERVERS=$(nmcli dev show "$CURRENT_WAN" 2>/dev/null | awk '/IP4.DNS/ {print $2}')
    DNSMASQ_SERVERS=""
    for dns in $WAN_DNS_SERVERS; do
        DNSMASQ_SERVERS+=$'server='"$dns"$'\n'
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
if [ "$ENABLE_VPN_ROUTING" = true ]; then
    echo "[INFO] Monitor checks every 10 seconds for WAN and VPN changes"
else
    echo "[INFO] Monitor checks every 10 seconds for WAN changes only"
fi
while true; do
    sleep 10

    ensure_lan_ip

    # Check for WAN changes
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
    
    # Check for VPN interface changes only if VPN routing is enabled
    if [ "$ENABLE_VPN_ROUTING" = true ]; then
        NEW_VPN_IFACES=$(detect_vpn_interfaces | tr '\n' ' ')
        
        if [ "$NEW_VPN_IFACES" != "$CURRENT_VPN_IFACES" ]; then
            echo "[INFO] VPN interface change detected"
            echo "[INFO] Previous: $CURRENT_VPN_IFACES"
            echo "[INFO] Current: $NEW_VPN_IFACES"
            
            # Clean up old VPN rules
            cleanup_vpn_rules "$CURRENT_VPN_IFACES"
            
            # Reconfigure VPN routing
            configure_vpn_routing
            
            CURRENT_VPN_IFACES="$NEW_VPN_IFACES"
        fi
    fi
done; then
                    subnets+=("$line")
                else
                    echo "[WARNING] Invalid CIDR format, skipping: $line"
                fi
            fi
        done < "$VPN_SUBNETS_FILE"
        
        if [ ${#subnets[@]} -eq 0 ]; then
            echo "[WARNING] No valid subnets found in $VPN_SUBNETS_FILE"
        fi
    else
        echo "[WARNING] VPN subnets file not found: $VPN_SUBNETS_FILE"
        echo "[INFO] VPN routing will work but without explicit subnet routes"
    fi
    echo "${subnets[@]}"
}

# === Function to configure VPN routes and iptables ===
configure_vpn_routing() {
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
    
    # Configure routing for each VPN interface
    for vpn_iface in "${vpn_ifaces[@]}"; do
        echo "[INFO] Configuring routes for VPN interface: $vpn_iface"
        
        # Allow forwarding between LAN and VPN interface
        sudo iptables -A FORWARD -i "$LAN_IFACE" -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
        sudo iptables -A FORWARD -i "$vpn_iface" -o "$LAN_IFACE" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        
        # Allow VPN traffic through this router
        sudo iptables -A INPUT -i "$vpn_iface" -j ACCEPT 2>/dev/null || true
        sudo iptables -A OUTPUT -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
        
        # Enable NAT for VPN interface (needed for some VPN configurations)
        sudo iptables -t nat -A POSTROUTING -o "$vpn_iface" -j MASQUERADE 2>/dev/null || true
        
        # Configure routes for explicitly defined subnets
        for subnet in "${vpn_subnets[@]}"; do
            # Add route via VPN interface if not already present
            if ! ip route show "$subnet" | grep -q "$vpn_iface"; then
                echo "[INFO] Adding route: $subnet via $vpn_iface"
                sudo ip route add "$subnet" dev "$vpn_iface" 2>/dev/null || echo "[WARNING] Route may already exist"
            fi
            
            # Allow specific subnet traffic
            sudo iptables -A FORWARD -s "$subnet" -i "$vpn_iface" -o "$LAN_IFACE" -j ACCEPT 2>/dev/null || true
            sudo iptables -A FORWARD -d "$subnet" -i "$LAN_IFACE" -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
        done
    done
    
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
    echo "[INFO] VPN routing configured"
}

# === Function to clean up old VPN rules ===
cleanup_vpn_rules() {
    local old_vpn_ifaces="$1"
    
    if [ -z "$old_vpn_ifaces" ]; then
        return
    fi
    
    echo "[INFO] Cleaning up old VPN routes..."
    
    for vpn_iface in $old_vpn_ifaces; do
        # Check if interface still exists
        if ! ip link show "$vpn_iface" &> /dev/null; then
            echo "[INFO] Removing rules for defunct VPN interface: $vpn_iface"
            
            # Remove forwarding rules
            sudo iptables -D FORWARD -i "$LAN_IFACE" -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
            sudo iptables -D FORWARD -i "$vpn_iface" -o "$LAN_IFACE" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
            
            # Remove INPUT/OUTPUT rules
            sudo iptables -D INPUT -i "$vpn_iface" -j ACCEPT 2>/dev/null || true
            sudo iptables -D OUTPUT -o "$vpn_iface" -j ACCEPT 2>/dev/null || true
            
            # Remove NAT rules
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

# Configure VPN routing on startup if enabled
if [ "$ENABLE_VPN_ROUTING" = true ]; then
    configure_vpn_routing
else
    echo "[INFO] VPN routing disabled - skipping VPN configuration"
fi

sudo mkdir -p /etc/iptables
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
echo "[INFO] Iptables configured and saved"

# === Function to update dnsmasq upstream based on WAN DNS ===
update_dnsmasq_upstream() {
    WAN_DNS_SERVERS=$(nmcli dev show "$CURRENT_WAN" 2>/dev/null | awk '/IP4.DNS/ {print $2}')
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
if [ "$ENABLE_VPN_ROUTING" = true ]; then
    echo "[INFO] Monitor checks every 10 seconds for WAN and VPN changes"
else
    echo "[INFO] Monitor checks every 10 seconds for WAN changes only"
fi
while true; do
    sleep 10

    ensure_lan_ip

    # Check for WAN changes
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
    
    # Check for VPN interface changes only if VPN routing is enabled
    if [ "$ENABLE_VPN_ROUTING" = true ]; then
        NEW_VPN_IFACES=$(detect_vpn_interfaces | tr '\n' ' ')
        
        if [ "$NEW_VPN_IFACES" != "$CURRENT_VPN_IFACES" ]; then
            echo "[INFO] VPN interface change detected"
            echo "[INFO] Previous: $CURRENT_VPN_IFACES"
            echo "[INFO] Current: $NEW_VPN_IFACES"
            
            # Clean up old VPN rules
            cleanup_vpn_rules "$CURRENT_VPN_IFACES"
            
            # Reconfigure VPN routing
            configure_vpn_routing
            
            CURRENT_VPN_IFACES="$NEW_VPN_IFACES"
        fi
    fi
done
