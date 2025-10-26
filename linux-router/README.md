# Dynamic VM Router
A lightweight Linux VM setup that functions as a dynamic router for other VMs.
It handles NAT, IP forwarding, LAN DNS via dnsmasq, and automatic WAN detection, making it easy to spin up a private VM network with internet access.
## Recommended Linux Distribution

* **Best suited:** Ubuntu LTS (Desktop or Server) or Xubuntu
  * Network configuration is tailored for Ubuntu-based systems.
* **Other compatible options:** Debian-based distributions (like Debian, Linux Mint)

  * Minor adjustments may be required for network configuration or service management.

## Usage

```bash
# 1) Test the router manually
sudo ./dynamic-router.sh <LAN_IFACE> <LAN_IP/CIDR> <PRIMARY_DNS> <SECONDARY_DNS>

# 2) Install as systemd service using the same script
sudo ./dynamic-router.sh --install-service <LAN_IFACE> <LAN_IP/CIDR> <PRIMARY_DNS> <SECONDARY_DNS>
```

* `<LAN_IFACE>` — the network interface for the LAN (e.g., ens34, enp0s8, or any VM network adapter connected to your private VM network)
* `<LAN_IP/CIDR>` — static IP for your LAN interface (e.g., 192.168.100.1/24)
* `<PRIMARY_DNS>` — upstream DNS server for LAN clients (e.g., 8.8.8.8)
* `<SECONDARY_DNS>` — secondary upstream DNS server (e.g., 1.1.1.1)

## Network Interfaces

### LAN (static)

* Interface: e.g., `ens34` (any interface connected to your VM network)
* IP: e.g., `192.168.100.1/24`
* LAN IP is **static** and must be assigned before starting the router.
* LAN clients use this IP as **gateway** and **DNS**.

#### Setting IP

Update your netplan or network configuration with the chosen IP and apply it:

```bash
sudo netplan apply
```

### WAN (dynamic)

* Detected automatically — any interface with a default route becomes WAN.
* Supports NAT, bridged, or any upstream connection providing internet access.
* Script automatically updates routing and NAT if the WAN changes.

## How it works

1. **WAN detection** is dynamic — the router always identifies which interface has internet access.
2. **LAN is static** — VMs use the router’s LAN IP as gateway and DNS.
3. The **router VM itself can access the internet**, including for updates and DNS.
4. **Forwarding and NAT** allow LAN → WAN traffic automatically.
5. **dnsmasq** binds only to the LAN interface, providing DNS for VMs (no DHCP — clients must be configured manually).
6. Logs can be inspected to verify functionality:

```bash
journalctl -u dynamic-router.service -f
```

## Notes

* LAN IP must be assigned **before** starting the script.
* The router maintains its own internet connectivity independently of the LAN.
* `dnsmasq` runs only on the LAN interface and provides DNS (no DHCP).
* If the LAN interface isn’t active at boot, dnsmasq may fail — consider adding readiness checks in the script.
* WAN interface detection adapts automatically, including after VPN changes.

## Future TODO

* [] Ensure internet access works when the router VM has an active VPN connection.
* [] Optional: Add DHCP support for LAN clients.
* [] Optional: Add logging or monitoring of WAN interface changes.lored for Ubuntu based.
- **Other compatible options**: Debian-based distributions (like Debian,, Linux Mint)
## Usage
```bash
# 1) Test the  script 
./dynamic-router.sh <LAN_IFACE> <LAN_IP/CIDR> <PRIMARY_DNS> <SECONDARY_DNS>
# 2) Edit file install-dynamic-router-service.sh
<LAN_IFACE> <LAN_IP/CIDR> <PRIMARY_DNS> <SECONDARY_DNS>
# 3. Run the script
./install-dynamic-router-service.sh
```
- `<LAN_IFACE>` — the network interface for the LAN (e.g., ens34, enp0s8, or any VM network adapter connected to your private VM network)
- `<LAN_IP/CIDR>` — static IP for your LAN interface (e.g., 192.168.100.1/24)
- `<PRIMARY_DNS>` — upstream DNS server for LAN clients (e.g., 8.8.8.8)
- `<SECONDARY_DNS>` — secondary upstream DNS server (e.g., 1.1.1.1)
## Network Interfaces
### LAN (static)
- Interface: e.g, `ens34` (amy interface connected to your VM network)
- IP: e.g., `192.168.100.1/24`
- LAN ip is **static** and must be assigned before starting the router.
- LAN clients use this IPas **gateway** and **DNS**
#### Setting IP
Update your netplan or network configuration with the chosen IP and apply it:
`sudo netplan apply`

### WAN (dynamic)
- Detected automatically — any interface with a default route becomes WAN.
- Supports NAT, bridged, or any upstream connection providing Internet access.
- Script automatically updates routing and NAT if the WAN changes.

## How it works
1. **WAN detection** is dynamic — the router always identifies which interface has internet access.
2. **LAN is static** — VMs use the router’s LAN IP as gateway and DNS.
3. The **router VM itself can access the internet**, including for updates and DNS.
4. **Forwarding and NAT** allow LAN → WAN traffic automatically.
5. **dnsmasq** binds only to the LAN interface, providing DNS for VMs. (No DHCP — clients must be configured manually.)
- Inspect the logs too see if it works `journalctl -u dynamic-router.service -f`

## Notes
- LAN IP must be assigned **before** starting the script.
- The router maintains its own internet connectivity independently of the LAN.
- `dnsmasq` runs only on the LAN interface and provides DNS (no DHCP).
- If the LAN interface isn’t active at boot, dnsmasq may fail — consider adding readiness checks in the script.

WAN interface detection adapts automatically, including after VPN changes.
## Future TODO
- [] Ensure internet access works when the router VM has an active VPN connection.
- [] Optional: Add DHCP support for LAN clients.
- [] Optional: Add logging or monitoring of WAN interface changes.
