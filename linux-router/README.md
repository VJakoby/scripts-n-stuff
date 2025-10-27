# Dynamic VM Router
A lightweight Linux VM setup that functions as a dynamic router for other VMs.
It handles NAT, IP forwarding, LAN DNS via dnsmasq, and automatic WAN detection, making it easy to spin up a private VM network with internet access.

## Recommended Linux Distribution
- **Best suited:** Ubuntu LTS (Desktop or Server) or Xubuntu.
  - Network configuration is tailored for Ubuntu based systems.
- **Other compatible options**: Debian-based distributions (like Debian, Linux Mint)

## Quick Start

### To test manually (without installing service):
```bash
sudo ./dynamic-router.sh --run ens34 192.168.100.1/24
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

## Network Interfaces

### LAN (static)
- Interface: e.g., `ens34` (any interface connected to your VM network)
- IP: e.g., `192.168.100.1/24`
- LAN IP is **automatically configured** by the script — no manual netplan configuration needed
- LAN clients use this IP as **gateway** and **DNS**

### WAN (dynamic)
- Detected automatically — any interface with a default route becomes WAN
- Supports NAT, bridged, or any upstream connection providing Internet access
- Script automatically updates routing and NAT if the WAN changes (e.g., VPN connects/disconnects)

## How It Works

1. **WAN detection** is dynamic — the router always identifies which interface has internet access
2. **LAN is static** — VMs use the router's LAN IP as gateway and DNS
3. The **router VM itself can access the internet** independently, including for updates and DNS resolution
4. **Forwarding and NAT** allow LAN → WAN traffic automatically
5. **dnsmasq** binds only to the LAN interface, providing DNS for VMs (no DHCP — clients must be configured manually)
6. **DNS conflicts resolved** — systemd-resolved and dnsmasq are configured to work together without port conflicts

## Configuring LAN VMs

After the router is running, configure your LAN VMs with static IPs:

**Example for a LAN VM:**
- IP Address: `192.168.100.10/24` (any IP in the same subnet)
- Gateway: `192.168.100.1` (the router's LAN IP)
- DNS Server: `192.168.100.1` (the router's LAN IP)

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

### Manual Testing (Without Installing Service)
If you want to test the router without installing the systemd service:
```bash
sudo ./dynamic-router.sh --run <LAN_IFACE> <LAN_IP/CIDR>
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

## Features

- ✅ **Single command installation** — no manual configuration needed
- ✅ **Automatic startup on boot** — set it and forget it
- ✅ **Dynamic WAN detection** — adapts to VPN changes automatically
- ✅ **DNS conflict resolution** — systemd-resolved and dnsmasq work together seamlessly
- ✅ **Router internet access** — the router VM maintains its own connectivity
- ✅ **Automatic WAN failover** — adapts if your internet connection changes
- ✅ **Persistent configuration** — survives reboots

## Troubleshooting

### Check if the service is running
```bash
sudo systemctl status dynamic-router.service
```

### View detailed logs
```bash
sudo journalctl -u dynamic-router.service -n 50
```

### Test router's internet access
From the router VM:
```bash
ping 1.1.1.1
curl -I https://google.com
```

### Test LAN VM connectivity
From a LAN VM:
```bash
ping 192.168.100.1  # Should reach the router
ping 1.1.1.1        # Should reach internet
ping google.com     # Should resolve and reach internet
```

### Common Issues

**Service fails to start:**
- Check that the LAN interface name is correct: `ip link show`
- Verify the interface exists: `ip addr show <LAN_IFACE>`

**LAN VMs can't reach internet:**
- Verify gateway is set to the router's LAN IP
- Verify DNS is set to the router's LAN IP
- Check firewall rules: `sudo iptables -L -v -n`

**Router can't access internet:**
- Check WAN interface has connectivity: `ip route`
- Test DNS resolution: `nslookup google.com 1.1.1.1`

## Notes

- The router maintains its own internet connectivity independently of the LAN
- `dnsmasq` runs only on the LAN interface and provides DNS (no DHCP)
- WAN interface detection adapts automatically, including after VPN changes
- All configuration is persistent and survives reboots
- The installation only needs to be run once

## Future TODO
- [ ] Add DHCP support for LAN clients (optional)
- [ ] Add logging or monitoring of WAN interface changes
- [ ] Add web UI for configuration and monitoring
