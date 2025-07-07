### Commands & Scripts
#### External IP Script
**ip-widget.sh**
```
#!/bin/bash

# Prints the external IP of the network connection

external_ip=$(curl -s https://api.ipify.org)
echo $external_ip
```

```
#### WHOAMI
*Whoami provides enhanced privacy, anonymity for Debian linux distributions*
https://github.com/owerdogan/whoami-project

```
sudo apt update && sudo apt install tar tor curl python3 python3-scapy network-manager

git clone https://github.com/omer-dogan/kali-whoami

sudo make install
```
#### Anonsurf (Ported)
Connect to TOR network, 
https://github.com/Und3rf10w/kali-anonsurf

```
git clone https://github.com/Und3rf10w/kali-anonsurf
cd kali-anonsurf && sudo chmod +x ./installer.sh
./installer.sh
```