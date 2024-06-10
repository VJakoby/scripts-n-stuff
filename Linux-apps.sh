#!/bin/bash

# Install apps
install_kali_apps() {
        "\[*] Installing Kali specific apps only..."

        # RustScan
        wget https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb
        dpkg -i rustscan_*
}

install_i3_desktop() {
        # Install i3 desktop
        sudo apt install i3 polybar nitrogen rofi

        # Polybar themes
        git clone --depth=1 https://github.com/adi1090x/polybar-themes.git
        cd $HOME/polybar-themes
        chmod +x setup.sh

        # Copy i3 pre-config to .config/i3/ directory on host
        cp i3/config $HOME/.config/i3/

        # Git-dumper
        pip install git-dumper
}

main() {
        clear
        cat <<- EOF
                [*] Choose your option to install...

                [1] Kali specific apps
                [2] i3 desktop packages and pre-defined configs
                [3] Both
                     
        EOF

        read -p "[?] SELECT OPTION : "

        if [[ $REPLY == "1" ]]; then
                install_kali_apps
        elif [[ $REPLY == "2" ]]; then
                install_i3_desktop
	elif [[ $REPLY == "3" ]]; then
                install_kali_apps
                install_i3_desktop
        else
	        echo -e "\n[!] Invalid Option, Exiting...\n"
		exit 1
	fi
}

main

