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

# Local dig check
check_record() {
  local type=$1
  local name=$2
  dig +short "$name" "$type"
}

# Web API check (Google DNS-over-HTTPS)
check_api_record() {
  local type=$1
  local name=$2
  curl -s "https://dns.google/resolve?name=${name}&type=${type}" | jq -r '.Answer[]?.data' 2>/dev/null
}

# SPF
echo "[SPF]"
spf_local=$(check_record TXT "$domain" | grep -i "v=spf1")
spf_api=$(check_api_record TXT "$domain" | grep -i "v=spf1")

if [ -n "$spf_local" ]; then
  echo -e "Local: ${GREEN}$spf_local${RESET}"
else
  echo -e "Local: ${RED}No SPF record found.${RESET}"
fi

if [ -n "$spf_api" ]; then
  echo -e "Web API: ${GREEN}$spf_api${RESET}"
else
  echo -e "Web API: ${RED}No SPF record found.${RESET}"
fi
echo

# DMARC
echo "[DMARC]"
dmarc_local=$(check_record TXT "_dmarc.$domain")
dmarc_api=$(check_api_record TXT "_dmarc.$domain")

if [ -n "$dmarc_local" ]; then
  echo -e "Local: ${GREEN}$dmarc_local${RESET}"
else
  echo -e "Local: ${RED}No DMARC record found.${RESET}"
fi

if [ -n "$dmarc_api" ]; then
  echo -e "Web API: ${GREEN}$dmarc_api${RESET}"
else
  echo -e "Web API: ${RED}No DMARC record found.${RESET}"
fi
echo

# DKIM
if [ -n "$selector" ]; then
  echo "[DKIM] (selector: $selector)"
  dkim_name="${selector}._domainkey.$domain"
  dkim_local=$(check_record TXT "$dkim_name")
  dkim_api=$(check_api_record TXT "$dkim_name")

  if [ -n "$dkim_local" ]; then
    echo -e "Local: ${GREEN}$dkim_local${RESET}"
  else
    echo -e "Local: ${RED}No DKIM record found.${RESET}"
  fi

  if [ -n "$dkim_api" ]; then
    echo -e "Web API: ${GREEN}$dkim_api${RESET}"
  else
    echo -e "Web API: ${RED}No DKIM record found.${RESET}"
  fi
else
  echo "[DKIM]"
  echo -e "${YELLOW}No selector provided — skipping DKIM check.${RESET}"
fi

echo
echo -e "=== ${GREEN}Check complete${RESET} ==="
