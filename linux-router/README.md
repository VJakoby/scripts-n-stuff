# Dynamic VM Router
A lightweight Linux VM setup that functions as a dynamic router for other VMs.
It handles NAT, IP forwarding, LAN DNS via dnsmasq, and automatic WAN detection, making it easy to spin up a private VM network with internet access.

## Features

- ✅ **Single command installation** — no manual configuration needed
- ✅ **Automatic startup on boot** — set it and forget it
- ✅ **Dynamic WAN detection** — adapts to VPN changes automatically
- ✅ **DNS conflict resolution** — systemd-resolved and dnsmasq work together seamlessly
- ✅ **Router internet access** — the router VM maintains its own connectivity
- ✅ **Automatic WAN failover** — adapts if your internet connection changes
- ✅ **Persistent configuration** — survives reboots

## Recommended Linux Distribution
- **Best suited:** Ubuntu LTS (Desktop or Server) or Xubuntu.
  - Network configuration is tailored for Ubuntu based systems.
- **Other compatible options**: Debian-based distributions (like Debian, Linux Mint)

## Quick Start

### Manual Testing (Without Installing Service)
If you want to test the router without installing the systemd service:
```bash
sudo ./dynamic-router.sh --run <LAN_IFACE> <LAN_IP/CIDR>
```
### One-Time Installation
Run the installation command once to set up the router service:
```bash
sudo ./dynamic-router.sh --install-service <LAN_IFACE> <LAN_IP/CIDR>
```
**Example:**
```bash
sudo ./dynamic-router.sh --install-service ens34 192.168.100.1/24
```
That's it! The router will start immediately and automatically on every boot.
### Parameters
- `<LAN_IFACE>` — the network interface for the LAN (e.g., ens34, enp0s8, or any VM network adapter connected to your private VM network)
- `<LAN_IP/CIDR>` — static IP for your LAN interface (e.g., 192.168.100.1/24)

**DNS servers are hardcoded:**
- Primary: 1.1.1.1 (Cloudflare)
- Secondary: 8.8.8.8 (Google)
---
## Network Interfaces

### LAN (static)
- Interface: e.g., `ens34` (any interface connected to your VM network)
- IP: e.g., `192.168.100.1/24`
- LAN IP is **automatically configured** by the script — no manual netplan configuration needed
- LAN clients use this IP as **gateway** and **DNS**
- 
### WAN (dynamic)
- Detected automatically — any interface with a default route becomes WAN
- Supports NAT, bridged, or any upstream connection providing Internet access
- Script automatically updates routing and NAT if the WAN changes (e.g., VPN connects/disconnects)
- 
## Management Commands

### Check Service Status
```bash
sudo systemctl status dynamic-router.service
```
### View Live Logs
```bash
sudo journalctl -u dynamic-router.service -f
```
### Restart Service
```bash
sudo systemctl restart dynamic-router.service
```
### Stop Service
```bash
sudo systemctl stop dynamic-router.service
```
### Disable Auto-Start on Boot
```bash
sudo systemctl disable dynamic-router.service
```

## Uninstallation

To completely remove the router service:

```bash
sudo systemctl stop dynamic-router.service
sudo systemctl disable dynamic-router.service
sudo rm /etc/systemd/system/dynamic-router.service
sudo rm /usr/local/bin/dynamic-router.sh
sudo systemctl daemon-reload
```

Optionally, restore DNS settings:
```bash
sudo chattr -i /etc/resolv.conf
sudo rm /etc/systemd/resolved.conf.d/no-stub.conf
sudo systemctl restart systemd-resolved
```
