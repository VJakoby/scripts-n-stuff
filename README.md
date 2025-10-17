# Scripts-n-Stuff

**Nuclei-Templates**
- Contains custom-nuclei templates

**Scripts**
- Contains custom scripts like:
```
- check-dns-posts.sh         # Returns SPF, DMARC posts of a given domain, also DKIM of <selector> is provided
- check-ssl-cert.sh          # Returns SSL certificates on several domains from a txt file
- enumeration-recon.sh       # Automates domain reconnaissance by discovering subdomains, checking their availability, scanning for vulnerabilities, and extracting historical data and parameters for further analysis.
- hotspot-connect.sh         # Quick connect to a wifi hotspot from argument usage <SSID> <PASSWORD>
- nmap-discovery.py          # Nmap wrapper for scanning either single IP or several IPs from txt file. Written in python
- nmap-discovery-sh          # Nmap wrapper for scanning either single IP or several IPs from txt file: Written in bash
- toggle-vm-resolution.sh    # Toggle between two custom defined resolutions. Probably most suitable for laptop screen usage.
- wifi-dump.sh               # Quick script for enabling monitor-mode on wifi dongle, and dumping wifi traffic
```
**Window-manager**
- Contains i3, i3blocks and rofi installation script and config files
- Just run `install_i3-setup.sh`, will install i3 and other dependencies, copying the predefined config files. 
