#!/bin/bash

# Kontrollera om rätt antal argument har angetts
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <target_network>"
    exit 1
fi

# Hämta mål-nätverket från argumentet
target_network=$1

# Ersätt '/' med '-' i filnamnet
filename_prefix=$(echo $target_network | tr '/' '-')

# Kör Nmap-kommandot och spara utdata till filer
nmap -sn -T4 -n $target_network -oN nmap-output-$filename_prefix.txt | grep "Nmap scan report for" | awk '{print $5}' > $filename_prefix.txt

echo "Raw nmap-output saved to: nmap-output-$filename_prefix.txt"
echo "Live IP-addersses saved to: $filename_prefix.txt"
