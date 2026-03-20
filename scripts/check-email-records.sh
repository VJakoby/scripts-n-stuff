#!/usr/bin/env bash
# check_mail_dns.sh
# Usage: ./check_mail_dns.sh <domain> [selector]

domain=$1
selector=$2

# Colors
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

# Dependency Check
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: 'jq' is not installed. Please install it to use Web API features.${RESET}"
    exit 1
fi

if [ -z "$domain" ]; then
    echo -e "${YELLOW}Usage:${RESET} $0 <domain> [selector]"
    exit 1
fi

clear
echo -e "${CYAN}==============================================${RESET}"
echo -e "${CYAN}         EMAIL RECORDS CHECK                  ${RESET}"
echo -e "${CYAN}==============================================${RESET}"
echo -e "Target Domain: ${YELLOW}$domain${RESET}"
echo

# --- Helper Functions ---

check_record() {
    local type=$1
    local name=$2
    dig +short "$name" "$type" | tr -d '"'
}

check_api_record() {
    local type=$1
    local name=$2
    curl -s "https://dns.google/resolve?name=${name}&type=${type}" | \
    jq -r '.Answer[]? | .data' 2>/dev/null | tr -d '"'
}

print_result() {
    local label=$1
    local local_val=$2
    local api_val=$3
    
    echo -e "${CYAN}[$label]${RESET}"
    if [ -n "$local_val" ]; then
        echo -e "  Local:   ${GREEN}$local_val${RESET}"
    else
        echo -e "  Local:   ${RED}Not Found${RESET}"
    fi

    if [ -n "$api_val" ]; then
        echo -e "  Web API: ${GREEN}$api_val${RESET}"
    else
        echo -e "  Web API: ${RED}Not Found${RESET}"
    fi
    echo
}

# --- Checks ---

# 1. MX Records
echo -e "${CYAN}[MX RECORDS]${RESET}"
mx_local=$(check_record MX "$domain")
if [ -n "$mx_local" ]; then
    echo -e "${GREEN}$mx_local${RESET}"
else
    echo -e "${RED}No MX records found. Domain cannot receive email.${RESET}"
fi
echo

# 2. SPF
spf_local=$(check_record TXT "$domain" | grep -i "v=spf1")
spf_api=$(check_api_record TXT "$domain" | grep -i "v=spf1")
print_result "SPF" "$spf_local" "$spf_api"

# 3. DMARC
dmarc_local=$(check_record TXT "_dmarc.$domain")
dmarc_api=$(check_api_record TXT "_dmarc.$domain")
print_result "DMARC" "$dmarc_local" "$dmarc_api"

# 4. DKIM
if [ -n "$selector" ]; then
    dkim_name="${selector}._domainkey.$domain"
    dkim_local=$(check_record TXT "$dkim_name")
    dkim_api=$(check_api_record TXT "$dkim_name")
    print_result "DKIM (Selector: $selector)" "$dkim_local" "$dkim_api"
else
    echo -e "${CYAN}[DKIM]${RESET}"
    echo -e "  ${YELLOW}No selector provided — skipping DKIM check.${RESET}"
    echo
fi

# 5. BIMI (Optional)
bimi_local=$(check_record TXT "default._bimi.$domain")
bimi_api=$(check_api_record TXT "default._bimi.$domain")
print_result "BIMI (Brand Icon)" "$bimi_local" "$bimi_api"

echo -e "${CYAN}==============================================${RESET}"
echo -e "${GREEN}            CHECK COMPLETE                    ${RESET}"
echo -e "${CYAN}==============================================${RESET}"
