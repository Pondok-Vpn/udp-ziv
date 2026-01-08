#!/bin/bash
# zi.sh - Instalasi ZiVPN dengan port forwarding

echo -e "Updating server"
apt-get update && apt-get upgrade -y

# Stop service lama
systemctl stop zivpn.service 2>/dev/null
pkill zivpn 2>/dev/null

# Install dependencies
apt-get install -y wget openssl curl jq

# Download binary
echo -e "Downloading UDP Service"
wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn

# Buat direktori
mkdir -p /etc/zivpn

# Download config.json
if [ ! -f /etc/zivpn/config.json ]; then
    wget -q https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json -O /etc/zivpn/config.json || {
        # Buat default jika gagal download
        cat > /etc/zivpn/config.json << EOF
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["zi"]
  }
}
EOF
    }
fi

# Generate cert jika belum ada
if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
    echo "Generating cert files:"
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=ID/CN=zivpn" \
        -keyout "/etc/zivpn/zivpn.key" \
        -out "/etc/zivpn/zivpn.crt"
fi

# Optimasi UDP
sysctl -w net.core.rmem_max=16777216 2>/dev/null
sysctl -w net.core.wmem_max=16777216 2>/dev/null

# Buat service
cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Input password
echo -e "ZIVPN UDP Passwords"
read -p "Enter passwords (use comma for multiple, ENTER for default 'zi'): " input_config

if [ -n "$input_config" ]; then
    # Convert to array
    IFS=',' read -r -a config_array <<< "$input_config"
    config_list=""
    for pass in "${config_array[@]}"; do
        config_list="${config_list}\"${pass}\","
    done
    config_list="${config_list%,}"
    
    # Update config.json
    jq --argjson config "[$config_list]" '.auth.config = $config' /etc/zivpn/config.json > /tmp/config.json.tmp
    mv /tmp/config.json.tmp /etc/zivpn/config.json
else
    # Default password
    jq '.auth.config = ["zi"]' /etc/zivpn/config.json > /tmp/config.json.tmp
    mv /tmp/config.json.tmp /etc/zivpn/config.json
fi

# Enable service
systemctl daemon-reload
systemctl enable zivpn.service
systemctl start zivpn.service

# Setup firewall rules jika interface ditemukan
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -n "$INTERFACE" ]; then
    # Allow ports
    iptables -A INPUT -p udp --dport 5667 -j ACCEPT
    iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT
    
    # Port forwarding yang FIXED
    iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport 6000:19999 -j DNAT --to-destination :5667
    
    echo "Port forwarding 6000-19999 -> 5667 diatur di interface $INTERFACE"
fi

# Setup UFW jika aktif
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
    ufw allow 5667/udp
    ufw allow 6000:19999/udp
    echo "Port diizinkan di UFW"
fi

# Cleanup
rm -f zi.sh 2>/dev/null

echo -e "\n=== ZIVPN UDP Installed ==="
echo "Main Port: 5667 UDP"
echo "Port Range: 6000-19999 UDP"
echo "Interface: ${INTERFACE:-Not found}"
echo "Service: systemctl status zivpn"
echo ""
echo "Gunakan 'menu' untuk user management"
