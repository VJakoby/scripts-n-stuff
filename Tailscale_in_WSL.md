## Tailscale in WSL


### Installera WSL och en Dist


### Installera Tailscale

```
curl -fsSL https://tailscale.com/install.sh | sh

# disable ipv6; only have to do this once
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
```

# Starta tailscale automatiskt vid start av WSL
```
#!/bin/bash

tmux new-session -d -s my_session 'sudo tailscaled && sudo tailscale up'
```
```
sudo chmod +x script.sh
echo "sudo sh ./script.sh
```