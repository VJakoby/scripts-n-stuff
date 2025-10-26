#!/bin/bash
# dynamic-router.sh — One-shot setup for Hybrid Dynamic WAN + static LAN router
# Usage:
#   ./dynamic-router.sh <LAN_IFACE> <LAN_IP/CIDR> <PRIMARY_DNS> <SECONDARY_DNS>
#   ./dynamic-router.sh --install-service <LAN_IFACE> <LAN_IP/CIDR> <PRIMARY_DNS> <SECONDARY_DNS>
#   ./dynamic-router.sh --watch <LAN_IFACE> <LAN_IP/CIDR> <PRIMARY_DNS> <SECONDARY_DNS>

set -e

MODE="oneshot"

if [[ "$1" == "--install-service" ]]; then
    MODE="install-service"
    shift
elif [[ "$1" == "--watch" ]]; then
    MODE="watcher"
    shift
fi

if [[ $# -ne 4 ]]; then
    echo "Usage: $0 [--install-service|--watch] <LAN_IFACE> <LAN_IP/CIDR> <PRIMARY_DNS> <SECONDARY_DNS>"
    exit 1
fi

LAN_IFACE="$1"
LAN_IP_CIDR="$2"
PRIMARY_DNS="$3"
SECONDARY_DNS="$4"

# === Ensure required packages ===
REQUIRED_PKGS=(dnsmasq iptables iptables-persistent curl netplan.io)
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        echo "[INFO] Installing missing package: $pkg"
        sudo apt-get update
        sudo apt-get install -y "$pkg"
    fi
done

# === Disable systemd-resolved to free port 53 ===
if systemctl is-active --quiet systemd-resolved; then
    sudo systemctl disable --now systemd-resolved
fi
# Ensure /etc/resolv.conf points to upstream DNS
sudo bash -c "echo -e 'nameserver $PRIMARY_DNS\nnameserver $SECONDARY_DNS' > /etc/resolv.conf"

# === WAN detection function ===
get_wan_iface() {
    ip route | awk '/^default/ {print $5; exit}'
}

# === Main setup function ===
setup_router() {
    WAN_IFACE=$(get_wan_iface)
    if [ -z "$WAN_IFACE" ]; then
        echo "[ERROR] No default route found. Connect WAN first."
        exit 1
    fi
    echo "[INFO] Detected WAN interface: $WAN_IFACE"

    sudo sysctl -w net.ipv4.ip_forward=1

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

    sudo iptables -A OUTPUT -o $WAN_IFACE -j ACCEPT
    sudo iptables -A OUTPUT -o $LAN_IFACE -j ACCEPT

    sudo iptables -A FORWARD -i $LAN_IFACE -o $WAN_IFACE -j ACCEPT
    sudo iptables -A FORWARD -i $WAN_IFACE -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT

    sudo iptables -t nat -A POSTROUTING -o $WAN_IFACE -j MASQUERADE

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

    sudo mkdir -p /etc/iptables
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
    echo "======== Router setup complete. LAN=${LAN_IP_CIDR%/*} via $LAN_IFACE, WAN=$WAN_IFACE ======="
}

# === WAN watcher loop ===
watch_wan() {
    CURRENT_WAN=$(get_wan_iface)
    while true; do
        NEW_WAN=$(get_wan_iface)
        if [ "$NEW_WAN" != "$CURRENT_WAN" ]; then
            echo "[INFO] WAN interface changed: $CURRENT_WAN -> $NEW_WAN"
            sudo iptables -t nat -D POSTROUTING -o $CURRENT_WAN -j MASQUERADE
            sudo iptables -D FORWARD -i $LAN_IFACE -o $CURRENT_WAN -j ACCEPT
            sudo iptables -D FORWARD -i $CURRENT_WAN -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
            sudo iptables -D OUTPUT -o $CURRENT_WAN -j ACCEPT

            sudo iptables -t nat -A POSTROUTING -o $NEW_WAN -j MASQUERADE
            sudo iptables -A FORWARD -i $LAN_IFACE -o $NEW_WAN -j ACCEPT
            sudo iptables -A FORWARD -i $NEW_WAN -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
            sudo iptables -A OUTPUT -o $NEW_WAN -j ACCEPT
            CURRENT_WAN=$NEW_WAN
            echo "[INFO] WAN rules updated for $NEW_WAN"
        fi
        sleep 10
    done
}

# === Main execution ===
case "$MODE" in
    oneshot)
        setup_router
        exit 0
        ;;
    watcher)
        watch_wan
        ;;
    install-service)
        setup_router
        sudo cp "$0" /usr/local/bin/dynamic-router.sh
        sudo chmod +x /usr/local/bin/dynamic-router.sh
        sudo tee /etc/systemd/system/dynamic-router.service > /dev/null <<EOF
[Unit]
Description=Hybrid Dynamic VM Router
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/dynamic-router.sh --watch $LAN_IFACE $LAN_IP_CIDR $PRIMARY_DNS $SECONDARY_DNS
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable dynamic-router.service
        sudo systemctl start dynamic-router.service
        echo "[INFO] Systemd service installed and started."
        ;;
esac
