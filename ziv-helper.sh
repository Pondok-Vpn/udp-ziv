cat > /usr/local/bin/ziv-helper.sh << 'EOF'
#!/bin/bash
# ============================================
# ZIVPN HELPER SCRIPT - PONDOK VPN EDITION
# Enhanced with Modern UI & Features
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
    
    read -p "$(echo -e ${Y}Bot API Key: ${N})" api_key
    read -p "$(echo -e ${Y}Chat ID (from @userinfobot): ${N})" chat_id
    
    if [ -z "$api_key" ] || [ -z "$chat_id" ]; then
        echo -e "${R}Configuration failed! Fields cannot be empty.${N}"
        return 1
    fi
    
    echo "TELEGRAM_BOT_TOKEN=${api_key}" > "$TELEGRAM_CONF"
    echo "TELEGRAM_CHAT_ID=${chat_id}" >> "$TELEGRAM_CONF"
    chmod 600 "$TELEGRAM_CONF"
    
    echo -e "${G}✓ Telegram configuration saved${N}"
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
        echo -e "Setting up Telegram first..."
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

chmod +x /usr/local/bin/ziv-helper.sh