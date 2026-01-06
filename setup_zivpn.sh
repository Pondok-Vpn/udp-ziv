#!/bin/bash
# Auto Install ZIVPN with Dependencies

echo "Installing dependencies..."
apt update && apt install -y figlet lolcat jq curl wget zip unzip openssl

echo "Downloading main installer..."
wget -O zivpn_install.sh https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/user_zivpn.sh
chmod +x zivpn_install.sh
./zivpn_install.sh
