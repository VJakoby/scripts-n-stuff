!/bin/bash
# clean-router-reset.sh — Fully reset network, DNS, and firewall for clean router setup

set -e

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

echo "[INFO] Cleanup complete. System is ready for fresh router script."
