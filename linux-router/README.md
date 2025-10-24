# Dynamic VM Router

This setup provides a lightweight Linux VM acting as a dynamic router for other VMs.  
It handles NAT, IP forwarding, LAN DNS via `dnsmasq`, and dynamic WAN detection.

## Requirements:
`dnsmasq iptables iptables-persistent`

## Network Intefaces


### LAN (static)
- Interface: e.g, `ens34` (in this setup it's connected to VMwares `VMnet2`
- IP: `192.168.100.1/24`
- VMs use this IP as **gateway** and **DNS**

### WAN (dynamic)
- Interface detected automatically (Ethernet, Wi-Fi, or NAT) - no need to define it manually.
- Can be NAT, bridged, or any other connection providing Internet access.
- The script updates routing and NAT automatically if it changes.

## How this works
1. WAN detection is dynamic — any interface that has the default route becomes WAN.
2. LAN interface is static — your VMs always use 192.168.100.1 as gateway and DNS.
3. Router VM itself can access the internet (apt, updates, DNS).
4. Forwarding and NAT allow LAN → WAN traffic automatically.
5. dnsmasq binds to LAN interface only, providing DNS for the VMs.

## Step by step

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

## Notes

- Router VM itself keeps internet access for updates/packages.
- WAN interface can change; script updates NAT/forwarding automatically.
- dnsmasq binds only to LAN, no DHCP in this setup.
- If the LAN interface isn’t up at boot, dnsmasq may fail — optional: add a check in the script.

### TODO
- Ensure if VPN connection is up, this should give WAN access
