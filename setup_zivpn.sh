#!/bin/bash
echo "=== ZIVPN UDP SIMPLE INSTALL ==="
# Install
apt update
apt install -y wget openssl

# Download
wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn

# Buat folder
mkdir -p /etc/zivpn

# Buat password file
echo "pondok123" > /etc/zivpn/passwords
echo "test456" >> /etc/zivpn/passwords

# Buat cert
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
  -subj "/C=ID/CN=zivpn" \
  -keyout "/etc/zivpn/key.pem" \
  -out "/etc/zivpn/cert.pem"

# Jalankan server
/usr/local/bin/zivpn server -listen ":5667" \
  -cert "/etc/zivpn/cert.pem" \
  -key "/etc/zivpn/key.pem" \
  -passwords "/etc/zivpn/passwords" &

echo ""
echo "=== SELESAI ==="
echo "Port: 5667 UDP"
echo "Password: pondok123, test456"
echo ""
echo "TAMBAH PASSWORD:"
echo "echo 'password_baru' >> /etc/zivpn/passwords"
echo "pkill zivpn"
echo "/usr/local/bin/zivpn server -listen ':5667' -cert '/etc/zivpn/cert.pem' -key '/etc/zivpn/key.pem' -passwords '/etc/zivpn/passwords' &"
