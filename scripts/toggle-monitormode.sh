#!/usr/bin/env bash
#
# toggle-monitor.sh
# Full robust toggle between managed <-> monitor mode for the first wireless interface
# Includes driver reload, NetworkManager handling, and verification of monitor support
# Set DRIVER_OVERRIDE if you know your specific driver module name (e.g. 8188eus)
#
set -euo pipefail

# ---------- Configuration ----------
DRIVER_OVERRIDE=""   # e.g. "8188eus" if you built a custom module
REQUIRE_STOP_NM=true # Stop NetworkManager temporarily to allow mode change
# -----------------------------------

# Colors
RED="\e[1;31m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
BLUE="\e[1;34m"
RESET="\e[0m"

# ---------- Helpers ----------
ensure_monitor_supported() {
    if iw list 2>/dev/null | grep -A5 "Supported interface modes" | grep -q "monitor"; then
        return 0
    else
        return 1
    fi
}

set_monitor_mode() {
    local IF="$1"
    local PRE_NM_ACTIVE=false

    echo -e "${YELLOW}Checking if driver supports monitor mode =${RESET}"
    if ! ensure_monitor_supported; then
        echo -e "${RED}Driver does NOT report monitor support. Aborting.${RESET}"
        return 2
    fi

    # Optionally stop NetworkManager
    if [ "$REQUIRE_STOP_NM" = true ] && command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager; then
        echo -e "${BLUE}Stopping NetworkManager...${RESET}"
        systemctl stop NetworkManager
        PRE_NM_ACTIVE=true
    fi

    ip link set "$IF" down || true
    echo -e "${BLUE}Attempting to set ${IF} -> monitor${RESET}"
    if iw dev "$IF" set type monitor 2>/dev/null; then
        ip link set "$IF" up
        sleep 0.2
    else
        # fallback
        iw dev "$IF" set type monitor >/dev/null 2>&1 || true
        ip link set "$IF" up || true
        sleep 0.2
    fi

    # Verify
    if iw dev "$IF" info 2>/dev/null | grep -iq "type.*monitor"; then
        echo -e "${GREEN}${IF} successfully set to monitor mode.${RESET}"
        if [ "$PRE_NM_ACTIVE" = true ]; then
            echo -e "${BLUE}Starting NetworkManager (keeps it from managing this interface)...${RESET}"
            systemctl start NetworkManager
        fi
        return 0
    else
        echo -e "${RED}Failed to set ${IF} to monitor mode — driver refused the change.${RESET}"
        iw dev "$IF" set type managed 2>/dev/null || true
        ip link set "$IF" up || true
        if [ "$PRE_NM_ACTIVE" = true ]; then
            systemctl start NetworkManager
        fi
        return 1
    fi
}
# ---------- End helpers ----------

# ---------- Root check ----------
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Run this script as root (sudo). Exiting.${RESET}"
    exit 1
fi

# ---------- Detect wireless interface ----------
INTERFACE=""
for IF in /sys/class/net/*; do
    IFNAME=$(basename "$IF")
    if [ -d "/sys/class/net/${IFNAME}/wireless" ] || [ -d "/sys/class/net/${IFNAME}/phy80211" ]; then
        INTERFACE="$IFNAME"
        break
    fi
done

if [ -z "$INTERFACE" ]; then
    echo -e "${RED}No wireless interface found (/sys/class/net/*/wireless).${RESET}"
    echo -e "${YELLOW}Check your driver or connection."
    echo "Try: lsmod | grep -i 8188; dmesg | grep -i realtek${RESET}"
    exit 1
fi

echo -e "${YELLOW}Detected interface =${RESET} ${GREEN}${INTERFACE}${RESET}"

# ---------- Get MAC and type ----------
MAC_ADDRESS="$(cat /sys/class/net/${INTERFACE}/address 2>/dev/null || true)"
CUR_TYPE="$(iw dev "${INTERFACE}" info 2>/dev/null | awk '/type/ {print $2; exit}' || true)"
if [ -z "$CUR_TYPE" ]; then
    CUR_TYPE="$(iwconfig "${INTERFACE}" 2>/dev/null | awk '/Mode:/ {print $1; exit}' || true)"
fi
echo -e "${YELLOW}MAC address =${RESET} ${GREEN}${MAC_ADDRESS:-unknown}${RESET}"
echo -e "${YELLOW}Current type =${RESET} ${GREEN}${CUR_TYPE:-unknown}${RESET}"

# ---------- Detect driver ----------
DRIVER=""
if command -v ethtool >/dev/null 2>&1; then
    DRIVER="$(ethtool -i "${INTERFACE}" 2>/dev/null | awk -F: '/driver:/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}' || true)"
fi
if [ -n "$DRIVER_OVERRIDE" ]; then
    DRIVER="$DRIVER_OVERRIDE"
fi
if [ -z "$DRIVER" ]; then
    echo -e "${RED}Could not determine driver module automatically.${RESET}"
    echo -e "${YELLOW}Set DRIVER_OVERRIDE in the script if you know it.${RESET}"
else
    echo -e "${YELLOW}Driver module =${RESET} ${GREEN}${DRIVER}${RESET}"
fi

# ---------- Toggle mode ----------
if [ "${CUR_TYPE}" = "monitor" ] || [ "${CUR_TYPE}" = "Monitor" ]; then
    # Switch to managed
    echo -e "${BLUE}Switching ${INTERFACE} -> managed${RESET}"
    ip link set "${INTERFACE}" down || true
    iw dev "${INTERFACE}" set type managed 2>/dev/null || true
    ip link set "${INTERFACE}" up
    if command -v nmcli >/dev/null 2>&1; then
        nmcli device set "${INTERFACE}" managed yes || true
    fi
    echo -e "${GREEN}${INTERFACE} is now in managed mode.${RESET}"
else
    # Switch to monitor using helper
    set_monitor_mode "${INTERFACE}"
fi

# ---------- Final status ----------
echo
echo -e "${YELLOW}iw dev output:${RESET}"
iw dev || true
echo
echo -e "${YELLOW}nmcli device status (if available):${RESET}"
nmcli device status 2>/dev/null || true

exit 0

# ---------- One-liner for manual toggle ----------
# sudo bash -c 'IF=$(ls /sys/class/net/*/wireless 2>/dev/null | head -n1 | xargs basename); nmcli device set $IF managed no >/dev/null 2>&1; ip link set $IF down; iw dev $IF set type monitor >/dev/null 2>&1; ip link set $IF up; iw dev $IF info'
