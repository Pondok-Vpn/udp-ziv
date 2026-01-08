#!/bin/bash
# ===========================================
# ZIVPN HELPER 
# Version: 3.0
# Telegram: @bendakerep
# ===========================================

# Colors (minimal)
RED='\033[0;31m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
NC='\033[0m'

# Configuration
CONFIG_DIR="/etc/zivpn"
TELEGRAM_CONF="${CONFIG_DIR}/telegram.conf"
BACKUP_FILES=("config.json" "users.db" "devices.db")

# Helper Functions
function get_host() {
    if [ -f "${CONFIG_DIR}/zivpn.crt" ]; then
        local CERT_CN
        CERT_CN=$(openssl x509 -in "${CONFIG_DIR}/zivpn.crt" -noout -subject 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p')
        if [ "$CERT_CN" == "zivpn" ] || [ -z "$CERT_CN" ]; then
            curl -s ifconfig.me
        else
            echo "$CERT_CN"
        fi
    else
        curl -s ifconfig.me
    fi
}

function send_telegram_notification() {
    local message="$1"
    local keyboard="$2"

    if [ ! -f "$TELEGRAM_CONF" ]; then
        return 1
    fi
    
    source "$TELEGRAM_CONF" 2>/dev/null

    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
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
    fi
}

# Core Functions
function setup_telegram() {
    echo "--- Konfigurasi Notifikasi Telegram ---"
    read -p "Masukkan Bot Token: " api_key
    read -p "Masukkan Chat ID: " chat_id

    if [ -z "$api_key" ] || [ -z "$chat_id" ]; then
        echo "Token dan Chat ID tidak boleh kosong."
        return 1
    fi

    # Test token
    echo "Testing bot token..."
    if curl -s "https://api.telegram.org/bot${api_key}/getMe" | grep -q '"ok":true'; then
        echo "✓ Token valid"
    else
        echo "❌ Token invalid"
        return 1
    fi

    echo "TELEGRAM_BOT_TOKEN=${api_key}" > "$TELEGRAM_CONF"
    echo "TELEGRAM_CHAT_ID=${chat_id}" >> "$TELEGRAM_CONF"
    chmod 600 "$TELEGRAM_CONF"
    
    # Test message
    send_telegram_notification "✅ ZiVPN Telegram Connected!"
    echo "✓ Konfigurasi berhasil"
    return 0
}

function handle_backup() {
    echo "--- Backup Data ---"

    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo "Telegram belum dikonfigurasi."
        read -p "Setup Telegram sekarang? (y/n): " choice
        if [[ "$choice" == "y" ]]; then
            setup_telegram
            [ $? -ne 0 ] && exit 1
        else
            echo "Backup dibatalkan."
            exit 1
        fi
    fi

    source "$TELEGRAM_CONF" 2>/dev/null

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="/tmp/zivpn_backup_${timestamp}.zip"
    
    echo "Membuat backup..."
    cd "$CONFIG_DIR" && zip "$backup_file" "${BACKUP_FILES[@]}" 2>/dev/null
    
    if [ ! -f "$backup_file" ]; then
        echo "❌ Gagal membuat backup"
        exit 1
    fi

    echo "Mengirim ke Telegram..."
    local response=$(curl -s -F "chat_id=${TELEGRAM_CHAT_ID}" \
        -F "document=@${backup_file}" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument")

    local file_id=$(echo "$response" | grep -o '"file_id":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$file_id" ]; then
        echo "❌ Gagal upload ke Telegram"
        rm -f "$backup_file"
        exit 1
    fi

    # Kirim info backup
    local host=$(get_host)
    local date_now=$(date +"%d %B %Y")
    local total_users=$(wc -l < "${CONFIG_DIR}/users.db" 2>/dev/null || echo "0")
    
    local message="
◇━━━━━━━━━━━━━━◇
   📦 BACKUP ZIVPN
◇━━━━━━━━━━━━━━◇
Host : ${host}
Tanggal : ${date_now}
User : ${total_users}
File ID : ${file_id}
◇━━━━━━━━━━━━━━◇
"
    
    send_telegram_notification "$message"
    rm -f "$backup_file"
    
    echo "✅ Backup berhasil!"
    echo "File ID: ${file_id}"
}

function handle_restore() {
    echo "--- Restore Data ---"

    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo "Telegram belum dikonfigurasi."
        exit 1
    fi

    source "$TELEGRAM_CONF" 2>/dev/null
    
    read -p "Masukkan File ID: " file_id
    if [ -z "$file_id" ]; then
        echo "File ID tidak boleh kosong."
        exit 1
    fi

    read -p "Yakin restore? Data saat ini akan ditimpa. (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Dibatalkan."
        exit 0
    fi

    echo "Mendownload backup..."
    local response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getFile?file_id=${file_id}")
    local file_path=$(echo "$response" | grep -o '"file_path":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$file_path" ]; then
        echo "❌ File tidak ditemukan"
        exit 1
    fi

    local temp_file="/tmp/restore_$(basename "$file_path")"
    curl -s -o "$temp_file" "https://api.telegram.org/file/bot${TELEGRAM_BOT_TOKEN}/${file_path}"
    
    if [ ! -f "$temp_file" ]; then
        echo "❌ Gagal download"
        exit 1
    fi

    echo "Mengekstrak..."
    unzip -o "$temp_file" -d "$CONFIG_DIR" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        systemctl restart zivpn.service
        echo "✅ Restore berhasil!"
        send_telegram_notification "✅ Restore completed!"
    else
        echo "❌ Gagal ekstrak file"
    fi
    
    rm -f "$temp_file"
}

function handle_notification() {
    local type="$1"
    shift
    
    case "$type" in
        "expiry")
            # $2=host $3=ip $4=client $5=isp $6=exp_date
            local message="
◇━━━━━━━━━━━━━━◇
 ⚠️ LICENSE EXPIRED
◇━━━━━━━━━━━━━━◇
IP : $3
Host : $2
Client : $4
ISP : $5
Expired : $6
◇━━━━━━━━━━━━━━◇
"
            local keyboard='{"inline_keyboard":[[{"text":"Perpanjang","url":"https://t.me/bendakerep"}]]}'
            send_telegram_notification "$message" "$keyboard"
            ;;
            
        "renewed")
            # $2=host $3=ip $4=client $5=isp $6=days
            local message="
◇━━━━━━━━━━━━━━◇
 ✅ LICENSE RENEWED
◇━━━━━━━━━━━━━━◇
IP : $3
Host : $2
Client : $4
Sisa : $6 hari
◇━━━━━━━━━━━━━━◇
"
            send_telegram_notification "$message"
            ;;
            
        "api-key")
            # $2=api_key $3=server_ip $4=domain
            local message="
🔑 API Key Generated
Key : $2
Server : $3
Domain : $4
"
            send_telegram_notification "$message"
            ;;
            
        "custom")
            send_telegram_notification "$2"
            ;;
    esac
}

function auto_backup() {
    # Function untuk cron job
    if [ ! -f "$TELEGRAM_CONF" ]; then
        return 1
    fi
    
    source "$TELEGRAM_CONF" 2>/dev/null
    
    local timestamp=$(date +%Y%m%d-%H%M)
    local backup_file="/tmp/auto_backup_${timestamp}.zip"
    
    cd "$CONFIG_DIR" && zip "$backup_file" "${BACKUP_FILES[@]}" 2>/dev/null
    
    if [ -f "$backup_file" ]; then
        curl -s -F "chat_id=${TELEGRAM_CHAT_ID}" \
            -F "document=@${backup_file}" \
            -F "caption=Auto Backup $(date +'%Y-%m-%d %H:%M')" \
            "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" > /dev/null
        rm -f "$backup_file"
    fi
}

# Main
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
    "notify")
        if [ "$2" == "expiry" ] && [ $# -eq 7 ]; then
            handle_notification "expiry" "$3" "$4" "$5" "$6" "$7"
        elif [ "$2" == "renewed" ] && [ $# -eq 6 ]; then
            handle_notification "renewed" "$3" "$4" "$5" "$6"
        elif [ "$2" == "api-key" ] && [ $# -eq 4 ]; then
            handle_notification "api-key" "$3" "$4"
        elif [ "$2" == "custom" ] && [ $# -eq 3 ]; then
            handle_notification "custom" "$3"
        else
            echo "Usage:"
            echo "  $0 notify expiry <host> <ip> <client> <isp> <exp_date>"
            echo "  $0 notify renewed <host> <ip> <client> <isp> <days>"
            echo "  $0 notify api-key <key> <server_ip> <domain>"
            echo "  $0 notify custom <message>"
        fi
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
        echo "ZIVPN Helper - Simple Version"
        echo "Usage: $0 {setup|backup|restore|notify|test|auto-backup}"
        echo ""
        echo "Examples:"
        echo "  $0 setup              # Setup Telegram"
        echo "  $0 backup             # Backup to Telegram"
        echo "  $0 restore            # Restore from Telegram"
        echo "  $0 notify custom 'Hello'  # Send custom message"
        echo "  $0 test               # Test Telegram connection"
        ;;
esac
