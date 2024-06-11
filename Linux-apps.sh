#!/bin/bash

# Install apps
install_kali_apps() {
    printf "[*] Installing Kali specific apps only...\n"

    # RustScan
    printf "[*] Downloading and installing RustScan...\n"

    wget https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb
    sudo dpkg -i rustscan_* || exit
    sudo apt-get install -f || exit

    printf "[*] Installing git-dumper...\n"
    pip install git-dumper || exit

    printf "[*] Installing rEngine..."
    git clone https://github.com/yogeshojha/rengine $HOME/rengine || exit
    cd rengine || exit

    printf "[*] Don't forget to edit the file /rengine/.env ...\n"
}

install_i3_desktop() {

    printf "[*] Installing i3, polybar, nitrogen, rofi...\n"
    sudo apt install -y i3 polybar nitrogen rofi || exit

    printf "[*] Downloading Polybar themes...\n"
    git clone --depth=1 https://github.com/adi1090x/polybar-themes.git $HOME/polybar-themes || exit
    cd $HOME/polybar-themes || exit
    chmod +x setup.sh || exit
    
    printf "[*] Copying i3 configs...\n"
    mkdir -p $HOME/.config/i3 || exit
    cp i3/config $HOME/.config/i3/ || exit
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
