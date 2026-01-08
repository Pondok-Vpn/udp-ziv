#!/bin/bash
# setup_zivpn.sh - Instalasi ZiVPN

echo "=== ZIVPN UDP SIMPLE INSTALL ==="

# Cek root
if [ "$EUID" -ne 0 ]; then 
    echo "Harus run sebagai root!"
    echo "Gunakan: sudo bash setup_zivpn.sh"
    exit 1
fi

# Stop lama
pkill zivpn 2>/dev/null
systemctl stop zivpn 2>/dev/null

# Install dependencies
apt update
apt install -y wget openssl jq curl

# Download binary
echo "Downloading ZIVPN binary..."
wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn

# Buat folder
mkdir -p /etc/zivpn

# Buat password file default jika tidak ada
if [ ! -f /etc/zivpn/users.db ]; then
    echo "pondok123:9999999999" > /etc/zivpn/users.db
fi

# Buat cert jika belum ada
if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
    echo "Creating SSL certificate..."
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=ID/CN=zivpn" \
        -keyout "/etc/zivpn/zivpn.key" \
        -out "/etc/zivpn/zivpn.crt" 2>/dev/null
fi

# Buat config.json default
if [ ! -f /etc/zivpn/config.json ]; then
    cat > /etc/zivpn/config.json << EOF
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["pondok123"]
  }
}
EOF
fi

# Buat service systemd
echo "Creating systemd service..."
cat > /etc/systemd/system/zivpn.service << EOF
[Unit]
Description=ZiVPN UDP Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

# Download menu manager
echo "Downloading menu manager..."
wget -q https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/user_zivpn.sh -O /usr/local/bin/zivpn-menu
chmod +x /usr/local/bin/zivpn-menu

# Start service
systemctl daemon-reload
systemctl enable zivpn
systemctl start zivpn

# Buat alias
if ! grep -q "alias menu=" ~/.bashrc; then
    echo "alias menu='zivpn-menu'" >> ~/.bashrc
fi
source ~/.bashrc 2>/dev/null

echo ""
echo "=== INSTALASI SELESAI ==="
echo "Port: 5667 UDP"
echo "Password default: pondok123"
echo "Gunakan 'menu' untuk membuka manager"
echo ""
echo "=== Cek Status Service ==="
systemctl status zivpn --no-pager

# Tunggu 3 detik lalu jalankan menu
sleep 3
/usr/local/bin/zivpn-menu
