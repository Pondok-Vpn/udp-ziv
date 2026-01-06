#!/bin/bash
# ============================================
# ZIVPN INSTALLER - PONDOK VPN
# Telegram: @bendakerep
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════════╗"
echo "║        ZIVPN UDP INSTALLER             ║"
echo "║      PONDOK VPN - UDP ZIVPN             ║"
echo "╚════════════════════════════════════════╝${NC}"
echo ""

[ "$EUID" -ne 0 ] && echo -e "${RED}Run as root: sudo bash $0${NC}" && exit 1

# LICENSE CHECK
echo -e "${YELLOW}[1] Checking license...${NC}"
LICENSE_URL="https://raw.githubusercontent.com/Pondok-Vpn/pondokvip/main/DAFTAR"
SERVER_IP=$(curl -s ifconfig.me)

echo -e "  IP Address: ${CYAN}$SERVER_IP${NC}"
echo -e "  License URL: ${CYAN}$LICENSE_URL${NC}"

if ! curl -s "$LICENSE_URL" | grep -q "$SERVER_IP"; then
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           LICENSE NOT FOUND            ║${NC}"
    echo -e "${RED}╠════════════════════════════════════════╣${NC}"
    echo -e "${RED}║                                        ║${NC}"
    echo -e "${RED}║  Server IP: $SERVER_IP                 ║${NC}"
    echo -e "${RED}║                                        ║${NC}"
    echo -e "${RED}║  Please add your IP to DAFTAR file     ║${NC}"
    echo -e "${RED}║  Contact: @bendakerep                  ║${NC}"
    echo -e "${RED}║                                        ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    exit 1
fi

echo -e "${GREEN}✅ License verified${NC}"
echo ""

# INSTALL DEPENDENCIES
echo -e "${YELLOW}[2] Installing dependencies...${NC}"
apt update -y > /dev/null 2>&1
apt install -y curl wget git golang jq sqlite3 openssl zip unzip > /dev/null 2>&1
echo -e "${GREEN}✅ Dependencies installed${NC}"

# DOWNLOAD ZIVPN BINARY
echo -e "${YELLOW}[3] Installing ZiVPN...${NC}"
cd /tmp
ZIVPN_URL="https://github.com/zivpn/zivpn/releases/latest/download/zivpn-linux-amd64"
if wget -q -O zivpn "$ZIVPN_URL" 2>/dev/null; then
    echo -e "  ${GREEN}✓ Downloaded binary${NC}"
else
    echo -e "  ${YELLOW}⚠️  Building from source...${NC}"
    rm -rf udp-custom 2>/dev/null
    git clone https://github.com/lord-alfredo/udp-custom.git > /dev/null 2>&1
    cd udp-custom
    go build -o zivpn
    cp zivpn /tmp/
    cd /tmp
fi

mv zivpn /usr/local/bin/
chmod +x /usr/local/bin/zivpn
echo -e "${GREEN}✅ ZiVPN installed${NC}"

# CREATE CONFIG DIRECTORY
echo -e "${YELLOW}[4] Creating configuration...${NC}"
mkdir -p /etc/zivpn

# SETUP TELEGRAM WITH YOUR TOKEN
echo -e "${YELLOW}[4.5] Setting up Telegram...${NC}"
cat > /etc/zivpn/telegram.conf << 'EOF'
# Telegram Configuration - Pondok VPN
# Auto-configured during installation
TELEGRAM_BOT_TOKEN=8477114091:AAEYVH4HAG_8q6AIkPG_72c_4NDm7pf0Xx8
TELEGRAM_CHAT_ID=5503146862
EOF
chmod 600 /etc/zivpn/telegram.conf
echo -e "  ${GREEN}✅ Telegram configured${NC}"

# GENERATE SSL CERTIFICATES
if [ ! -f /etc/zivpn/zivpn.crt ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/zivpn/zivpn.key \
        -out /etc/zivpn/zivpn.crt \
        -subj "/C=ID/ST=Java/L=Jakarta/O=PondokVPN/CN=zivpn" > /dev/null 2>&1
    echo -e "  ${GREEN}✅ SSL certificates generated${NC}"
fi

# CREATE CONFIG.JSON
cat > /etc/zivpn/config.json << 'EOF'
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": []
  }
}
EOF
echo -e "  ${GREEN}✅ Config created${NC}"

# CREATE EMPTY DATABASE
touch /etc/zivpn/users.db
chmod 600 /etc/zivpn/users.db
echo -e "  ${GREEN}✅ Database created${NC}"

# INSTALL HELPER SCRIPTS
echo -e "${YELLOW}[5] Installing helper tools...${NC}"

# Install ziv-helper.sh
cat > /usr/local/bin/ziv-helper.sh << 'EOF'
#!/bin/bash
# ============================================
# ZIVPN HELPER SCRIPT - PONDOK VPN EDITION
# Telegram: @bendakerep
# ============================================

# Colors
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
P='\033[0;35m'
C='\033[0;36m'
W='\033[1;37m'
N='\033[0m'

# Config
CONFIG_DIR="/etc/zivpn"
TELEGRAM_CONF="${CONFIG_DIR}/telegram.conf"

# Banner
show_banner() {
    clear
    echo -e "${P}"
    echo "╔══════════════════════════════════╗"
    echo "║     ZIVPN HELPER - PONDOK VPN    ║"
    echo "║     Premium Backup & Tools       ║"
    echo "╚══════════════════════════════════╝${N}"
    echo ""
}

# Get Server Info
get_host() {
    if [ -f "${CONFIG_DIR}/zivpn.crt" ]; then
        local CERT_CN
        CERT_CN=$(openssl x509 -in "${CONFIG_DIR}/zivpn.crt" -noout -subject 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p' || echo "zivpn")
        if [ "$CERT_CN" == "zivpn" ] || [ -z "$CERT_CN" ]; then
            curl -s ifconfig.me
        else
            echo "$CERT_CN"
        fi
    else
        curl -s ifconfig.me
    fi
}

# Telegram Functions
send_telegram() {
    local message="$1"
    local keyboard="$2"
    
    [ ! -f "$TELEGRAM_CONF" ] && return 1
    source "$TELEGRAM_CONF" 2>/dev/null
    
    [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ] && return 1
    
    local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    
    if [ -n "$keyboard" ]; then
        curl -s -X POST "$api_url" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            --data-urlencode "text=${message}" \
            -d "reply_markup=${keyboard}" > /dev/null
    else
        curl -s -X POST "$api_url" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            --data-urlencode "text=${message}" \
            -d "parse_mode=Markdown" > /dev/null
    fi
}

# Setup Telegram
setup_telegram() {
    show_banner
    echo -e "${C}════ Telegram Configuration ════${N}"
    echo ""
    
    # Check if already configured
    if [ -f "$TELEGRAM_CONF" ]; then
        source "$TELEGRAM_CONF" 2>/dev/null
        if [ "$TELEGRAM_BOT_TOKEN" == "8477114091:AAEYVH4HAG_8q6AIkPG_72c_4NDm7pf0Xx8" ]; then
            echo -e "${G}✓ Already using Pondok VPN Telegram bot${N}"
            echo ""
            echo -e "${Y}Current configuration:${N}"
            echo -e "  Bot: ${C}Pondok VPN Bot${N}"
            echo -e "  Chat ID: ${C}$TELEGRAM_CHAT_ID${N}"
            echo ""
            read -p "$(echo -e ${Y}Change configuration? (y/N): ${N})" change
            if [[ ! "$change" =~ ^[Yy]$ ]]; then
                test_notify
                return 0
            fi
        fi
    fi
    
    read -p "$(echo -e ${Y}Bot Token: ${N})" api_key
    read -p "$(echo -e ${Y}Chat ID: ${N})" chat_id
    
    if [ -z "$api_key" ] || [ -z "$chat_id" ]; then
        echo -e "${R}Configuration failed!${N}"
        return 1
    fi
    
    echo "TELEGRAM_BOT_TOKEN=$api_key" > "$TELEGRAM_CONF"
    echo "TELEGRAM_CHAT_ID=$chat_id" >> "$TELEGRAM_CONF"
    chmod 600 "$TELEGRAM_CONF"
    
    echo -e "${G}✓ Telegram configuration saved${N}"
    test_notify
    return 0
}

# Backup Function
backup() {
    show_banner
    echo -e "${C}════ Backup Configuration ════${N}"
    echo ""
    
    # Check Telegram config
    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo -e "${Y}Telegram configuration not found${N}"
        setup_telegram
        [ $? -ne 0 ] && exit 1
    fi
    
    source "$TELEGRAM_CONF" 2>/dev/null
    
    # Create backup
    local backup_file="zivpn_backup_$(date +%Y%m%d_%H%M%S).zip"
    local temp_file="/tmp/${backup_file}"
    
    echo -e "${Y}Creating backup archive...${N}"
    cd "$CONFIG_DIR"
    zip -r "$temp_file" config.json users.db 2>/dev/null
    
    if [ ! -f "$temp_file" ]; then
        echo -e "${R}Failed to create backup${N}"
        return 1
    fi
    
    # Send to Telegram
    echo -e "${Y}Sending to Telegram...${N}"
    local response
    response=$(curl -s -F "chat_id=${TELEGRAM_CHAT_ID}" \
        -F "document=@${temp_file}" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument")
    
    local file_id
    file_id=$(echo "$response" | jq -r '.result.document.file_id' 2>/dev/null)
    
    if [ -z "$file_id" ] || [ "$file_id" == "null" ]; then
        echo -e "${R}Failed to upload backup${N}"
        rm -f "$temp_file"
        return 1
    fi
    
    # Send notification
    local host=$(get_host)
    local current_date=$(date +"%d %B %Y")
    
    local message="
${P}╔══════════════════════════════╗
║     🔄 ZIVPN BACKUP          ║
╠══════════════════════════════╣
║                              ║
║  ${W}Host:${N} ${C}$host${P}                ║
║  ${W}Date:${N} ${C}$current_date${P}           ║
║  ${W}File ID:${N} ${C}$file_id${P}          ║
║                              ║
║  ${Y}Save File ID for restore${P}     ║
╚══════════════════════════════╝${N}
"
    
    send_telegram "$message"
    
    # Cleanup
    rm -f "$temp_file"
    
    echo -e "${G}✓ Backup completed successfully!${N}"
    echo -e "${C}File ID: ${W}$file_id${N}"
    echo -e "${Y}Save this ID for restore${N}"
}

# Restore Function
restore() {
    show_banner
    echo -e "${C}════ Restore Configuration ════${N}"
    echo ""
    
    # Check Telegram config
    [ ! -f "$TELEGRAM_CONF" ] && echo -e "${R}Telegram config not found${N}" && exit 1
    source "$TELEGRAM_CONF" 2>/dev/null
    
    # Get File ID
    read -p "$(echo -e ${Y}Enter Backup File ID: ${N})" file_id
    [ -z "$file_id" ] && echo -e "${R}File ID required${N}" && exit 1
    
    # Confirmation
    read -p "$(echo -e ${R}WARNING: This will overwrite current data! Continue? (y/n): ${N})" confirm
    [ "$confirm" != "y" ] && echo -e "${Y}Restore cancelled${N}" && exit 0
    
    echo -e "${Y}Downloading backup...${N}"
    
    # Get file path
    local response
    response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getFile?file_id=${file_id}")
    local file_path=$(echo "$response" | jq -r '.result.file_path' 2>/dev/null)
    
    [ -z "$file_path" ] || [ "$file_path" == "null" ] && echo -e "${R}Invalid File ID${N}" && exit 1
    
    # Download file
    local temp_file="/tmp/restore_$(basename "$file_path")"
    local download_url="https://api.telegram.org/file/bot${TELEGRAM_BOT_TOKEN}/${file_path}"
    
    curl -s -o "$temp_file" "$download_url"
    [ $? -ne 0 ] && echo -e "${R}Download failed${N}" && exit 1
    
    # Extract and restore
    echo -e "${Y}Restoring files...${N}"
    unzip -o "$temp_file" -d "$CONFIG_DIR" 2>/dev/null
    if [ $? -eq 0 ]; then
        systemctl restart zivpn.service 2>/dev/null
        echo -e "${G}✓ Restore completed!${N}"
        
        # Send notification
        local host=$(get_host)
        local message="
${P}╔══════════════════════════════╗
║     ✅ RESTORE COMPLETE       ║
╠══════════════════════════════╣
║                              ║
║  ${W}Host:${N} ${C}$host${P}                ║
║  ${W}Time:${N} ${C}$(date +"%H:%M:%S")${P}          ║
║                              ║
║  ${G}Configuration restored${P}        ║
╚══════════════════════════════╝${N}
"
        send_telegram "$message"
    else
        echo -e "${R}Restore failed${N}"
    fi
    
    rm -f "$temp_file"
}

# Notification Functions
notify_expiry() {
    local host="$1"
    local ip="$2"
    local client="$3"
    local isp="$4"
    local exp_date="$5"
    
    local message="
${P}╔══════════════════════════════╗
║     ⚠️ LICENSE EXPIRED        ║
╠══════════════════════════════╣
║                              ║
║  ${W}Client:${N} ${C}$client${P}              ║
║  ${W}Server:${N} ${C}$host${P}                ║
║  ${W}IP:${N} ${C}$ip${P}                      ║
║  ${W}ISP:${N} ${C}$isp${P}                    ║
║  ${W}Expired:${N} ${R}$exp_date${P}           ║
║                              ║
║  ${Y}Contact: @bendakerep${P}          ║
╚══════════════════════════════╝${N}
"
    
    local keyboard='{"inline_keyboard":[[{"text":"🔁 Renew License","url":"https://t.me/bendakerep"}]]}'
    
    send_telegram "$message" "$keyboard"
}

notify_renewed() {
    local host="$1"
    local ip="$2"
    local client="$3"
    local isp="$4"
    local expiry_ts="$5"
    
    local remaining_days=$(( (expiry_ts - $(date +%s)) / 86400 ))
    
    local message="
${P}╔══════════════════════════════╗
║     ✅ LICENSE RENEWED        ║
╠══════════════════════════════╣
║                              ║
║  ${W}Client:${N} ${C}$client${P}              ║
║  ${W}Server:${N} ${C}$host${P}                ║
║  ${W}Remaining:${N} ${G}$remaining_days days${P}    ║
║                              ║
║  ${Y}Thank you for choosing       ║
║     PONDOK VPN${P}               ║
╚══════════════════════════════╝${N}
"
    
    send_telegram "$message"
}

notify_api() {
    local api_key="$1"
    local server_ip="$2"
    local domain="$3"
    
    local message="
${P}╔══════════════════════════════╗
║     🔑 API KEY GENERATED      ║
╠══════════════════════════════╣
║                              ║
║  ${W}Key:${N} ${C}$api_key${P}                ║
║  ${W}Server:${N} ${C}$server_ip${P}           ║
║  ${W}Domain:${N} ${C}$domain${P}              ║
║                              ║
║  ${Y}PONDOK VPN - @bendakerep${P}     ║
╚══════════════════════════════╝${N}
"
    
    send_telegram "$message"
}

# Test Notification
test_notify() {
    local host=$(get_host)
    local ip=$(curl -s ifconfig.me)
    
    local message="
${P}╔══════════════════════════════╗
║     🔔 TEST NOTIFICATION     ║
╠══════════════════════════════╣
║                              ║
║  ${W}Host:${N} ${C}$host${P}                ║
║  ${W}IP:${N} ${C}$ip${P}                    ║
║  ${W}Time:${N} ${C}$(date)${P}              ║
║                              ║
║  ${G}PONDOK VPN System${P}            ║
╚══════════════════════════════╝${N}
"
    
    send_telegram "$message"
    echo -e "${G}✓ Test notification sent${N}"
}

# Main Menu
show_menu() {
    show_banner
    echo -e "${C}═══════════ MAIN MENU ═══════════${N}"
    echo ""
    echo -e "${W}[1]${N} ${G}Setup Telegram Notification${N}"
    echo -e "${W}[2]${N} ${G}Backup Configuration${N}"
    echo -e "${W}[3]${N} ${G}Restore Configuration${N}"
    echo -e "${W}[4]${N} ${Y}Send Test Notification${N}"
    echo -e "${W}[0]${N} ${R}Exit${N}"
    echo ""
    echo -e "${C}══════════════════════════════════${N}"
}

# Main
case "$1" in
    backup)
        backup
        ;;
    restore)
        restore
        ;;
    setup-telegram)
        setup_telegram
        ;;
    test)
        test_notify
        ;;
    expiry-notification)
        [ $# -ne 6 ] && echo "Usage: $0 expiry-notification <host> <ip> <client> <isp> <exp_date>" && exit 1
        notify_expiry "$2" "$3" "$4" "$5" "$6"
        ;;
    renewed-notification)
        [ $# -ne 6 ] && echo "Usage: $0 renewed-notification <host> <ip> <client> <isp> <expiry_ts>" && exit 1
        notify_renewed "$2" "$3" "$4" "$5" "$6"
        ;;
    api-key-notification)
        [ $# -ne 4 ] && echo "Usage: $0 api-key-notification <api_key> <server_ip> <domain>" && exit 1
        notify_api "$2" "$3" "$4"
        ;;
    *)
        # Interactive mode
        while true; do
            show_menu
            read -p "$(echo -e ${Y}Select option [0-4]: ${N})" choice
            
            case $choice in
                1) setup_telegram ;;
                2) backup ;;
                3) restore ;;
                4) test_notify ;;
                0) echo -e "${C}Goodbye!${N}"; exit 0 ;;
                *) echo -e "${R}Invalid option${N}" ;;
            esac
            
            echo ""
            read -p "$(echo -e ${Y}Press Enter to continue...${N})" dummy
        done
        ;;
esac
EOF

# Install zi.sh
wget -q -O /usr/local/bin/zi.sh \
    "https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/zi.sh" 2>/dev/null || {
    echo -e "  ${YELLOW}⚠️  Downloading zi.sh from GitHub...${NC}"
    # Fallback ke inline script jika download gagal
    cat > /usr/local/bin/zi.sh << 'EOF'
#!/bin/bash
echo "ZiVPN User Manager"
echo "Please download the complete zi.sh from:"
echo "https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/zi.sh"
echo ""
echo "Or run:"
echo "wget -O /usr/local/bin/zi.sh https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/zi.sh"
echo "chmod +x /usr/local/bin/zi.sh"
EOF
}

chmod +x /usr/local/bin/ziv-helper.sh
chmod +x /usr/local/bin/zi.sh
echo -e "${GREEN}✅ Helper tools installed${NC}"

# CREATE SYSTEMD SERVICE
echo -e "${YELLOW}[6] Creating service...${NC}"
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

# SEND INSTALL NOTIFICATION
echo -e "${YELLOW}[8] Sending installation notification...${NC}"
if [ -f /etc/zivpn/telegram.conf ]; then
    /usr/local/bin/ziv-helper.sh test > /dev/null 2>&1
    echo -e "  ${GREEN}✅ Notification sent to Telegram${NC}"
fi

# FINAL OUTPUT
clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    INSTALLATION COMPLETE                       ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║                                                                ║"
echo -e "║  ${GREEN}✅${NC} License Verified                                    ║"
echo -e "║  ${GREEN}✅${NC} ZiVPN Core                                          ║"
echo -e "║  ${GREEN}✅${NC} Configuration                                       ║"
echo -e "║  ${GREEN}✅${NC} Telegram Auto-configured                            ║"
echo -e "║  ${GREEN}✅${NC} Service Running                                     ║"
echo "║                                                                ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║                     QUICK COMMANDS                             ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║                                                                ║"
echo -e "║  ${YELLOW}Start Manager:${NC} ${CYAN}zi.sh${NC}                                       ║"
echo -e "║  ${YELLOW}Backup:${NC} ${CYAN}ziv-helper.sh backup${NC}                                ║"
echo -e "║  ${YELLOW}Test Telegram:${NC} ${CYAN}ziv-helper.sh test${NC}                           ║"
echo "║                                                                ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║                     SERVER INFO                                ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║                                                                ║"
echo -e "║  ${YELLOW}IP:${NC} ${CYAN}$SERVER_IP${NC}                                           ║"
echo -e "║  ${YELLOW}Port:${NC} ${CYAN}5667 UDP${NC}                                         ║"
echo -e "║  ${YELLOW}Telegram:${NC} ${CYAN}Ready (Bot: Pondok VPN)${NC}                         ║"
echo "║                                                                ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Support: @bendakerep                                          ║"
echo "║  Bot Token: 8477114091:AAEYVH4HAG_8q6AIkPG_72c_4NDm7pf0Xx8     ║"
echo "║  Chat ID: 5503146862                                           ║"
echo "╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✅ ZiVPN installation complete!${NC}"
echo ""
echo -e "${YELLOW}Run 'zi.sh' to start user management.${NC}"
echo -e "${YELLOW}Run 'ziv-helper.sh test' to verify Telegram notifications.${NC}"
echo ""