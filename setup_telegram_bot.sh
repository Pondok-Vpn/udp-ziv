#!/bin/bash
# =============================
# SETUP TELEGRAM BOT FOR ZIVPN
# BY: PONDOK VPN
# =============================

# Colors
RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
NC='\033[0m'

clear
echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     ${YELLOW}TELEGRAM BOT SETUP FOR ZIVPN${BLUE}     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: Please run as root${NC}"
    exit 1
fi

# Step 1: Install dependencies
echo -e "${YELLOW}[1] Installing dependencies...${NC}"
apt-get update
apt-get install -y jq curl bc

# Step 2: Setup Telegram configuration
echo -e "${YELLOW}[2] Setting up Telegram configuration...${NC}"

if [ ! -f "/etc/zivpn/telegram.conf" ]; then
    echo ""
    echo -e "${BLUE}════════ TELEGRAM BOT SETUP ════════${NC}"
    read -p "Enter your Telegram Bot Token: " bot_token
    read -p "Enter your Telegram Chat ID: " chat_id
    
    echo "TELEGRAM_BOT_TOKEN=${bot_token}" > /etc/zivpn/telegram.conf
    echo "TELEGRAM_CHAT_ID=${chat_id}" >> /etc/zivpn/telegram.conf
    echo "TELEGRAM_ENABLED=true" >> /etc/zivpn/telegram.conf
    
    echo -e "${GREEN}✅ Telegram configuration saved${NC}"
else
    echo -e "${GREEN}✅ Telegram configuration already exists${NC}"
fi

# Step 3: Copy bot script
echo -e "${YELLOW}[3] Copying bot script...${NC}"
cp telegram_bot.sh /etc/zivpn/telegram_bot.sh
chmod +x /etc/zivpn/telegram_bot.sh

# Step 4: Create systemd service
echo -e "${YELLOW}[4] Creating systemd service...${NC}"
cat > /etc/systemd/system/zivpn-bot.service << EOF
[Unit]
Description=ZIVPN Telegram Bot Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/bin/bash /etc/zivpn/telegram_bot.sh start
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=zivpn-bot

[Install]
WantedBy=multi-user.target
EOF

# Step 5: Create CLI command
echo -e "${YELLOW}[5] Creating CLI command...${NC}"
cat > /usr/local/bin/zivpn-bot << 'EOF'
#!/bin/bash
# ZIVPN Telegram Bot CLI

case "$1" in
    "start")
        systemctl start zivpn-bot.service
        echo "ZIVPN Telegram Bot started"
        ;;
    "stop")
        systemctl stop zivpn-bot.service
        echo "ZIVPN Telegram Bot stopped"
        ;;
    "restart")
        systemctl restart zivpn-bot.service
        echo "ZIVPN Telegram Bot restarted"
        ;;
    "status")
        systemctl status zivpn-bot.service
        ;;
    "enable")
        systemctl enable zivpn-bot.service
        echo "ZIVPN Telegram Bot enabled on boot"
        ;;
    "disable")
        systemctl disable zivpn-bot.service
        echo "ZIVPN Telegram Bot disabled on boot"
        ;;
    "test")
        /etc/zivpn/telegram_bot.sh test
        ;;
    "send")
        if [ -z "$2" ]; then
            echo "Usage: zivpn-bot send <message>"
            exit 1
        fi
        /etc/zivpn/telegram_bot.sh send "$2"
        ;;
    "log")
        journalctl -u zivpn-bot.service -f
        ;;
    *)
        echo "Usage: zivpn-bot {start|stop|restart|status|enable|disable|test|send|log}"
        echo ""
        echo "Commands:"
        echo "  start    - Start Telegram Bot"
        echo "  stop     - Stop Telegram Bot"
        echo "  restart  - Restart Telegram Bot"
        echo "  status   - Check Bot status"
        echo "  enable   - Enable Bot on boot"
        echo "  disable  - Disable Bot on boot"
        echo "  test     - Send test message"
        echo "  send     - Send custom message"
        echo "  log      - View bot logs"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/zivpn-bot

# Step 6: Reload systemd
echo -e "${YELLOW}[6] Reloading systemd...${NC}"
systemctl daemon-reload

# Step 7: Start and enable bot
echo -e "${YELLOW}[7] Starting Telegram Bot...${NC}"
systemctl start zivpn-bot.service
systemctl enable zivpn-bot.service

# Step 8: Test bot
echo -e "${YELLOW}[8] Testing Telegram Bot...${NC}"
sleep 2
/etc/zivpn/telegram_bot.sh test

# Step 9: Show status
echo -e "${YELLOW}[9] Bot Status:${NC}"
systemctl status zivpn-bot.service --no-pager -l

echo ""
echo -e "${BLUE}════════ SETUP COMPLETE ════════${NC}"
echo ""
echo -e "${GREEN}✅ Telegram Bot setup completed successfully!${NC}"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Available Commands:${NC}"
echo -e "  ${YELLOW}zivpn-bot start${NC}    - Start Telegram Bot"
echo -e "  ${YELLOW}zivpn-bot stop${NC}     - Stop Telegram Bot"
echo -e "  ${YELLOW}zivpn-bot status${NC}   - Check Bot status"
echo -e "  ${YELLOW}zivpn-bot test${NC}     - Send test message"
echo -e "  ${YELLOW}zivpn-bot log${NC}      - View bot logs"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Telegram Commands:${NC}"
echo -e "  ${YELLOW}/start${NC} or ${YELLOW}/menu${NC} - Show main menu"
echo -e "  ${YELLOW}/list${NC} - List all accounts"
echo -e "  ${YELLOW}/create${NC} - Create new account"
echo -e "  ${YELLOW}/delete${NC} - Delete account"
echo -e "  ${YELLOW}/help${NC} - Show help"
echo ""
echo -e "${GREEN}Now go to your Telegram and send /start to your bot!${NC}"
echo ""
