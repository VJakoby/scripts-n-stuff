# AzireVPN / qBittorrent namespace

qBittorrent runs in a dedicated network namespace. Only traffic from the namespace uses AzireVPN(or other wireguard VPN); host/Docker traffic uses the normal ISP connection.

This is essentially a more complicated way instead of using Gluetun as a docker container essentially.

```text
Host / Docker
     |
   eno1
     |
Internet

Host
10.200.0.1
     |
 veth-host
     |
 veth-torrent
10.200.0.2
     |
torrent namespace
     |
qBittorrent
     |
azirevpn (WireGuard)
     |
AzireVPN
```

## Fixed configuration

| Item                | Value                          |
| ------------------- | ------------------------------ |
| Namespace           | `torrent`                      |
| Host veth           | `veth-host`                    |
| Namespace veth      | `veth-torrent`                 |
| Namespace IP        | `10.200.0.2/24`                |
| Host IP             | `10.200.0.1/24`                |
| External interface  | `eno1`                         |
| WireGuard interface | `azirevpn`                     |
| WG config           | `/etc/wireguard/azirevpn.conf` |
| VPN IP              | `X.X.X.X`                      |
| WebUI               | `10.200.0.2:8080`              |

## Important files

```text
/usr/local/sbin/torrent-netns.sh
/usr/local/sbin/torrent-vpn.sh
/usr/local/sbin/qbittorrent-vpn.sh

/etc/wireguard/azirevpn.conf
/etc/nftables.d/torrent-killswitch.nft
/etc/netns/torrent/resolv.conf

/etc/systemd/system/torrent-netns.service
/etc/systemd/system/torrent-vpn.service

/etc/sudoers.d/qbittorrent-vpn

~/.config/autostart/qBitTorrent.desktop
~/.config/qBittorrent/
```

## Services

```bash
sudo systemctl enable torrent-netns.service
sudo systemctl enable torrent-vpn.service
```

Check:

```bash
sudo systemctl is-active torrent-netns.service
sudo systemctl is-active torrent-vpn.service
```

Both should return:

```text
active
```

## Quick tests

VPN IP:

```bash
sudo ip netns exec torrent curl -4 https://api.ipify.org
```

Expected:

```text
193.187.90.195
```

WireGuard:

```bash
sudo ip netns exec torrent wg show
```

qBittorrent:

```bash
sudo ip netns exec torrent pgrep -a qbittorrent
```

WebUI:

```bash
curl http://10.200.0.2:8080
```


## Kill-switch Test

VPN down:

```bash
sudo ip netns exec torrent wg-quick down /etc/wireguard/azirevpn.conf
```

Internet from namespace must **fail** — it must never fall back to the normal ISP IP.

## Restore:

```bash
sudo systemctl restart torrent-vpn.service
```

## Troubleshooting

```bash
sudo systemctl status torrent-vpn.service
sudo journalctl -u torrent-vpn.service -n 40 --no-pager
sudo systemctl restart torrent-vpn.service
```

If WireGuard says `azirevpn already exists`:

```bash
sudo ip netns exec torrent wg-quick down /etc/wireguard/azirevpn.conf
sudo systemctl reset-failed torrent-vpn.service
sudo systemctl start torrent-vpn.service
```

### Recovery order

```text
torrent-netns.service
        ↓
torrent-vpn.service
        ↓
qBittorrent
```

Traefik continues to access qBittorrent directly via:

```text
10.200.0.2:8080
```

