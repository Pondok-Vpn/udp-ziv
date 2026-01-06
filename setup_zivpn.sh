#!/bin/bash
# ============================================
# ZIVPN AUTO INSTALLER - PONDOK VPN
# Telegram: @bendakerep
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════╗"
echo "║        ZIVPN AUTO INSTALLER        ║"
echo "║        PONDOK VPN - udp-zi         ║"
echo "╚════════════════════════════════════╝${NC}"
echo ""

# Check root
[ "$EUID" -ne 0 ] && echo -e "${RED}Run as root: sudo bash $0${NC}" && exit 1

# Get server IP
SERVER_IP=$(curl -s ifconfig.me)
echo -e "${YELLOW}Server IP:${NC} ${CYAN}$SERVER_IP${NC}"
echo ""

# ============================================
# 1. INSTALL DEPENDENCIES
# ============================================
echo -e "${YELLOW}[1] Installing dependencies...${NC}"
apt update -y > /dev/null 2>&1
apt install -y curl wget jq sqlite3 openssl > /dev/null 2>&1
echo -e "${GREEN}✅ Dependencies installed${NC}"

# ============================================
# 2. DOWNLOAD ZIVPN BINARY
# ============================================
echo -e "${YELLOW}[2] Downloading ZiVPN...${NC}"
cd /tmp
ZIVPN_URL="https://github.com/zivpn/zivpn/releases/latest/download/zivpn-linux-amd64"
if wget -q -O zivpn "$ZIVPN_URL"; then
    echo -e "  ${GREEN}✅ ZiVPN downloaded${NC}"
else
    echo -e "  ${YELLOW}⚠️ Download failed, trying source...${NC}"
    apt install -y golang git > /dev/null 2>&1
    git clone https://github.com/lord-alfredo/udp-custom.git > /dev/null 2>&1
    cd udp-custom
    go build -o zivpn
    cd /tmp
    cp udp-custom/zivpn .
fi

mv zivpn /usr/local/bin/
chmod +x /usr/local/bin/zivpn
echo -e "${GREEN}✅ ZiVPN installed${NC}"

# ============================================
# 3. CREATE CONFIGURATION
# ============================================
echo -e "${YELLOW}[3] Creating configuration...${NC}"
mkdir -p /etc/zivpn

# SSL certificates
if [ ! -f /etc/zivpn/zivpn.crt ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/zivpn/zivpn.key \
        -out /etc/zivpn/zivpn.crt \
        -subj "/C=ID/ST=Java/L=Jakarta/O=PondokVPN/CN=zivpn" > /dev/null 2>&1
    echo -e "  ${GREEN}✅ SSL certificates created${NC}"
fi

# config.json
cat > /etc/zivpn/config.json << 'EOF'
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
EOF
echo -e "  ${GREEN}✅ Config file created${NC}"

# Database
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

# Add IP to local DAFTAR file
echo "$SERVER_IP" > /etc/zivpn/DAFTAR
echo -e "  ${GREEN}✅ IP added to /etc/zivpn/DAFTAR${NC}"

# ============================================
# 4. INSTALL HELPER SCRIPTS
# ============================================
echo -e "${YELLOW}[4] Installing helper scripts...${NC}"

# Copy ziv-helper.sh if exists locally
if [ -f "./ziv-helper.sh" ]; then
    cp ./ziv-helper.sh /usr/local/bin/
    chmod +x /usr/local/bin/ziv-helper.sh
    echo -e "  ${GREEN}✅ Helper script installed${NC}"
else
    echo -e "  ${YELLOW}⚠️ ziv-helper.sh not found${NC}"
fi

# Copy zi.sh if exists locally
if [ -f "./zi.sh" ]; then
    cp ./zi.sh /usr/local/bin/zivpn-user.sh
    chmod +x /usr/local/bin/zivpn-user.sh
    echo -e "  ${GREEN}✅ User manager installed${NC}"
elif [ -f "./zivpn-user.sh" ]; then
    cp ./zivpn-user.sh /usr/local/bin/
    chmod +x /usr/local/bin/zivpn-user.sh
    echo -e "  ${GREEN}✅ User manager installed${NC}"
else
    echo -e "  ${YELLOW}⚠️ User manager not found${NC}"
fi

# ============================================
# 5. CREATE SYSTEMD SERVICE
# ============================================
echo -e "${YELLOW}[5] Creating service...${NC}"
cat > /etc/systemd/system/zivpn.service << 'EOF'
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
EOF

systemctl daemon-reload
systemctl enable zivpn > /dev/null 2>&1
systemctl start zivpn > /dev/null 2>&1

sleep 2
if systemctl is-active --quiet zivpn; then
    echo -e "  ${GREEN}✅ Service started successfully${NC}"
else
    echo -e "  ${YELLOW}⚠️ Checking service status...${NC}"
    systemctl status zivpn --no-pager -l
fi

# ============================================
# 6. FIREWALL CONFIGURATION
# ============================================
echo -e "${YELLOW}[6] Configuring firewall...${NC}"
if command -v ufw > /dev/null 2>&1; then
    ufw allow 5667/udp > /dev/null 2>&1
    echo -e "  ${GREEN}✅ UFW: Port 5667/udp allowed${NC}"
elif command -v iptables > /dev/null 2>&1; then
    iptables -A INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null
    echo -e "  ${GREEN}✅ iptables: Port 5667/udp allowed${NC}"
else
    echo -e "  ${YELLOW}⚠️ No firewall manager found${NC}"
fi

# ============================================
# 7. FINAL OUTPUT
# ============================================
clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════╗"
echo "║       INSTALLATION COMPLETE!       ║"
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
echo -e "║  ${YELLOW}Add User (CLI):${NC}                    ║"
echo -e "║  ${CYAN}sqlite3 /etc/zivpn/users.db${NC}         ║"
echo -e "║  ${CYAN}\"INSERT INTO users (username, password)\"${NC} ║"
echo -e "║  ${CYAN}\"VALUES ('user1', 'pass1');\"${NC}       ║"
echo "║                                    ║"
echo -e "║  ${YELLOW}Check Status:${NC}                     ║"
echo -e "║  ${CYAN}systemctl status zivpn${NC}              ║"
echo -e "║  ${CYAN}ss -tulpn | grep 5667${NC}               ║"
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
echo "║  Support: @bendakerep              ║"
echo "║  GitHub: Pondok-Vpn/udp-ziv        ║"
echo "╚════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}ZiVPN is ready to use!${NC}"
echo ""
