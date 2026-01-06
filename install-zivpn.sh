cat > /usr/local/bin/install-zivpn.sh << 'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}"
echo "╔══════════════════════════════╗"
echo "║        ZIVPN INSTALLER       ║"
echo "║     PONDOK VPN - udp-ziv     ║"
echo "╚══════════════════════════════╝${NC}"
echo ""

[ "$EUID" -ne 0 ] && echo -e "${RED}Run: sudo bash $0${NC}" && exit 1

echo -e "${YELLOW}[1] Checking system...${NC}"
apt update -y > /dev/null 2>&1
apt install -y git golang jq curl > /dev/null 2>&1

echo -e "${YELLOW}[2] Building from source...${NC}"
cd /tmp
git clone https://github.com/lord-alfredo/udp-custom.git > /dev/null 2>&1
cd udp-custom
go build -o zivpn
cp zivpn /usr/local/bin/
chmod +x /usr/local/bin/zivpn

echo -e "${YELLOW}[3] Setting up config...${NC}"
mkdir -p /etc/zivpn
cat > /etc/zivpn/config.json << 'CFG'
{
  "listen": ":443",
  "auth": {
    "mode": "passwords",
    "config": []
  },
  "encryption": "chacha20-ietf-poly1305"
}
CFG

touch /etc/zivpn/users.db

echo -e "${YELLOW}[4] Creating service...${NC}"
cat > /etc/systemd/system/zivpn.service << 'SVC'
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/zivpn -config /etc/zivpn/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable zivpn
systemctl start zivpn

sleep 2

echo -e "${YELLOW}[5] Setting up firewall...${NC}"
iptables -A INPUT -p udp --dport 443 -j ACCEPT 2>/dev/null
iptables -A INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null

echo ""
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo -e "${CYAN}Service:${NC} zivpn"
echo -e "${CYAN}Port:${NC} 443 UDP"
echo -e "${CYAN}Manager:${NC} menu → option 10"
echo ""
echo -e "${YELLOW}Support: @bendakerep${NC}"
EOF

chmod +x /usr/local/bin/install-zivpn.sh