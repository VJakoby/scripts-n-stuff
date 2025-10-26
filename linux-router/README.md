# Dynamic VM Router
This setup provides a lightweight Linux VM acting as a dynamic router for other VMs.  
It handles NAT, IP forwarding, LAN DNS via `dnsmasq`, and dynamic WAN detection.

## Requirements:
`dnsmasq iptables iptables-persistent`

## Network Interfaces
### LAN (static)
- Interface: e.g, `ens34` (in this setup it's connected to VMwares `VMnet2`
- IP: `192.168.100.1/24`
- **This IP must be configured manually** on the LAN interface (for example, via netplan or nmcli).
- VMs use this IP as **gateway** and **DNS**
#### Setting IP
1. Change the `01-netcfg.yaml` if IP or interface is not correct.
2. `sudo netplan apply`
### WAN (dynamic)
- Detected automatically — any interface with the default route becomes WAN..
- Can be NAT, bridged, or any other connection providing Internet access.
- The script automatically updates routing and NAT if the WAN changes.

## How this works
1. WAN detection is dynamic — any interface that has the default route becomes WAN.
2. LAN interface is static — your VMs always use 192.168.100.1 as gateway and DNS.
3. Router VM itself can access the internet (apt, updates, DNS).
4. Forwarding and NAT allow LAN → WAN traffic automatically.
5. `dnsmasq` binds to LAN interface only, providing DNS for the VMs. (No DHCP). Clients must be manually set also within the same subnet.

## Setup
```
sudo apt update
sudo apt install iptables iptables-persistent dnsmasq -y
sudo mv dynamic-router.sh /usr/local/bin/dynamic-router.sh
sudo chmod +x /usr/local/bin/dynamic-router.sh
sudo mv dynamic-router.service /etc/systemd/system/dynamic-router.service
sudo systemctl daemon-reload
sudo systemctl enable dynamic-router.service
sudo systemctl start dynamic-router.service
```
- Inspect the logs too see if it works `journalctl -u dynamic-router.service -f`

## Notes
- The LAN IP (192.168.100.1/24) must be manually assigned before starting the service.
- The router VM itself maintains internet connectivity.
- dnsmasq runs only on the LAN interface and provides DNS (no DHCP).
- If the LAN interface isn’t active at boot, dnsmasq may fail — consider adding a readiness check in the script.
- WAN interface detection adapts automatically, including after VPN changes.
- 
### Future TODO
- [] Ensure that Internet access works when router has a active VPN connection enabled.
