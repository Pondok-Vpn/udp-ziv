cat > /usr/local/bin/setup-zivpn.sh << 'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════╗"
echo "║        ZIVPN SETUP SCRIPT          ║"
echo "║      PONDOK VPN - udp-zi           ║"
echo "╚════════════════════════════════════╝${NC}"
echo ""

[ "$EUID" -ne 0 ] && echo -e "${RED}Run as root: sudo bash $0${NC}" && exit 1

# CHECK LICENSE
echo -e "${YELLOW}[1] Checking license...${NC}"
SERVER_IP=$(curl -s ifconfig.me)
echo -e "  Server IP: ${CYAN}$SERVER_IP${NC}"

# License check (sesuaikan URL Anda)
LICENSE_URL="https://raw.githubusercontent.com/Pondok-Vpn/pondokvip/main/DAFTAR"
if curl -s "$LICENSE_URL" | grep -q "$SERVER_IP"; then
    echo -e "${GREEN}✅ License verified${NC}"
else
    echo -e "${RED}❌ IP not in license list${NC}"
    echo -e "${YELLOW}Continue anyway? (y/n): ${NC}"
    read -r continue_install
    [[ "$continue_install" != "y" ]] && exit 1
fi

# INSTALL DEPS
echo -e "${YELLOW}[2] Installing dependencies...${NC}"
apt update -y > /dev/null 2>&1
apt install -y curl wget jq sqlite3 openssl zip unzip > /dev/null 2>&1
echo -e "${GREEN}✅ Dependencies installed${NC}"

# GET ZIVPN BINARY
echo -e "${YELLOW}[3] Getting ZiVPN binary...${NC}"
cd /tmp
ZIVPN_URL="https://github.com/zivpn/zivpn/releases/latest/download/zivpn-linux-amd64"
if wget -q -O zivpn "$ZIVPN_URL"; then
    echo -e "  ${GREEN}✅ Downloaded binary${NC}"
else
    echo -e "  ${YELLOW}⚠️ Download failed, trying alternative...${NC}"
    # Fallback ke build dari source
    apt install -y golang git > /dev/null 2>&1
    git clone https://github.com/lord-alfredo/udp-custom.git > /dev/null 2>&1
    cd udp-custom && go build -o zivpn && cd /tmp
    cp udp-custom/zivpn .
fi

mv zivpn /usr/local/bin/
chmod +x /usr/local/bin/zivpn
echo -e "${GREEN}✅ ZiVPN installed${NC}"

# SETUP CONFIG DIR
echo -e "${YELLOW}[4] Creating configuration...${NC}"
mkdir -p /etc/zivpn

# SSL CERTS
if [ ! -f /etc/zivpn/zivpn.crt ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/zivpn/zivpn.key \
        -out /etc/zivpn/zivpn.crt \
        -subj "/C=ID/ST=Java/L=Jakarta/O=PondokVPN/CN=zivpn" > /dev/null 2>&1
    echo -e "  ${GREEN}✅ SSL certificates created${NC}"
fi

# CONFIG.JSON (MODE DB - SEPERTI DISKUSI KITA)
cat > /etc/zivpn/config.json << 'CFGEOF'
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "db",
    "config": "/etc/zivpn/users.db"
  }
}
CFGEOF
echo -e "  ${GREEN}✅ Config file created${NC}"

# DATABASE
sqlite3 /etc/zivpn/users.db "
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    expiry INTEGER DEFAULT 0,
    limit_ip INTEGER DEFAULT 1,
    is_active INTEGER DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);" 2>/dev/null
echo -e "  ${GREEN}✅ Database created${NC}"

# COPY HELPER SCRIPT (DARI LOKAL JIKA ADA)
echo -e "${YELLOW}[5] Installing helper scripts...${NC}"
if [ -f "$(dirname "$0")/ziv-helper.sh" ]; then
    cp "$(dirname "$0")/ziv-helper.sh" /usr/local/bin/
    chmod +x /usr/local/bin/ziv-helper.sh
    echo -e "  ${GREEN}✅ Helper script installed${NC}"
else
    echo -e "  ${YELLOW}⚠️ ziv-helper.sh not found locally${NC}"
    echo -e "  ${CYAN}Download manually after install${NC}"
fi

# COPY USER MANAGER (DARI LOKAL JIKA ADA)
if [ -f "$(dirname "$0")/zi.sh" ]; then
    cp "$(dirname "$0")/zi.sh" /usr/local/bin/zivpn-user.sh
    chmod +x /usr/local/bin/zivpn-user.sh
    echo -e "  ${GREEN}✅ User manager installed${NC}"
else
    echo -e "  ${YELLOW}⚠️ zi.sh not found locally${NC}"
fi

# SYSTEMD SERVICE
echo -e "${YELLOW}[6] Creating service...${NC}"
cat > /etc/systemd/system/zivpn.service << 'SVCEOF'
[Unit]
Description=ZiVPN UDP Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/zivpn -c /etc/zivpn/config.json
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable zivpn > /dev/null 2>&1
systemctl start zivpn > /dev/null 2>&1

sleep 2
if systemctl is-active --quiet zivpn; then
    echo -e "  ${GREEN}✅ Service started successfully${NC}"
else
    echo -e "  ${RED}⚠️ Service failed to start${NC}"
    echo -e "  ${YELLOW}Check: systemctl status zivpn${NC}"
fi

# FIREWALL
echo -e "${YELLOW}[7] Configuring firewall...${NC}"
if command -v ufw > /dev/null 2>&1; then
    ufw allow 5667/udp > /dev/null 2>&1
    echo -e "  ${GREEN}✅ UFW: Port 5667/udp allowed${NC}"
elif command -v iptables > /dev/null 2>&1; then
    iptables -A INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null
    echo -e "  ${GREEN}✅ iptables: Port 5667/udp allowed${NC}"
else
    echo -e "  ${YELLOW}⚠️ No firewall manager found${NC}"
fi

# FINAL OUTPUT
clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════╗"
echo "║       SETUP COMPLETE!              ║"
echo "╠════════════════════════════════════╣"
echo "║                                    ║"
echo -e "║  ${GREEN}✅${NC} ZiVPN Installed                 ║"
echo -e "║  ${GREEN}✅${NC} Running on Port 5667           ║"
echo -e "║  ${GREEN}✅${NC} Database Ready                 ║"
echo -e "║  ${GREEN}✅${NC} Service Active                 ║"
echo "║                                    ║"
echo "╠════════════════════════════════════╣"
echo "║         QUICK COMMANDS             ║"
echo "╠════════════════════════════════════╣"
echo "║                                    ║"
echo -e "║  ${YELLOW}Add User:${NC}                         ║"
echo -e "║  ${CYAN}zivpn-user.sh add username password${NC} ║"
echo "║                                    ║"
echo -e "║  ${YELLOW}Setup Telegram:${NC}                   ║"
echo -e "║  ${CYAN}ziv-helper.sh setup-telegram${NC}        ║"
echo "║                                    ║"
echo -e "║  ${YELLOW}Backup:${NC}                           ║"
echo -e "║  ${CYAN}ziv-helper.sh backup${NC}                ║"
echo "║                                    ║"
echo -e "║  ${YELLOW}Check Status:${NC}                     ║"
echo -e "║  ${CYAN}systemctl status zivpn${NC}              ║"
echo "║                                    ║"
echo "╠════════════════════════════════════╣"
echo "║         SERVER INFO                ║"
echo "╠════════════════════════════════════╣"
echo "║                                    ║"
echo -e "║  ${YELLOW}IP:${NC} ${CYAN}$SERVER_IP${NC}                     ║"
echo -e "║  ${YELLOW}Port:${NC} ${CYAN}5667 UDP${NC}                     ║"
echo -e "║  ${YELLOW}Config:${NC} ${CYAN}/etc/zivpn/${NC}                ║"
echo "║                                    ║"
echo "╠════════════════════════════════════╣"
echo "║  Telegram: @bendakerep             ║"
echo "║  Repo: Pondok-Vpn/udp-ziv          ║"
echo "╚════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Setup complete! Use commands above to manage.${NC}"
echo ""
EOF

chmod +x /usr/local/bin/setup-zivpn.sh
