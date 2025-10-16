#!/usr/bin/env bash

# Usage: ./check_ssl.sh domains.txt

input_file="$1"

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

if [ -z "$input_file" ]; then
    echo "Usage: $0 <domain_list_file>"
    exit 1
fi

if [ ! -f "$input_file" ]; then
    echo "Error: file '$input_file' not found."
    exit 1
fi

while read -r domain; do
    [[ -z "$domain" || "$domain" =~ ^# ]] && continue

    cert_data=$(timeout 5 openssl s_client -connect "${domain}:443" -servername "$domain" </dev/null 2>/dev/null | openssl x509 -noout -subject -enddate 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$cert_data" ]; then
        echo -e "${RED}${domain} --> Certificate not found${NC}"
        continue
    fi

    cn=$(echo "$cert_data" | sed -n 's/.*CN=\(.*\)/\1/p')
    end_date=$(echo "$cert_data" | grep 'notAfter=' | cut -d'=' -f2-)
    end_epoch=$(date -d "$end_date" +%s 2>/dev/null)
    now_epoch=$(date +%s)

    if [ -z "$end_epoch" ]; then
        echo -e "${RED}${domain} --> Could not parse certificate date${NC}"
        continue
    fi

    if [ "$end_epoch" -lt "$now_epoch" ]; then
        echo -e "${RED}${domain} --> Certificate found: {CommonName: $cn, Expires: $end_date, Status: EXPIRED}${NC}"
    else
        echo -e "${GREEN}${domain} --> Certificate found: {CommonName: $cn, Expires: $end_date}${NC}"
    fi
done < "$input_file"
