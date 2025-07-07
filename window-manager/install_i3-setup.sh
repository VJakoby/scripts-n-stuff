#!/bin/bash
# Script that installs i3 and dependencies

# Rofi themes are available here
# https://github.com/adi1090x/rofi
#git clone --depth=1 https://github.com/adi1090x/rofi.git
#cd rofi
#chmod +x setup.sh
#./setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Install required packages
echo "[+] Installing packages..."
sudo apt update
#sudo apt install -y i3 polybar rofi feh fonts-font-awesome pavucontrol acpi lm-sensors lightdm i3blocks
sudo apt install -y i3 i3blocks rofi feh fonts-font-awesome bc acpi

# 2. Downloading rofi themes for future use
echo "[+] Downloading rofi themes"
git clone --depth=1 https://github.com/adi1090x/rofi.git
cd rofi
chmod +x setup.sh
./setup.sh

# 2. Set up i3 config
echo "[+] Setting up i3 config..."
mkdir -p ~/.config/i3
cp "$SCRIPT_DIR/i3/config" ~/.config/i3/config

# 3. Setup i3blocks config
echo "[+] Setting up i3blocks"
mkdir -p ~/.config/i3blocks
cp "$SCRIPT_DIR/i3blocks/config" ~/.config/i3blocks/config
cp "$SCRIPT_DIR/i3blocks/rofi-launch.sh" ~/.config/i3blocks/
cp "$SCRIPT_DIR/i3blocks/cpu.sh" ~/.config/i3blocks/

mkdir p ~/.config/rofi
cp "$SCRIPT_DIR/rofi/config.rasi" ~/.config/rofi/

# 4. Setup LightDM (optional but recommended)
echo "[+] Ensuring lightdm is set as display manager..."
sudo debconf-set-selections <<< "lightdm shared/default-x-display-manager select lightdm"
sudo dpkg-reconfigure -f noninteractive lightdm

# 6. Done
echo -e "\n✅ All done!"
echo "Reboot and at the login screen, choose i3 session (bottom-right gear icon if available)."
