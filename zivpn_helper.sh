#!/bin/bash
# ===========================================
# ZIVPN HELPER - TELEGRAM BOT & BACKUP SYSTEM
# Version: 2.0
# Telegram: @bendakerep
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
CYAN='\033[0;96m'
NC='\033[0m'

# Variables
CONFIG_DIR="/etc/zivpn"
TELEGRAM_CONF="${CONFIG_DIR}/telegram.conf"
BACKUP_DIR="/var/backups/zivpn"
LOG_FILE="/var/log/zivpn_helper.log"

# Function untuk garis
print_line() {
    echo -e "${BLUE}======================================================${NC}"
}

print_green_line() {
    echo -e "${GREEN}======================================================${NC}"
}

# Logging
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Check dependencies
check_deps() {
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}Installing curl...${NC}"
        apt-get install -y curl > /dev/null 2>&1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Installing jq...${NC}"
        apt-get install -y jq > /dev/null 2>&1
    fi
}

# Setup Telegram Bot dengan VALIDASI
setup_telegram() {
    print_line
    echo -e "${BLUE}           SETUP TELEGRAM BOT                  ${NC}"
    print_line
    echo ""
    
    echo -e "${CYAN}Instructions:${NC}"
    echo "1. Create bot via @BotFather"
    echo "2. Get your bot token"
    echo "3. Get your chat ID from @userinfobot"
    echo ""
    
    read -p "Enter Bot Token: " bot_token
    read -p "Enter Chat ID   : " chat_id
    
    if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
        echo -e "${RED}❌ Token and Chat ID cannot be empty!${NC}"
        return 1
    fi
    
    # Validasi format token
    if [[ ! "$bot_token" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}❌ Invalid bot token format!${NC}"
        echo -e "${YELLOW}Example: 1234567890:ABCdefGHIjklMNopQRSTuvwxyz${NC}"
        return 1
    fi
    
    # Test the bot token
    echo -e "${YELLOW}Testing bot token...${NC}"
    response=$(curl -s "https://api.telegram.org/bot${bot_token}/getMe")
    
    if echo "$response" | jq -e '.ok == true' >/dev/null 2>&1; then
        bot_name=$(echo "$response" | jq -r '.result.username')
        echo -e "${GREEN}✅ Bot found: @${bot_name}${NC}"
    else
        echo -e "${RED}❌ Invalid bot token! Please check again.${NC}"
        return 1
    fi
    
    # Save configuration
    mkdir -p "$CONFIG_DIR"
    echo "TELEGRAM_BOT_TOKEN=${bot_token}" > "$TELEGRAM_CONF"
    echo "TELEGRAM_CHAT_ID=${chat_id}" >> "$TELEGRAM_CONF"
    chmod 600 "$TELEGRAM_CONF"
    
    # Send test message
    echo -e "${YELLOW}Sending test message...${NC}"
    send_notification "✅ ZiVPN Telegram Bot Connected!
📅 $(date '+%Y-%m-%d %H:%M:%S')
🤖 Bot: @${bot_name}
📱 Ready to receive notifications!"
    
    echo ""
    print_green_line
    echo -e "${GREEN}           TELEGRAM BOT SETUP COMPLETE        ${NC}"
    print_green_line
    echo ""
    
    log_message "INFO" "Telegram bot setup completed for chat ID: $chat_id"
    return 0
}

# Send notification
send_notification() {
    local message="$1"
    
    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo -e "${RED}❌ Telegram not configured!${NC}"
        echo -e "${YELLOW}Run: $0 setup${NC}"
        return 1
    fi
    
    source "$TELEGRAM_CONF" 2>/dev/null
    
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo -e "${RED}❌ Invalid Telegram configuration!${NC}"
        return 1
    fi
    
    local response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" \
        -d "parse_mode=Markdown")
    
    if echo "$response" | jq -e '.ok == true' >/dev/null 2>&1; then
        return 0
    else
        echo -e "${YELLOW}⚠️  Failed to send notification${NC}"
        return 1
    fi
}

# Backup dengan fitur LENGKAP
backup_zivpn() {
    print_line
    echo -e "${BLUE}           BACKUP ZIVPN CONFIGURATION          ${NC}"
    print_line
    echo ""
    
    check_deps
    
    # Cek apakah Telegram sudah diatur
    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo -e "${YELLOW}⚠️  Telegram not configured${NC}"
        read -p "Setup Telegram now? (y/n): " choice
        
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            setup_telegram
            if [ $? -ne 0 ]; then
                echo -e "${YELLOW}Continuing with local backup only...${NC}"
            fi
        fi
    fi
    
    # Buat backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Backup filename dengan timestamp
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/zivpn_backup_${timestamp}.tar.gz"
    local temp_dir="/tmp/zivpn_backup_${timestamp}"
    
    print_line
    echo -e "${CYAN}Creating backup...${NC}"
    print_line
    echo ""
    
    # Buat temporary directory untuk backup
    mkdir -p "$temp_dir"
    
    # Copy semua file penting
    if [ -d "$CONFIG_DIR" ]; then
        cp -r "$CONFIG_DIR" "$temp_dir/"
        echo -e "${GREEN}✓ Config files${NC}"
    fi
    
    # Copy logs
    if [ -f "/var/log/zivpn.log" ]; then
        cp /var/log/zivpn.log "$temp_dir/"
        echo -e "${GREEN}✓ Log files${NC}"
    fi
    
    # Copy service file
    if [ -f "/etc/systemd/system/zivpn.service" ]; then
        cp /etc/systemd/system/zivpn.service "$temp_dir/"
        echo -e "${GREEN}✓ Service file${NC}"
    fi
    
    # Buat info file
    cat > "$temp_dir/backup_info.txt" << EOF
ZiVPN Backup Information
=======================
Date: $(date)
Version: $(/usr/local/bin/zivpn --version 2>/dev/null || echo "Unknown")
IP: $(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
Files included:
- Configurations
- User database
- SSL certificates
- Log files
EOF
    
    # Buat tar.gz archive
    tar -czf "$backup_file" -C "$temp_dir" . 2>/dev/null
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}❌ Failed to create backup archive!${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    local file_size=$(du -h "$backup_file" | cut -f1)
    echo ""
    echo -e "${GREEN}✅ Backup created: ${backup_file}${NC}"
    echo -e "${CYAN}📦 Size: ${file_size}${NC}"
    
    # Cleanup temp dir
    rm -rf "$temp_dir"
    
    # Kirim ke Telegram jika diatur
    if [ -f "$TELEGRAM_CONF" ]; then
        source "$TELEGRAM_CONF" 2>/dev/null
        
        if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
            print_line
            echo -e "${CYAN}Sending to Telegram...${NC}"
            print_line
            echo ""
            
            # Upload file ke Telegram
            local response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
                -F "chat_id=${TELEGRAM_CHAT_ID}" \
                -F "document=@${backup_file}" \
                -F "caption=📦 ZiVPN Backup
📅 $(date '+%Y-%m-%d %H:%M:%S')
💾 Size: ${file_size}
🔐 Total users: $(wc -l < "${CONFIG_DIR}/users.db" 2>/dev/null || echo "0")")
            
            if echo "$response" | jq -e '.ok == true' >/dev/null 2>&1; then
                local file_id=$(echo "$response" | jq -r '.result.document.file_id')
                echo -e "${GREEN}✅ Backup sent to Telegram!${NC}"
                echo -e "${CYAN}📎 File ID: ${file_id}${NC}"
                
                # Simpan file ID untuk restore
                echo "BACKUP_${timestamp}_FILE_ID=${file_id}" >> "$CONFIG_DIR/backup_history.txt"
                
            else
                echo -e "${YELLOW}⚠️  Failed to send to Telegram${NC}"
            fi
        fi
    fi
    
    # Hapus backup lama (keep last 10)
    local backup_count=$(ls -1 "${BACKUP_DIR}/zivpn_backup_"*.tar.gz 2>/dev/null | wc -l)
    if [ "$backup_count" -gt 10 ]; then
        echo -e "${YELLOW}Cleaning old backups...${NC}"
        ls -t "${BACKUP_DIR}/zivpn_backup_"*.tar.gz | tail -n +11 | xargs rm -f
    fi
    
    echo ""
    print_green_line
    echo -e "${GREEN}           BACKUP COMPLETED                  ${NC}"
    print_green_line
    echo ""
    
    log_message "INFO" "Backup created: $backup_file"
    return 0
}

# Restore dengan VALIDASI
restore_zivpn() {
    print_line
    echo -e "${BLUE}           RESTORE ZIVPN CONFIGURATION         ${NC}"
    print_line
    echo ""
    
    check_deps
    
    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo -e "${RED}❌ Telegram not configured!${NC}"
        echo -e "${YELLOW}Setup Telegram first: $0 setup${NC}"
        return 1
    fi
    
    source "$TELEGRAM_CONF" 2>/dev/null
    
    echo -e "${CYAN}Restore Options:${NC}"
    echo "1) Restore from local backup file"
    echo "2) Restore from Telegram (using File ID)"
    echo ""
    
    read -p "Select option [1/2]: " restore_choice
    
    case $restore_choice in
        1)
            # Restore dari local file
            echo ""
            echo -e "${YELLOW}Available backups:${NC}"
            ls -lh "${BACKUP_DIR}/zivpn_backup_"*.tar.gz 2>/dev/null | awk '{print NR ") " $9 " (" $5 ")"}'
            echo ""
            
            read -p "Enter backup number: " backup_num
            
            local backup_files=($(ls "${BACKUP_DIR}/zivpn_backup_"*.tar.gz 2>/dev/null))
            
            if [ ${#backup_files[@]} -eq 0 ]; then
                echo -e "${RED}❌ No local backups found!${NC}"
                return 1
            fi
            
            if [[ "$backup_num" =~ ^[0-9]+$ ]] && [ "$backup_num" -ge 1 ] && [ "$backup_num" -le ${#backup_files[@]} ]; then
                local backup_file="${backup_files[$((backup_num-1))]}"
                echo -e "${GREEN}Selected: $(basename "$backup_file")${NC}"
            else
                echo -e "${RED}❌ Invalid selection!${NC}"
                return 1
            fi
            ;;
            
        2)
            # Restore dari Telegram
            echo ""
            read -p "Enter Telegram File ID: " file_id
            
            if [ -z "$file_id" ]; then
                echo -e "${RED}❌ File ID cannot be empty!${NC}"
                return 1
            fi
            
            # Download file dari Telegram
            echo -e "${YELLOW}Downloading from Telegram...${NC}"
            
            # Get file path
            local response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getFile?file_id=${file_id}")
            local file_path=$(echo "$response" | jq -r '.result.file_path // empty')
            
            if [ -z "$file_path" ]; then
                echo -e "${RED}❌ Invalid File ID or file not found!${NC}"
                return 1
            fi
            
            # Download file
            local backup_file="/tmp/zivpn_telegram_backup.tar.gz"
            curl -s -o "$backup_file" "https://api.telegram.org/file/bot${TELEGRAM_BOT_TOKEN}/${file_path}"
            
            if [ ! -s "$backup_file" ]; then
                echo -e "${RED}❌ Failed to download file!${NC}"
                return 1
            fi
            
            echo -e "${GREEN}✓ File downloaded${NC}"
            ;;
            
        *)
            echo -e "${RED}❌ Invalid option!${NC}"
            return 1
            ;;
    esac
    
    # Konfirmasi restore
    echo ""
    echo -e "${RED}⚠️  WARNING: This will overwrite current configuration!${NC}"
    read -p "Are you sure you want to restore? (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Restore cancelled.${NC}"
        return 0
    fi
    
    print_line
    echo -e "${CYAN}Restoring configuration...${NC}"
    print_line
    echo ""
    
    # Buat backup sebelum restore
    local pre_restore_backup="${BACKUP_DIR}/pre_restore_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$pre_restore_backup" -C /etc zivpn/ 2>/dev/null
    echo -e "${GREEN}✓ Pre-restore backup created${NC}"
    
    # Extract backup
    local temp_restore="/tmp/zivpn_restore_$(date +%s)"
    mkdir -p "$temp_restore"
    
    if tar -xzf "$backup_file" -C "$temp_restore" 2>/dev/null; then
        # Restore files
        if [ -d "$temp_restore/zivpn" ]; then
            cp -r "$temp_restore/zivpn"/* "$CONFIG_DIR/" 2>/dev/null
            echo -e "${GREEN}✓ Config files restored${NC}"
        fi
        
        # Restore service file jika ada
        if [ -f "$temp_restore/zivpn.service" ]; then
            cp "$temp_restore/zivpn.service" /etc/systemd/system/
            systemctl daemon-reload
            echo -e "${GREEN}✓ Service file restored${NC}"
        fi
        
        # Set permissions
        chmod 600 "$CONFIG_DIR"/*.key "$CONFIG_DIR"/*.db 2>/dev/null
        echo -e "${GREEN}✓ Permissions set${NC}"
        
        # Restart service
        systemctl restart zivpn.service
        echo -e "${GREEN}✓ Service restarted${NC}"
        
        # Cleanup
        rm -rf "$temp_restore"
        if [ "$restore_choice" = "2" ]; then
            rm -f "$backup_file"
        fi
        
        # Send notification
        send_notification "✅ ZiVPN Restore Completed!
📅 $(date '+%Y-%m-%d %H:%M:%S')
🔄 Configuration has been restored"
        
        echo ""
        print_green_line
        echo -e "${GREEN}           RESTORE COMPLETED                ${NC}"
        print_green_line
        echo ""
        
        log_message "INFO" "Restore completed from $backup_file"
        return 0
        
    else
        echo -e "${RED}❌ Failed to extract backup file!${NC}"
        rm -rf "$temp_restore"
        return 1
    fi
}

# Send custom notification
send_custom_notif() {
    local message="$2"
    
    if [ -z "$message" ]; then
        echo -e "${RED}❌ Message cannot be empty!${NC}"
        echo "Usage: $0 notify 'Your message here'"
        return 1
    fi
    
    print_line
    echo -e "${BLUE}           SENDING NOTIFICATION              ${NC}"
    print_line
    echo ""
    
    send_notification "$message"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Notification sent!${NC}"
    else
        echo -e "${RED}❌ Failed to send notification${NC}"
    fi
    
    echo ""
}

# Test Telegram connection
test_telegram() {
    print_line
    echo -e "${BLUE}           TEST TELEGRAM CONNECTION           ${NC}"
    print_line
    echo ""
    
    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo -e "${RED}❌ Telegram not configured!${NC}"
        return 1
    fi
    
    source "$TELEGRAM_CONF" 2>/dev/null
    
    echo -e "${CYAN}Testing bot token...${NC}"
    response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe")
    
    if echo "$response" | jq -e '.ok == true' >/dev/null 2>&1; then
        bot_name=$(echo "$response" | jq -r '.result.username')
        echo -e "${GREEN}✅ Bot: @${bot_name}${NC}"
    else
        echo -e "${RED}❌ Invalid bot token!${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Testing chat ID...${NC}"
    send_notification "🔔 ZiVPN Test Notification
✅ Connection test successful
📅 $(date '+%Y-%m-%d %H:%M:%S')
🤖 Bot: @${bot_name}"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Test message sent successfully!${NC}"
    else
        echo -e "${RED}❌ Failed to send test message${NC}"
        echo -e "${YELLOW}Check your Chat ID${NC}"
    fi
    
    echo ""
    print_green_line
    echo -e "${GREEN}           TEST COMPLETED                    ${NC}"
    print_green_line
    echo ""
}

# Show backup history
show_backups() {
    print_line
    echo -e "${BLUE}           BACKUP HISTORY                     ${NC}"
    print_line
    echo ""
    
    echo -e "${CYAN}Local Backups:${NC}"
    echo "========================="
    
    if ls "${BACKUP_DIR}/zivpn_backup_"*.tar.gz 2>/dev/null >/dev/null; then
        ls -lh "${BACKUP_DIR}/zivpn_backup_"*.tar.gz | awk '{print "📦 " $9 " (" $5 ") - " $6 " " $7 " " $8}'
    else
        echo "No local backups found"
    fi
    
    echo ""
    echo -e "${CYAN}Telegram Backup History:${NC}"
    echo "==============================="
    
    if [ -f "${CONFIG_DIR}/backup_history.txt" ]; then
        cat "${CONFIG_DIR}/backup_history.txt" | head -10
    else
        echo "No Telegram backup history"
    fi
    
    echo ""
}

# Main menu
case "$1" in
    "setup")
        setup_telegram
        ;;
    "backup")
        backup_zivpn
        ;;
    "restore")
        restore_zivpn
        ;;
    "notify")
        send_custom_notif "$@"
        ;;
    "test")
        test_telegram
        ;;
    "list")
        show_backups
        ;;
    "help"|"--help"|"-h")
        echo -e "${CYAN}ZiVPN Helper - Telegram Bot & Backup System${NC}"
        print_line
        echo ""
        echo "Available commands:"
        echo "  setup          - Setup Telegram bot"
        echo "  backup         - Backup configuration to Telegram"
        echo "  restore        - Restore from backup"
        echo "  notify 'msg'   - Send custom notification"
        echo "  test           - Test Telegram connection"
        echo "  list           - List available backups"
        echo "  help           - Show this help"
        echo ""
        echo "Examples:"
        echo "  $0 setup"
        echo "  $0 backup"
        echo "  $0 notify 'Server will restart in 5 minutes'"
        ;;
    *)
        echo -e "${CYAN}ZiVPN Helper${NC}"
        echo "Usage: $0 {setup|backup|restore|notify|test|list|help}"
        echo ""
        echo "Run '$0 help' for more information"
        ;;
esac
