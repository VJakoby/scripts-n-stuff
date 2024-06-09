#!/bin/bash
## Application installation script


# Global strings
DIR=


# Install apps
install_kali_apps() {
        echo -e "\[*] Installing Kali Specific Apps..."
        # Rustscan
        #
}      

install_all_apps() {
            # Everything
            sudo apt install i3 polybar nitrogen rofi
            $ git clone --depth=1 https://github.com/adi1090x/polybar-themes.git
            cd polybar-themes
            chmod +x setup.sh

}

main() {
        clear
        cat <<- EOF
                [*] Installing Kali Specific Apps
                
                [1] Only Kali specific apps
                [2] Everything (including i3)

            EOF

            read -p "[?] Select Option : "

            if [[ $REPLY == "1" ]]; then
		            STYLE='simple'
		            install_fonts
		            install_themes
	        elif [[ $REPLY == "2" ]]; then
		            STYLE='bitmap'
		            install_fonts
		            install_themes
	        else
		            echo -e "\n[!] Invalid Option, Exiting...\n"
		            exit 1
	        fi
}

main

