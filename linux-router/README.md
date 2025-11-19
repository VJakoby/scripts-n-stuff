# Dynamic VM Router
Lightweight Linux VM router for private VM networks. Handles NAT, IP forwarding, LAN DNS via dnsmasq, and automatic WAN detection—allowing VMs internet access with minimal setup.
Original idea by Jakob, core coding by Claude + ChatGPT.

## Recommended Linux Distributions

- Ubuntu LTS / Xubuntu (best)
- Other Debian-based distros (e.g., Debian, Linux Mint)
Network setup is tailored for Ubuntu/Debian systems.

## Quick Start
- Test Without Installing Service
`sudo ./dynamic-router.sh --run <LAN_IFACE> <LAN_IP/CIDR>`

- Install Service
`sudo ./dynamic-router.sh --install-service <LAN_IFACE> <LAN_IP/CIDR>`

### Example Usage:
```bash
Usage:
  ./router.sh --install-service <LAN_IFACE> <LAN_IP/CIDR> [OPTIONS]
  ./router.sh --run <LAN_IFACE> <LAN_IP/CIDR> [OPTIONS]
  ./router.sh --reset

Options:
  --vpn                 Enable VPN routing (monitors and routes VPN interfaces)
  --subnets <file>      Path to file containing VPN subnets (one per line)
                        Default: /etc/router/vpn-subnets.txt

  ./router.sh --run ens33 10.0.0.1/24
  ./router.sh --run ens33 10.0.0.1/24 --vpn --subnets /etc/openvpn/subnets.txt
  ./router.sh --install-service eth1 10.0.0.1/24
  ./router.sh --install-service eth1 10.0.0.1/24 --vpn
  ./router.sh --install-service eth1 10.0.0.1/24 --vpn --subnets /path/to/custom/vpn-subnets.txt
  ./router.sh --reset
```
