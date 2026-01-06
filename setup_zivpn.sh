#!/bin/bash
echo "=== ZIVPN UDP SIMPLE INSTALL ==="

# Stop lama
pkill zivpn 2>/dev/null

# Install
apt update
apt install -y wget openssl jq curl figlet lolcat

# Download binary
wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn

# Buat folder
mkdir -p /etc/zivpn

# Buat password file (SIMPEL!)
echo "pondok123:9999999999" > /etc/zivpn/users.db

# Buat cert
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
  -subj "/C=ID/CN=zivpn" \
  -keyout "/etc/zivpn/zivpn.key" \
  -out "/etc/zivpn/zivpn.crt"

# Jalankan server
/usr/local/bin/zivpn server -listen ":5667" \
  -cert "/etc/zivpn/zivpn.crt" \
  -key "/etc/zivpn/zivpn.key" \
  -db "/etc/zivpn/users.db" &

echo ""
echo "=== DOWNLOAD MENU MANAGER ==="

# Download user_zivpn.sh dari repo
wget -q https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/user_zivpn.sh -O /usr/local/bin/zivpn-menu
chmod +x /usr/local/bin/zivpn-menu

# Buat alias
echo "alias menu='zivpn-menu'" >> ~/.bashrc
source ~/.bashrc

echo ""
echo "=== INSTALASI SELESAI ==="
echo "Port: 5667 UDP"
echo "Password default: pondok123"
echo ""
echo "=== LANGSUNG KE MENU ==="
sleep 3

# Langsung jalankan menu user_zivpn.sh
/usr/local/bin/zivpn-menu
