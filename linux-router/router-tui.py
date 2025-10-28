#!/usr/bin/env python3
"""
Dynamic Router Terminal UI (TUI)
A terminal-based interface for monitoring and controlling the dynamic router
Usage: sudo python3 router-tui.py
Controls: q=quit, r=restart, s=stop, l=logs, h=help
"""

import curses
import subprocess
import time
from datetime import datetime
import sys

def run_command(cmd):
    """Execute shell command and return output"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        return result.stdout.strip()
    except:
        return ""

def get_human_readable_bytes(bytes_val):
    """Convert bytes to human readable format"""
    try:
        bytes_val = int(bytes_val)
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes_val < 1024.0:
                return f"{bytes_val:.1f} {unit}"
            bytes_val /= 1024.0
        return f"{bytes_val:.1f} PB"
    except:
        return "0 B"

def get_router_status():
    """Gather all router status information"""
    data = {}

    # Service status
    service_status = run_command("systemctl is-active dynamic-router.service 2>/dev/null")
    data['service_active'] = service_status == "active"
    data['service_status_raw'] = service_status

    # Uptime
    if data['service_active']:
        uptime_output = run_command("systemctl show dynamic-router.service -p ActiveEnterTimestamp --value")
        if uptime_output:
            try:
                start_time = datetime.strptime(uptime_output, "%a %Y-%m-%d %H:%M:%S %Z")
                uptime = datetime.now() - start_time
                days = uptime.days
                hours, remainder = divmod(uptime.seconds, 3600)
                minutes, _ = divmod(remainder, 60)
                data['uptime'] = f"{days}d {hours}h {minutes}m"
            except:
                data['uptime'] = "Unknown"
    else:
        data['uptime'] = "Not running"

    # Network interfaces
    data['wan_iface'] = run_command("ip route | awk '/^default/ {print $5; exit}'")
    if data['wan_iface']:
        data['wan_ip'] = run_command(f"ip addr show {data['wan_iface']} | grep 'inet ' | awk '{{print $2}}' | cut -d'/' -f1")
        wan_dns_output = run_command(f"nmcli dev show {data['wan_iface']} | awk '/IP4.DNS/ {{print $2}}'")
        data['wan_dns'] = wan_dns_output.split() if wan_dns_output else []
    else:
        data['wan_ip'] = "N/A"
        data['wan_dns'] = []

    data['lan_iface'] = run_command("grep 'interface=' /etc/dnsmasq.d/lan.conf 2>/dev/null | cut -d'=' -f2")
    if not data['lan_iface']:
        data['lan_iface'] = run_command("systemctl show dynamic-router.service -p ExecStart --value | grep -oP 'ens\\d+|enp\\d+s\\d+' | head -1")
    if data['lan_iface']:
        data['lan_ip'] = run_command(f"ip addr show {data['lan_iface']} 2>/dev/null | grep 'inet ' | awk '{{print $2}}'")
    else:
        data['lan_ip'] = "N/A"

    lan_dns_output = run_command("grep '^server=' /etc/dnsmasq.d/lan.conf 2>/dev/null | cut -d'=' -f2")
    data['lan_dns'] = lan_dns_output.split() if lan_dns_output else []

    # VPN detection
    data['vpn_iface'] = run_command("ip link show | grep -oP '(tun|wg|tap)\\d+' | head -1")
    data['vpn_active'] = bool(data['vpn_iface'])

    # Traffic stats
    if data['wan_iface']:
        rx = run_command(f"cat /sys/class/net/{data['wan_iface']}/statistics/rx_bytes 2>/dev/null")
        tx = run_command(f"cat /sys/class/net/{data['wan_iface']}/statistics/tx_bytes 2>/dev/null")
        data['rx_bytes'] = get_human_readable_bytes(rx)
        data['tx_bytes'] = get_human_readable_bytes(tx)
    else:
        data['rx_bytes'] = "0 B"
        data['tx_bytes'] = "0 B"

    # Connections
    conns = run_command("ss -t state established | wc -l")
    try:
        data['connections'] = max(0, int(conns) - 1)
    except:
        data['connections'] = 0

    # LAN clients
    if data['lan_iface']:
        clients_output = run_command(f"ip neigh show dev {data['lan_iface']}")
        clients = []
        for line in clients_output.split('\n'):
            if line and any(state in line for state in ['REACHABLE', 'STALE', 'DELAY']):
                ip = line.split()[0]
                if not ip.startswith('169.254.'):
                    clients.append(ip)
        data['clients'] = clients
        data['lan_clients'] = len(clients)
    else:
        data['clients'] = []
        data['lan_clients'] = 0

    return data

def draw_box(stdscr, y, x, height, width, title=""):
    stdscr.addstr(y, x, "┌" + "─"*(width-2) + "┐")
    for i in range(1, height-1):
        stdscr.addstr(y+i, x, "│" + " "*(width-2) + "│")
    stdscr.addstr(y+height-1, x, "└" + "─"*(width-2) + "┘")
    if title:
        stdscr.addstr(y, x+2, f" {title} ", curses.A_BOLD)

def show_logs(stdscr):
    stdscr.clear()
    height, width = stdscr.getmaxyx()
    logs = run_command("journalctl -u dynamic-router.service -n 100 --no-pager")
    lines = logs.split('\n')
    title = "═ ROUTER LOGS (Press any key to return) ═"
    stdscr.addstr(0, (width-len(title))//2, title, curses.A_BOLD | curses.color_pair(3))
    start_line = max(0, len(lines)-(height-3))
    for i, line in enumerate(lines[start_line:]):
        if i >= height-2: break
        color = curses.color_pair(1)
        if 'ERROR' in line: color = curses.color_pair(2)
        elif 'WARNING' in line: color = curses.color_pair(4)
        elif 'INFO' in line and '✓' in line: color = curses.color_pair(3)
        stdscr.addstr(i+2, 0, line[:width-1], color)
    stdscr.refresh()
    stdscr.getch()

def confirm_action(stdscr, message):
    height, width = stdscr.getmaxyx()
    dialog_height = 7
    dialog_width = len(message)+10
    dialog_y = (height - dialog_height)//2
    dialog_x = (width - dialog_width)//2
    draw_box(stdscr, dialog_y, dialog_x, dialog_height, dialog_width, "CONFIRM")
    stdscr.addstr(dialog_y+2, dialog_x+5, message)
    stdscr.addstr(dialog_y+4, dialog_x+5, "[Y]es  [N]o", curses.A_BOLD)
    stdscr.refresh()
    while True:
        key = stdscr.getch()
        if key in [ord('y'), ord('Y')]: return True
        if key in [ord('n'), ord('N'), 27]: return False

def show_message(stdscr, message, color=1):
    height, width = stdscr.getmaxyx()
    stdscr.addstr(height-2, 2, " "*(width-4))
    stdscr.addstr(height-2, 2, message, curses.color_pair(color)|curses.A_BOLD)
    stdscr.refresh()

def main(stdscr):
    curses.start_color()
    curses.init_pair(1, curses.COLOR_CYAN, curses.COLOR_BLACK)
    curses.init_pair(2, curses.COLOR_RED, curses.COLOR_BLACK)
    curses.init_pair(3, curses.COLOR_GREEN, curses.COLOR_BLACK)
    curses.init_pair(4, curses.COLOR_YELLOW, curses.COLOR_BLACK)
    curses.init_pair(5, curses.COLOR_WHITE, curses.COLOR_BLACK)
    curses.init_pair(6, curses.COLOR_MAGENTA, curses.COLOR_BLACK)

    curses.curs_set(0)
    stdscr.nodelay(1)
    stdscr.timeout(1000)

    last_update = 0
    status_data = {}

    while True:
        now = time.time()
        if now - last_update >= 1:
            status_data = get_router_status()
            last_update = now

        stdscr.clear()
        height, width = stdscr.getmaxyx()
        stdscr.addstr(0, (width-33)//2, "═══ DYNAMIC VM ROUTER DASHBOARD ═══", curses.A_BOLD | curses.color_pair(1))
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        stdscr.addstr(0, width-len(timestamp)-2, timestamp, curses.color_pair(5))

        y = 2
        status_color = curses.color_pair(3) if status_data.get('service_active') else curses.color_pair(2)
        status_text = "● RUNNING" if status_data.get('service_active') else "● STOPPED"
        stdscr.addstr(y, 2, status_text, status_color | curses.A_BOLD)
        raw_status = status_data.get('service_status_raw','unknown')
        stdscr.addstr(y, 15, f"({raw_status})", curses.color_pair(5))
        stdscr.addstr(y, 35, f"Uptime: {status_data.get('uptime','N/A')}", curses.color_pair(5))

        # NETWORK box (tightened)
        y += 2
        draw_box(stdscr, y, 2, 8, width-4, "NETWORK INTERFACES")
        y += 1
        stdscr.addstr(y, 4, "WAN:", curses.A_BOLD)
        stdscr.addstr(y, 10, f"{status_data.get('wan_iface','N/A')} ({status_data.get('wan_ip','N/A')})", curses.color_pair(3))
        stdscr.addstr(y, 45, "DNS:", curses.A_BOLD)
        stdscr.addstr(y, 50, ", ".join(status_data.get('wan_dns',[])), curses.color_pair(1))

        y += 1
        stdscr.addstr(y, 4, "LAN:", curses.A_BOLD)
        stdscr.addstr(y, 10, f"{status_data.get('lan_iface','N/A')} ({status_data.get('lan_ip','N/A')})", curses.color_pair(3))
        stdscr.addstr(y, 45, "DNS:", curses.A_BOLD)
        stdscr.addstr(y, 50, ", ".join(status_data.get('lan_dns',[])), curses.color_pair(3))

        y += 1
        stdscr.addstr(y, 4, "VPN:", curses.A_BOLD)
        if status_data.get('vpn_active'):
            vpn_text = f"Connected ({status_data.get('vpn_iface','unknown')})"
            stdscr.addstr(y, 10, vpn_text, curses.color_pair(3))
        else:
            stdscr.addstr(y, 10, "Disconnected", curses.color_pair(4))

        # Statistics
        y += 2
        draw_box(stdscr, y, 2, 6, width//2-3, "STATISTICS")
        y += 1
        stdscr.addstr(y, 4, f"Downloaded:  {status_data.get('rx_bytes','0 B')}", curses.color_pair(1))
        y += 1
        stdscr.addstr(y, 4, f"Uploaded:    {status_data.get('tx_bytes','0 B')}", curses.color_pair(1))
        y += 1
        stdscr.addstr(y, 4, f"Connections: {status_data.get('connections',0)}", curses.color_pair(1))

        # LAN Clients
        clients_y = y-3
        draw_box(stdscr, clients_y, width//2+1, 6, width//2-3, "LAN CLIENTS")
        clients_y += 1
        stdscr.addstr(clients_y, width//2+3, f"Total: {status_data.get('lan_clients',0)}", curses.color_pair(6)|curses.A_BOLD)
        clients_y += 1
        clients = status_data.get('clients',[])
        for i, ip in enumerate(clients[:2]):
            stdscr.addstr(clients_y+i, width//2+3, f"• {ip}", curses.color_pair(3))
        if len(clients)>2:
            stdscr.addstr(clients_y+2, width//2+3, f"... and {len(clients)-2} more", curses.color_pair(5))

        # Controls
        y = height-4
        stdscr.addstr(y, 2, "─"*(width-4), curses.color_pair(5))
        y += 1
        controls = "[Q]uit  [R]estart  [S]top  [L]ogs  [H]elp"
        stdscr.addstr(y, (width-len(controls))//2, controls, curses.A_BOLD|curses.color_pair(6))

        stdscr.refresh()

        try:
            key = stdscr.getch()
            if key in [ord('q'), ord('Q')]:
                break
            elif key in [ord('r'), ord('R')]:
                if confirm_action(stdscr, "Restart router service?"):
                    run_command("systemctl restart dynamic-router.service")
                    show_message(stdscr,"✓ Router service restarted",3)
                    time.sleep(2)
            elif key in [ord('s'), ord('S')]:
                if confirm_action(stdscr, "Stop router service?"):
                    run_command("systemctl stop dynamic-router.service")
                    show_message(stdscr,"✓ Router service stopped",4)
                    time.sleep(2)
            elif key in [ord('l'), ord('L')]:
                show_logs(stdscr)
            elif key in [ord('h'), ord('H')]:
                stdscr.clear()
                help_text = ["═══ HELP ═══","","Q - Quit","R - Restart router service","S - Stop router service",
                             "L - View full logs","H - Show this help","","Dashboard refreshes every second.","",
                             "Press any key to return..."]
                for i,line in enumerate(help_text):
                    attr = curses.A_BOLD if i==0 else curses.A_NORMAL
                    stdscr.addstr(i+2,(width-len(line))//2,line,attr)
                stdscr.refresh()
                stdscr.getch()
        except KeyboardInterrupt:
            break
        except:
            pass

if __name__=='__main__':
    try:
        curses.wrapper(main)
    except KeyboardInterrupt:
        print("\nExiting...")
        sys.exit(0)
