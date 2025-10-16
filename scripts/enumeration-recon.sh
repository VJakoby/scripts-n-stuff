#!/bin/bash
# Requirements:
# sudo apt install httprobe eyewitness assetfinder subjack waybackurls

# Usage: ./enumeration-recon.sh <domain|domains.txt>
set -u

run_recon() {
    local url="$1"

    echo "==> Starting recon for: $url"

    if [ ! -d "$url" ]; then
        mkdir -p "$url"
    fi
    if [ ! -d "$url/recon" ]; then
        mkdir -p "$url/recon"
    fi
    if [ ! -d "$url/recon/scans" ]; then
        mkdir -p "$url/recon/scans"
    fi
    if [ ! -d "$url/recon/httprobe" ]; then
        mkdir -p "$url/recon/httprobe"
    fi
    if [ ! -d "$url/recon/potential_takeovers" ]; then
        mkdir -p "$url/recon/potential_takeovers"
    fi
    if [ ! -d "$url/recon/wayback" ]; then
        mkdir -p "$url/recon/wayback"
    fi
    if [ ! -d "$url/recon/wayback/params" ]; then
        mkdir -p "$url/recon/wayback/params"
    fi
    if [ ! -d "$url/recon/wayback/extensions" ]; then
        mkdir -p "$url/recon/wayback/extensions"
    fi
    if [ ! -f "$url/recon/httprobe/alive.txt" ]; then
        touch "$url/recon/httprobe/alive.txt"
    fi
    if [ ! -f "$url/recon/final.txt" ]; then
        touch "$url/recon/final.txt"
    fi

    echo "[+] Harvesting subdomains with assetfinder..."
    assetfinder "$url" >> "$url/recon/assets.txt"
    cat "$url/recon/assets.txt" | grep "$url" >> "$url/recon/final.txt" || true
    rm -f "$url/recon/assets.txt"

    echo "[+] Probing for alive domains..."
    cat "$url/recon/final.txt" | sort -u | httprobe -s -p https:443 | sed 's/https\?:\/\///' | tr -d ':443' >> "$url/recon/httprobe/a.txt" || true
    sort -u "$url/recon/httprobe/a.txt" > "$url/recon/httprobe/alive.txt" || true
    rm -f "$url/recon/httprobe/a.txt"

    echo "[+] Checking for possible subdomain takeover..."
    if [ ! -f "$url/recon/potential_takeovers/potential_takeovers.txt" ]; then
        touch "$url/recon/potential_takeovers/potential_takeovers.txt"
    fi

    subjack -w "$url/recon/final.txt" -t 100 -timeout 30 -ssl -c ~/go/src/github.com/haccer/subjack/fingerprints.json -v 3 -o "$url/recon/potential_takeovers/potential_takeovers.txt" || true

    echo "[+] Scanning for open ports..."
    if [ -s "$url/recon/httprobe/alive.txt" ]; then
        nmap -iL "$url/recon/httprobe/alive.txt" -T4 -oA "$url/recon/scans/scanned.txt" || true
    else
        echo "    No alive hosts for nmap scan."
    fi

    echo "[+] Scraping wayback data..."
    cat "$url/recon/final.txt" | waybackurls >> "$url/recon/wayback/wayback_output.txt" || true
    sort -u "$url/recon/wayback/wayback_output.txt" -o "$url/recon/wayback/wayback_output.txt" || true

    echo "[+] Pulling and compiling all possible params found in wayback data..."
    grep -E '\?.+=' "$url/recon/wayback/wayback_output.txt" | cut -d '=' -f 1 | sort -u >> "$url/recon/wayback/params/wayback_params.txt" || true
    if [ -f "$url/recon/wayback/params/wayback_params.txt" ]; then
        while IFS= read -r line; do
            printf '%s=\n' "$line"
        done < "$url/recon/wayback/params/wayback_params.txt"
    fi

    echo "[+] Pulling and compiling js/php/aspx/jsp/json files from wayback output..."
    # reset tmp files
    rm -f "$url/recon/wayback/extensions/"*.txt || true
    while IFS= read -r line; do
        ext="${line##*.}"
        case "$ext" in
            js)
                echo "$line" >> "$url/recon/wayback/extensions/js1.txt"
                sort -u "$url/recon/wayback/extensions/js1.txt" > "$url/recon/wayback/extensions/js.txt" || true
                ;;
            html)
                echo "$line" >> "$url/recon/wayback/extensions/jsp1.txt"
                sort -u "$url/recon/wayback/extensions/jsp1.txt" > "$url/recon/wayback/extensions/jsp.txt" || true
                ;;
            json)
                echo "$line" >> "$url/recon/wayback/extensions/json1.txt"
                sort -u "$url/recon/wayback/extensions/json1.txt" > "$url/recon/wayback/extensions/json.txt" || true
                ;;
            php)
                echo "$line" >> "$url/recon/wayback/extensions/php1.txt"
                sort -u "$url/recon/wayback/extensions/php1.txt" > "$url/recon/wayback/extensions/php.txt" || true
                ;;
            aspx)
                echo "$line" >> "$url/recon/wayback/extensions/aspx1.txt"
                sort -u "$url/recon/wayback/extensions/aspx1.txt" > "$url/recon/wayback/extensions/aspx.txt" || true
                ;;
        esac
    done < "$url/recon/wayback/wayback_output.txt"

    rm -f "$url/recon/wayback/extensions/js1.txt" "$url/recon/wayback/extensions/jsp1.txt" "$url/recon/wayback/extensions/json1.txt" "$url/recon/wayback/extensions/php1.txt" "$url/recon/wayback/extensions/aspx1.txt" || true

    echo "==> Done for: $url"
    echo
}

usage() {
    echo "Usage: $0 <domain|file_with_domains>"
    echo "  Example single domain: $0 example.com"
    echo "  Example file:         $0 domains.txt  (one domain per line, '#' or empty lines ignored)"
    exit 1
}

# --- Main logic: accept single domain or file with domains ---
if [ $# -ne 1 ]; then
    usage
fi

input="$1"

if [ -f "$input" ]; then
    echo "[*] Input is a file. Iterating domains in $input"
    # read file, ignore blank lines and comments (lines starting with #)
    while IFS= read -r line || [ -n "$line" ]; do
        # trim whitespace
        dom="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        # skip empty or comment lines
        if [ -z "$dom" ] || [[ "$dom" == \#* ]]; then
            continue
        fi
        run_recon "$dom"
    done < "$input"
else
    # treat as single domain
    run_recon "$input"
fi
