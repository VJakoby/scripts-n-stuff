#!/bin/bash

#usr/local/sbin/torrent-vpn.sh¨

set -e

NS="torrent"
WG_CONFIG="/etc/wireguard/azire.conf"

# Start WireGuard inside namespace
ip netns exec "$NS" wg-quick up "$WG_CONFIG"

# Install kill switch
ip netns exec "$NS" nft -f /etc/nftables.d/torrent-killswitch.nft