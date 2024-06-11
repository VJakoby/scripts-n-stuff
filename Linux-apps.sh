#!/bin/bash

# Install apps
install_kali_apps() {
    printf "[*] Installing Kali specific apps only..."

    # RustScan
    printf "[*] Downloading and installing RustScan..."

    wget https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb
    sudo dpkg -i rustscan_*
    sudo apt-get install -f

    printf "[*] Installing git-dumper..."
    pip install git-dumper

    printf "[*] Installing rEngine..."
    git clone https://github.com/yogeshojha/rengine $HOME/rengine
    cd rengine || exit

    printf "[*] Don't forget to edit the file /rengine/.env .."
}

install_i3_desktop() {

    printf "[*] Installing i3, polybar, nitrogen, rofi..."
    sudo apt install -y i3 polybar nitrogen rofi

    printf "[*] Downloading Polybar themes..."
    git clone --depth=1 https://github.com/adi1090x/polybar-themes.git $HOME/polybar-themes
    cd $HOME/polybar-themes || exit
    chmod +x setup.sh
    
    printf "[*] Copying i3 configs..."
    mkdir -p $HOME/.config/i3
    cp i3/config $HOME/.config/i3/
}

main() {
    clear
    cat <<EOF
[*] Choose your option to install...


[1] Kali specific apps 
[2] i3 desktop packages and pre-defined configs
[3] Both
EOF

    read -p "[?] Select option : " option

    if [[ $option == "1" ]]; then
        install_kali_apps
    elif [[ $option == "2" ]]; then
        install_i3_desktop
    elif [[ $option == "3" ]]; then
        install_kali_apps
        install_i3_desktop
    else
        printf -e "\n[!] Invalid Option, Exiting...\n"
        exit 1
    fi
}

main
