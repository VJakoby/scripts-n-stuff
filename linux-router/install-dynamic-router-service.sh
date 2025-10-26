#!/bin/bash
# install-dynamic-router-service.sh
# TO CHANGE:
# Set the following values:
# <LAN_IFACE>
# <LAN_IP/CIDR>
# <PRIMARY_DNS>
# <SECONDARY_DNS>

# Move script to /usr/local/bin
sudo mv dynamic-router.sh /usr/local/bin/dynamic-router.sh
sudo chmod +x /usr/local/bin/dynamic-router.sh

# Create a systemd service
sudo tee /etc/systemd/system/dynamic-router.service > /dev/null <<EOF
[Unit]
Description=Dynamic VM Router
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/dynamic-router.sh <LAN_IFACE> <LAN_IP/CIDR> <PRIMARY_DNS> <SECONDARY_DNS>
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable dynamic-router.service
sudo systemctl start dynamic-router.service

echo "[INFO] dynamic-router service installed and started."
