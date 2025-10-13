#!/bin/bash
# Script that installs i3 and dependencies

## Rofi themes are available here
# https://github.com/newmanls/rofi-themes-collection?tab=readme-ov-file

#!/bin/bash
# Script that installs i3 and dependencies

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Helper function for safe copy
safe_copy() {
    src="$1"
    dest="$2"
    if [ -f "$src" ]; then
        cp "$src" "$dest"
        echo "   Copied: $src → $dest"
    else
        echo "   ⚠️  Warning: missing file $src, skipped."
    fi
}

# 1. Install required packages
echo "[+] Installing packages..."
sudo apt update
sudo apt install -y i3 i3blocks rofi polybar feh fonts-font-awesome bc acpi lightdm pavucontrol lm-sensors lxappearance

# 2. Set up i3 config
echo "[+] Setting up i3 config..."
mkdir -p ~/.config/i3
safe_copy "$SCRIPT_DIR/i3/config" ~/.config/i3/config

# 3. Setup i3blocks config
echo "[+] Setting up i3blocks"
mkdir -p ~/.config/i3blocks
safe_copy "$SCRIPT_DIR/i3blocks/config" ~/.config/i3blocks/config
safe_copy "$SCRIPT_DIR/i3blocks/rofi-launch.sh" ~/.config/i3blocks/rofi-launch.sh
safe_copy "$SCRIPT_DIR/i3blocks/cpu.sh" ~/.config/i3blocks/cpu.sh
safe_copy "$SCRIPT_DIR/i3blocks/reboot.sh" ~/.config/i3blocks/reboot.sh
safe_copy "$SCRIPT_DIR/i3blocks/poweroff.sh" ~/.config/i3blocks/poweroff.sh

# 4. Setup polybar
echo "[+] Setting up polybar"
mkdir -p ~/.config/polybar
safe_copy "$SCRIPT_DIR/polybar/config.ini" ~/.config/polybar/config.ini

# 5. Setup rofi config
echo "[+] Setting up rofi config"
mkdir -p ~/.config/rofi
safe_copy "$SCRIPT_DIR/rofi/config.rasi" ~/.config/rofi/config.rasi

# 6. Setup LightDM (optional but recommended)
echo "[+] Ensuring lightdm is set as display manager..."
if dpkg -l | grep -q lightdm; then
    sudo debconf-set-selections <<< "lightdm shared/default-x-display-manager select lightdm"
    sudo dpkg-reconfigure -f noninteractive lightdm
else
    echo "   ⚠️  Warning: lightdm not installed correctly."
fi

# 7. Done
echo -e "\n✅ Everything completed!"
echo "Reboot and at the login screen, choose i3 session (bottom-right gear icon if available)."
