# Dynamic VM Router
Lightweight Linux VM router for private VM networks. Handles NAT, IP forwarding, LAN DNS via dnsmasq, and automatic WAN detection—allowing VMs internet access with minimal setup.
Original idea by Jakob, core coding by Claude + ChatGPT.

## Features
- Single-command installation, zero manual config
- Automatic startup on boot
- Dynamic WAN detection and failover
- VPN-aware routing
- DNS conflict resolution (systemd-resolved + dnsmasq)
- Router VM maintains its own connectivity
- Persistent configuration across reboots

## Recommended Linux Distributions

- Ubuntu LTS / Xubuntu (best)
- Other Debian-based distros (e.g., Debian, Linux Mint)
Network setup is tailored for Ubuntu/Debian systems.

## Quick Start
- Test Without Installing Service
`sudo ./dynamic-router.sh --run <LAN_IFACE> <LAN_IP/CIDR>`

- Install Service
`sudo ./dynamic-router.sh --install-service <LAN_IFACE> <LAN_IP/CIDR>`

### Example:
```bash
sudo ./dynamic-router.sh --install-service ens34 192.168.100.1/24`
<LAN_IFACE> — LAN network interface (e.g., ens34, enp0s8)
<LAN_IP/CIDR> — static IP for LAN (e.g., 192.168.100.1/24)

Hardcoded DNS:
Primary: 1.1.1.1 (Cloudflare)
Secondary: 8.8.8.8 (Google)
```

## Network Interfaces
### LAN (static)

- IP automatically configured by the script
- LAN clients use this IP as gateway and DNS
#### WAN (dynamic)
- Detected automatically (interface with default route)
- Supports NAT or bridged upstream connections
- Updates routing/NAT automatically on WAN changes (VPN, reconnects, etc.)
### Management Commands
#### Check status:
`sudo systemctl status dynamic-router.service`

#### View live logs:
`sudo journalctl -u dynamic-router.service -f`

#### Restart service:
`sudo systemctl restart dynamic-router.service`

#### Stop service:
`sudo systemctl stop dynamic-router.service`

#### Disable auto-start on boot:
`sudo systemctl disable dynamic-router.service`

### Uninstallation
`sudo systemctl stop dynamic-router.service && sudo systemctl disable dynamic-router.service && sudo rm /etc/systemd/system/dynamic-router.service /usr/local/bin/dynamic-router.sh && sudo systemctl daemon-reload`

#### Optionally restore DNS:
- `sudo chattr -i /etc/resolv.conf && sudo rm /etc/systemd/resolved.conf.d/no-stub.conf && sudo systemctl restart systemd-resolved`
