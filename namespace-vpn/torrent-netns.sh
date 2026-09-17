#!/bin/bash

#/usr/local/sbin/torrent-netns.sh

set -e

NS="torrent"
HOST_VETH="veth-host"
NS_VETH="veth-torrent"

# Create namespace if missing
if ! ip netns list | grep -qw "$NS"; then
    ip netns add "$NS"
fi

# Create veth pair if missing
if ! ip link show "$HOST_VETH" >/dev/null 2>&1; then
    ip link add "$HOST_VETH" type veth peer name "$NS_VETH"
    ip link set "$NS_VETH" netns "$NS"
fi

# Host side
ip addr add 10.200.0.1/24 dev "$HOST_VETH" 2>/dev/null || true
ip link set "$HOST_VETH" up

# Namespace side
ip netns exec "$NS" ip link set lo up
ip netns exec "$NS" ip addr add 10.200.0.2/24 dev "$NS_VETH" 2>/dev/null || true
ip netns exec "$NS" ip link set "$NS_VETH" up

# Default route
ip netns exec "$NS" ip route replace default via 10.200.0.1

# Enable forwarding
sysctl -w net.ipv4.ip_forward=1

# NAT to normal Internet connection
iptables -t nat -C POSTROUTING \
    -s 10.200.0.0/24 -o eno1 -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING \
    -s 10.200.0.0/24 -o eno1 -j MASQUERADE