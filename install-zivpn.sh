cat > /usr/local/bin/install-zivpn.sh << 'EOF'
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
echo "║        ZIVPN UDP INSTALLER         ║"
echo "║      PONDOK VPN - udp-zi           ║"
echo "╚════════════════════════════════════╝${NC}"
echo ""

[ "$EUID" -ne 0 ] && echo -e "${RED}Run as root: sudo bash $0${NC}" && exit 1

# LICENSE CHECK
echo -e "${YELLOW}[1] Checking license...${NC}"
LICENSE_URL="https://raw.githubusercontent.com/Pondok-Vpn/pondokvip/main/DAFTAR"
SERVER_IP=$(curl -s ifconfig.me)

echo -e "  IP Address: ${CYAN}$SERVER_IP${NC}"
echo -e "  License URL: ${CYAN}$LICENSE_URL${NC}"

if ! curl -s "$LICENSE_URL" | grep -q "$SERVER_IP"; then
    echo -e "${RED}╔════════════════════════════════════╗${NC}"
    echo -e "${RED}║           LICENSE NOT FOUND         ║${NC}"
    echo -e "${RED}╠════════════════════════════════════╣${NC}"
    echo -e "${RED}║                                    ║${NC}"
    echo -e "${RED}║  Server IP: $SERVER_IP             ║${NC}"
    echo -e "${RED}║                                    ║${NC}"
    echo -e "${RED}║  Please add your IP to DAFTAR file ║${NC}"
    echo -e "${RED}║  Contact: @bendakerep              ║${NC}"
    echo -e "${RED}║                                    ║${NC}"
    echo -e "${RED}╚════════════════════════════════════╝${NC}"
    exit 1
fi

echo -e "${GREEN}✅ License verified${NC}"
echo ""

# INSTALL DEPENDENCIES
echo -e "${YELLOW}[2] Installing dependencies...${NC}"
apt update -y > /dev/null 2>&1
apt install -y curl wget git golang jq sqlite3 openssl zip unzip > /dev/null 2>&1
echo -e "${GREEN}✅ Dependencies installed${NC}"

# DOWNLOAD ZIVPN BINARY (lebih reliable dari build source)
echo -e "${YELLOW}[3] Installing ZiVPN...${NC}"
cd /tmp
ZIVPN_URL="https://github.com/zivpn/zivpn/releases/latest/download/zivpn-linux-amd64"
wget -q -O zivpn "$ZIVPN_URL" 2>/dev/null || {
    echo -e "${YELLOW}  Fallback: Building from source...${NC}"
    rm -rf udp-custom 2>/dev/null
    git clone https://github.com/lord-alfredo/udp-custom.git > /dev/null 2>&1
    cd udp-custom
    go build -o zivpn
    cp zivpn /tmp/
    cd /tmp
}

mv zivpn /usr/local/bin/
chmod +x /usr/local/bin/zivpn
echo -e "${GREEN}✅ ZiVPN installed${NC}"

# CREATE CONFIG DIRECTORY
echo -e "${YELLOW}[4] Creating configuration...${NC}"
mkdir -p /etc/zivpn

# GENERATE SSL CERTIFICATES
if [ ! -f /etc/zivpn/zivpn.crt ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/zivpn/zivpn.key \
        -out /etc/zivpn/zivpn.crt \
        -subj "/C=ID/ST=Java/L=Jakarta/O=PondokVPN/CN=zivpn" > /dev/null 2>&1
    echo -e "  ${GREEN}✅ SSL certificates generated${NC}"
fi

# CREATE CONFIG.JSON (MODE DB)
cat > /etc/zivpn/config.json << 'CFG'
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
CFG
echo -e "  ${GREEN}✅ Config created${NC}"

# CREATE DATABASE
sqlite3 /etc/zivpn/users.db "
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    expiry INTEGER DEFAULT 0,
    limit_ip INTEGER DEFAULT 1,
    is_active INTEGER DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
" 2>/dev/null
echo -e "  ${GREEN}✅ Database created${NC}"

# INSTALL HELPER SCRIPT
echo -e "${YELLOW}[5] Installing helper tools...${NC}"
wget -q -O /usr/local/bin/ziv-helper.sh \
    "https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/ziv-helper.sh" 2>/dev/null || {
    echo -e "  ${YELLOW}⚠️  Using local helper script${NC}"
    # Fallback ke script lokal jika ada
    [ -f "$(dirname "$0")/ziv-helper.sh" ] && \
        cp "$(dirname "$0")/ziv-helper.sh" /usr/local/bin/
}
chmod +x /usr/local/bin/ziv-helper.sh

# INSTALL USER MANAGER
wget -q -O /usr/local/bin/zivpn-user.sh \
    "https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/zi.sh" 2>/dev/null || {
    echo -e "  ${YELLOW}⚠️  Using local user manager${NC}"
    [ -f "$(dirname "$0")/zi.sh" ] && \
        cp "$(dirname "$0")/zi.sh" /usr/local/bin/zivpn-user.sh
}
chmod +x /usr/local/bin/zivpn-user.sh
echo -e "${GREEN}✅ Helper tools installed${NC}"

# CREATE SYSTEMD SERVICE
echo -e "${YELLOW}[6] Creating service...${NC}"
cat > /etc/systemd/system/zivpn.service << 'SVC'
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
SVC

systemctl daemon-reload
systemctl enable zivpn > /dev/null 2>&1
systemctl start zivpn > /dev/null 2>&1
sleep 2

if systemctl is-active --quiet zivpn; then
    echo -e "  ${GREEN}✅ Service started${NC}"
else
    echo -e "  ${YELLOW}⚠️  Service might need manual start${NC}"
fi

# FIREWALL
echo -e "${YELLOW}[7] Configuring firewall...${NC}"
if command -v ufw > /dev/null 2>&1; then
    ufw allow 5667/udp > /dev/null 2>&1
    echo -e "  ${GREEN}✅ UFW rule added${NC}"
elif command -v iptables > /dev/null 2>&1; then
    iptables -A INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null
    echo -e "  ${GREEN}✅ iptables rule added${NC}"
fi

# FINAL OUTPUT
clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════╗"
echo "║     INSTALLATION COMPLETE          ║"
echo "╠════════════════════════════════════╣"
echo "║                                    ║"
echo -e "║  ${GREEN}✅${NC} License Verified                ║"
echo -e "║  ${GREEN}✅${NC} ZiVPN Core                      ║"
echo -e "║  ${GREEN}✅${NC} Configuration                   ║"
echo -e "║  ${GREEN}✅${NC} Database Setup                  ║"
echo -e "║  ${GREEN}✅${NC} Helper Tools                   ║"
echo -e "║  ${GREEN}✅${NC} Service Running                ║"
echo "║                                    ║"
echo "╠════════════════════════════════════╣"
echo "║         QUICK COMMANDS             ║"
echo "╠════════════════════════════════════╣"
echo "║                                    ║"
echo -e "║  ${YELLOW}Add User:${NC}                         ║"
echo -e "║    ${CYAN}zivpn-user.sh add user pass${NC}       ║"
echo "║                                    ║"
echo -e "║  ${YELLOW}Backup:${NC}                           ║"
echo -e "║    ${CYAN}ziv-helper.sh backup${NC}              ║"
echo "║                                    ║"
echo -e "║  ${YELLOW}Setup Telegram:${NC}                   ║"
echo -e "║    ${CYAN}ziv-helper.sh setup-telegram${NC}      ║"
echo "║                                    ║"
echo "╠════════════════════════════════════╣"
echo "║         SERVER INFO                ║"
echo "╠════════════════════════════════════╣"
echo "║                                    ║"
echo -e "║  ${YELLOW}IP:${NC} ${CYAN}$SERVER_IP${NC}                     ║"
echo -e "║  ${YELLOW}Port:${NC} ${CYAN}5667 UDP${NC}                     ║"
echo -e "║  ${YELLOW}Service:${NC} ${CYAN}zivpn${NC}                     ║"
echo "║                                    ║"
echo "╠════════════════════════════════════╣"
echo "║  Support: @bendakerep              ║"
echo "║  GitHub: Pondok-Vpn/udp-ziv        ║"
echo "╚════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}ZiVPN is ready to use!${NC}"
echo ""
EOF

chmod +x /usr/local/bin/install-zivpn.sh
