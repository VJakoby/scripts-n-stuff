#!/usr/bin/env bash
# check_mail_dns.sh
# Usage: ./check_mail_dns.sh <domain> [selector]

domain=$1
selector=$2

# Colors
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"

if [ -z "$domain" ]; then
  echo -e "${YELLOW}Usage:${RESET} $0 <domain> [selector]"
  exit 1
fi

echo -e "=== Checking DNS records for: ${YELLOW}$domain${RESET} ==="
echo

# SPF
echo "[SPF]"
spf=$(dig +short TXT "$domain" | grep -i "v=spf1")
if [ -n "$spf" ]; then
  echo -e "${GREEN}$spf${RESET}"
else
  echo -e "${RED}No SPF record found.${RESET}"
fi
echo

# DMARC
echo "[DMARC]"
dmarc=$(dig +short TXT "_dmarc.$domain")
if [ -n "$dmarc" ]; then
  echo -e "${GREEN}$dmarc${RESET}"
else
  echo -e "${RED}No DMARC record found.${RESET}"
fi
echo

# DKIM
if [ -n "$selector" ]; then
  echo "[DKIM] (selector: $selector)"
  dkim_record=$(dig +short TXT "${selector}._domainkey.$domain")
  if [ -n "$dkim_record" ]; then
    echo -e "${GREEN}$dkim_record${RESET}"
  else
    echo -e "${RED}No DKIM record found for selector '$selector'.${RESET}"
  fi
else
  echo "[DKIM]"
  echo -e "${YELLOW}No selector provided — skipping DKIM check.${RESET}"
fi

echo
echo -e "=== ${GREEN}Check complete${RESET} ==="
