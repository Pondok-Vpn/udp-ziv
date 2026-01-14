#!/bin/bash
# ══════════════════════════════
# BACKUP FILE : UDP ZIVPN HELPER
# CREATED     : PONDOK VPN (C) 2026-01-06
# TELEGRAM    : @bendakerep
# EMAIL       : redzall55@gmail.com
# ══════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
NC='\033[0m'
CONFIG_DIR="/etc/zivpn"
USER_DB="${CONFIG_DIR}/users.db"
CONFIG_FILE="${CONFIG_DIR}/config.json"
TELEGRAM_CONF="${CONFIG_DIR}/telegram.conf"
BACKUP_FILES=("config.json" "users.db" "devices.db" "locked.db")
LOG_FILE="/var/log/zivpn_helper.log"
# ============================================
#              INITIAL CHECKS
# ============================================
check_dependencies() {
    local missing=()
    for cmd in jq curl; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "${RED}Missing dependencies: ${missing[*]}${NC}"
        echo "Install with: apt install ${missing[*]} -y"
        exit 1
    fi
}
# ============================================
#              HELPER FUNCTIONS
# ============================================

function get_host() {
    local host
    host=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "unknown")
    if [ -f "${CONFIG_DIR}/zivpn.crt" ]; then
        local cert_cn
        cert_cn=$(openssl x509 -in "${CONFIG_DIR}/zivpn.crt" -noout -subject 2>/dev/null | sed -n 's/.*CN\s*=\s*\([^,]*\).*/\1/p')
        if [ -n "$cert_cn" ] && [ "$cert_cn" != "zivpn" ]; then
            host="$cert_cn"
        fi
    fi
    echo "$host"
}
function send_telegram_notification() {
    local message="$1"
    local keyboard="$2"
    if [ ! -f "$TELEGRAM_CONF" ]; then
        return 1
    fi
    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_CHAT_ID=""
    if [ -f "$TELEGRAM_CONF" ]; then
        . "$TELEGRAM_CONF" 2>/dev/null
    fi
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        return 1
    fi
    local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    local curl_opts=(
        "-s"
        "-X" "POST"
        "$api_url"
        "-d" "chat_id=${TELEGRAM_CHAT_ID}"
        "--data-urlencode" "text=${message}"
    )
    
    if [ -n "$keyboard" ]; then
        curl_opts+=("-d" "reply_markup=${keyboard}")
    else
        curl_opts+=("-d" "parse_mode=Markdown")
    fi
    curl "${curl_opts[@]}" > /dev/null 2>&1
}

function log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}
# ============================================
#        DELETE EXPIRED ACCOUNTS
# ============================================
function delete_expired_accounts() {
    echo "--- Delete Expired Accounts ---"
    log_message "Starting expired accounts cleanup"
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo "No accounts found"
        log_message "No accounts database found"
        return 0
    fi
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Config file not found"
        log_message "Config file not found"
        return 1
    fi
    local current_timestamp=$(date +%s)
    local temp_file=$(mktemp)
    local deleted_count=0
    local updated_config
    echo "Checking expired accounts..."
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%s)"
    if ! updated_config=$(cat "$CONFIG_FILE" 2>/dev/null); then
        echo "Failed to read config file"
        return 1
    fi
    while IFS=':' read -r password expiry_timestamp client_name; do
        if [ -z "$password" ] || [ -z "$expiry_timestamp" ]; then
            continue
        fi
        if [ "$expiry_timestamp" -lt "$current_timestamp" ]; then
            updated_config=$(echo "$updated_config" | jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo "Warning: Failed to remove $client_name from config"
                continue
            fi
            deleted_count=$((deleted_count + 1))
            echo "✓ Deleted: $client_name"
            log_message "Deleted expired account: $client_name ($password)"
        else
            echo "$password:$expiry_timestamp:$client_name" >> "$temp_file"
        fi
    done < "$USER_DB"
    if [ $deleted_count -gt 0 ]; then
        echo "$updated_config" > "$CONFIG_FILE"
        mv "$temp_file" "$USER_DB"
        chmod 600 "$USER_DB"
        if systemctl restart zivpn.service >/dev/null 2>&1; then
            echo "✅ Service restarted"
        else
            echo "⚠️  Failed to restart service"
        fi
        echo "✅ Deleted $deleted_count expired accounts"
        log_message "Deleted $deleted_count expired accounts"
        if [ -f "$TELEGRAM_CONF" ]; then
            local host=$(get_host)
            local message="🗑️ *Auto Delete Expired Accounts*
Deleted: $deleted_count accounts
Time: $(date +'%H:%M:%S')
Server: $host"
            send_telegram_notification "$message"
        fi
    else
        echo "✅ No expired accounts found"
        rm -f "$temp_file"
    fi
}
# ============================================
#              TELEGRAM SETUP
# ============================================
function setup_telegram() {
    echo "--- Telegram Setup ---"
    read -p "Masukkan Bot Token: " api_key
    read -p "Masukkan Chat ID: " chat_id
    if [ -z "$api_key" ] || [ -z "$chat_id" ]; then
        echo "Token dan Chat ID tidak boleh kosong."
        return 1
    fi
    if [[ ! "$api_key" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
        echo "Format token salah. Contoh: 1234567890:ABCdefGHIjklMNopQRSTuvwxyz"
        return 1
    fi
    echo "Testing bot token..."
    local response
    response=$(curl -s --max-time 10 "https://api.telegram.org/bot${api_key}/getMe")
    if echo "$response" | grep -q '"ok":true'; then
        local bot_name=$(echo "$response" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
        echo "✓ Token valid. Bot: @$bot_name"
    else
        echo "❌ Token invalid atau tidak bisa terkoneksi"
        return 1
    fi
    mkdir -p "$CONFIG_DIR"
    echo "TELEGRAM_BOT_TOKEN=\"$api_key\"" > "$TELEGRAM_CONF"
    echo "TELEGRAM_CHAT_ID=\"$chat_id\"" >> "$TELEGRAM_CONF"
    chmod 600 "$TELEGRAM_CONF"
    local test_msg="✅ ZiVPN Telegram Connected!
Bot: @${bot_name}
Time: $(date +'%Y-%m-%d %H:%M:%S')"
    if send_telegram_notification "$test_msg"; then
        echo "✓ Setup berhasil. Test message sent."
        return 0
    else
        echo "⚠️  Setup disimpan tapi test message gagal"
        return 0
    fi
}
# ============================================
#              BACKUP FUNCTION
# ============================================
function handle_backup() {
    echo "--- Backup Data ---"
    log_message "Starting backup"
    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo "Telegram belum dikonfigurasi."
        read -p "Setup Telegram sekarang? (y/n): " choice
        if [[ "$choice" == "y" ]] || [[ "$choice" == "Y" ]]; then
            setup_telegram
            if [ $? -ne 0 ]; then
                echo "Backup dibatalkan."
                exit 1
            fi
        else
            echo "Backup dibatalkan."
            exit 1
        fi
    fi
    . "$TELEGRAM_CONF" 2>/dev/null
    
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "Telegram config tidak valid."
        exit 1
    fi
    if ! command -v zip >/dev/null 2>&1; then
        echo "Installing zip..."
        apt-get install -y zip >/dev/null 2>&1 || yum install -y zip >/dev/null 2>&1
    fi
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="/tmp/zivpn_backup_${timestamp}.zip"
    echo "Creating backup..."
    cd "$CONFIG_DIR" 2>/dev/null || { echo "Config directory not found"; exit 1; }
    local files_to_backup=()
    for file in "${BACKUP_FILES[@]}"; do
        if [ -f "$file" ]; then
            files_to_backup+=("$file")
        fi
    done
    if [ ${#files_to_backup[@]} -eq 0 ]; then
        echo "❌ No files to backup"
        exit 1
    fi
    zip -q "$backup_file" "${files_to_backup[@]}"
    
    if [ ! -f "$backup_file" ]; then
        echo "❌ Failed to create backup"
        exit 1
    fi
    echo "Uploading to Telegram..."
    local response
    response=$(curl -s -F "chat_id=${TELEGRAM_CHAT_ID}" \
        -F "document=@${backup_file}" \
        -F "caption=ZiVPN Backup $(date +'%Y-%m-%d %H:%M:%S')" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument")
    local file_id=$(echo "$response" | jq -r '.result.document.file_id' 2>/dev/null)
    if [ -z "$file_id" ] || [ "$file_id" = "null" ]; then
        echo "❌ Failed to upload to Telegram"
        echo "Response: $response"
        rm -f "$backup_file"
        exit 1
    fi
    local host=$(get_host)
    local date_now=$(date +"%d %B %Y %H:%M")
    local total_users=0
    if [ -f "$USER_DB" ]; then
        total_users=$(wc -l < "$USER_DB" 2>/dev/null || echo "0")
    fi
    local message="📦 *ZiVPN Backup Complete*
Server: \`$host\`
Date: $date_now
Total Users: $total_users
File ID: \`$file_id\`
Backup Time: $(date +'%H:%M:%S')"
    send_telegram_notification "$message"
    rm -f "$backup_file"
    echo "✅ Backup successful!"
    echo "File ID: $file_id"
    log_message "Backup completed. File ID: $file_id"
}
# ============================================
#              RESTORE FUNCTION
# ============================================
function handle_restore() {
    echo "--- Restore Data ---"
    log_message "Starting restore"
    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo "Telegram not configured."
        exit 1
    fi
    . "$TELEGRAM_CONF" 2>/dev/null
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "Invalid Telegram config."
        exit 1
    fi
    read -p "Masukkan File ID: " file_id
    if [ -z "$file_id" ]; then
        echo "File ID tidak boleh kosong."
        exit 1
    fi
    read -p "Yakin restore? Data saat ini akan ditimpa. (y/n): " confirm
    if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
        echo "Cancelled."
        exit 0
    fi
    echo "Downloading backup..."
    local response
    response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getFile?file_id=${file_id}")
    local file_path=$(echo "$response" | jq -r '.result.file_path' 2>/dev/null)
    if [ -z "$file_path" ] || [ "$file_path" = "null" ]; then
        echo "❌ File not found"
        exit 1
    fi
    local temp_file="/tmp/zivpn_restore_$(basename "$file_path")"
    curl -s -o "$temp_file" "https://api.telegram.org/file/bot${TELEGRAM_BOT_TOKEN}/${file_path}"
    
    if [ ! -f "$temp_file" ]; then
        echo "❌ Failed to download"
        exit 1
    fi
    if ! command -v unzip >/dev/null 2>&1; then
        echo "Installing unzip..."
        apt-get install -y unzip >/dev/null 2>&1 || yum install -y unzip >/dev/null 2>&1
    fi
    echo "Extracting..."
    local backup_dir="/tmp/zivpn_backup_before_restore_$(date +%s)"
    mkdir -p "$backup_dir"
    cp -r "$CONFIG_DIR"/* "$backup_dir/" 2>/dev/null
    if unzip -o "$temp_file" -d "$CONFIG_DIR" >/dev/null 2>&1; then
        chmod 600 "$CONFIG_DIR"/*
        chown root:root "$CONFIG_DIR"/*
        if systemctl restart zivpn.service; then
            echo "✅ Restore successful!"
            send_telegram_notification "✅ Restore completed successfully!"
            log_message "Restore completed from file ID: $file_id"
        else
            echo "⚠️  Files restored but service restart failed"
            log_message "Restore completed but service restart failed"
        fi
    else
        echo "❌ Failed to extract backup"
        # Restore backup
        cp -r "$backup_dir"/* "$CONFIG_DIR/" 2>/dev/null
        log_message "Restore failed"
    fi
    rm -f "$temp_file"
    rm -rf "$backup_dir"
}
# ============================================
#              NOTIFICATION HANDLER
# ============================================
function handle_notification() {
    local type="$1"
    shift
    case "$type" in
        "expiry")
            local message="⚠️ *License Expired*
IP: \`$2\`
Host: $1
Client: $3
ISP: $4
Expired: $5
Time: $(date +'%H:%M:%S')"
            local keyboard='{"inline_keyboard":[[{"text":"Perpanjang","url":"https://t.me/bendakerep"}]]}'
            send_telegram_notification "$message" "$keyboard"
            ;;
            
        "renewed")
            local message="✅ *License Renewed*
IP: \`$2\`
Host: $1
Client: $3
Remaining: $5 days
Renewed: $(date +'%H:%M:%S')"
            send_telegram_notification "$message"
            ;;
            
        "custom")
            send_telegram_notification "$2"
            ;;
            
        *)
            echo "Unknown notification type: $type"
            ;;
    esac
}
# ============================================
#              AUTO BACKUP (CRON)
# ============================================
function auto_backup() {
    if [ ! -f "$TELEGRAM_CONF" ]; then
        log_message "Auto backup skipped: Telegram not configured"
        return 1
    fi
    . "$TELEGRAM_CONF" 2>/dev/null
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        log_message "Auto backup skipped: Invalid Telegram config"
        return 1
    fi
    local timestamp=$(date +%Y%m%d-%H%M)
    local backup_file="/tmp/zivpn_auto_backup_${timestamp}.zip"
    cd "$CONFIG_DIR" 2>/dev/null || return 1
    local files_found=0
    for file in "${BACKUP_FILES[@]}"; do
        if [ -f "$file" ]; then
            files_found=1
            break
        fi
    done
    if [ $files_found -eq 0 ]; then
        log_message "Auto backup: No files found"
        return 1
    fi
    if zip -q "$backup_file" "${BACKUP_FILES[@]}" 2>/dev/null; then
        curl -s -F "chat_id=${TELEGRAM_CHAT_ID}" \
            -F "document=@${backup_file}" \
            -F "caption=Auto Backup $(date +'%Y-%m-%d %H:%M')" \
            "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" > /dev/null
        log_message "Auto backup completed"
    else
        log_message "Auto backup failed"
    fi
    rm -f "$backup_file" 2>/dev/null
}
# ============================================
#              MAIN DISPATCHER
# ============================================
check_dependencies
case "$1" in
    "setup")
        setup_telegram
        ;;
    "backup")
        handle_backup
        ;;
    "restore")
        handle_restore
        ;;
    "auto-backup")
        auto_backup
        ;;
    "delete_expired")
        delete_expired_accounts
        ;;
    "notify")
        shift
        case "$1" in
            "expiry")
                if [ $# -eq 6 ]; then
                    handle_notification "expiry" "$2" "$3" "$4" "$5" "$6"
                else
                    echo "Usage: $0 notify expiry <host> <ip> <client> <isp> <exp_date>"
                fi
                ;;
            "renewed")
                if [ $# -eq 5 ]; then
                    handle_notification "renewed" "$2" "$3" "$4" "$5"
                else
                    echo "Usage: $0 notify renewed <host> <ip> <client> <isp> <days>"
                fi
                ;;
            "custom")
                if [ $# -eq 2 ]; then
                    handle_notification "custom" "$2"
                else
                    echo "Usage: $0 notify custom <message>"
                fi
                ;;
            *)
                echo "Available notify types: expiry, renewed, custom"
                ;;
        esac
        ;;
    "test")
        if [ ! -f "$TELEGRAM_CONF" ]; then
            echo "Telegram not configured"
            exit 1
        fi
        send_telegram_notification "✅ Test notification $(date +'%H:%M:%S')"
        echo "Test message sent"
        ;;
    *)
        echo "ZiVPN Helper v1.0"
        echo "Usage: $0 {setup|backup|restore|notify|test|auto-backup|delete_expired}"
        echo ""
        echo "Commands:"
        echo "  setup           - Setup Telegram bot"
        echo "  backup          - Backup to Telegram"
        echo "  restore         - Restore from Telegram"
        echo "  delete_expired  - Delete expired accounts"
        echo "  auto-backup     - Auto backup (for cron)"
        echo "  notify          - Send notifications"
        echo "  test            - Test Telegram connection"
        echo ""
        echo "Notify Examples:"
        echo "  $0 notify expiry \"myhost.com\" \"1.2.3.4\" \"John\" \"ISP\" \"2024-12-31\""
        echo "  $0 notify custom \"Hello World\""
        ;;
esac
