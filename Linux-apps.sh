#!/bin/bash

# Global strings
DIR=


# Install apps
install_kali_apps() {
        
        "\[*] Installing Kali Specific apps only..."
        # Rustscan
                https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb

        # Kiterunner       


}



install_i3_desktop() {
        # Install i3 desktop
        sudo apt install i3 polybar nitrogen rofi

        # Polybar themes
        git clone --depth=1 https://github.com/adi1090x/polybar-themes.git
        cd $HOME/polybar-themes
        chmod +x setup.sh

        # Copy i3 pre-config to .config/i3/ directory
        cp i3/config $HOME/.config/i3/

        # Copy nit


        # Append config to polybar config
        
}

main() {
        clear
        cat <<- EOF
                [*] Installing i3 desktop, kali apps and configuring...

                [1] Kali specific apps (Rustscan, Nuclie)
                [2] i3 desktop packages and configs
        
            EOF

            read -p "[?] SELECT OPTION : "

            if [[ $REPLY == "1" ]]; then
                        install_kali_apps
	        elif [[ $REPLY == "2" ]]; then
                        install_i3_desktop
	        else
		        echo -e "\n[!] Invalid Option, Exiting...\n"
		        exit 1
	        fi
}

main

