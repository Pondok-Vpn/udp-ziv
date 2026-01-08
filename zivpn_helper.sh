#!/bin/bash
# zivpn_helper.sh - Backup/Restore sederhana

CONFIG_DIR="/etc/zivpn"
TELEGRAM_CONF="${CONFIG_DIR}/telegram.conf"

# Fungsi sederhana tanpa dependencies kompleks
function setup_telegram() {
    echo "=== Setup Telegram Notifications ==="
    
    read -p "Masukkan Bot Token: " bot_token
    read -p "Masukkan Chat ID: " chat_id
    
    if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
        echo "Token dan Chat ID tidak boleh kosong!"
        return 1
    fi
    
    echo "TELEGRAM_BOT_TOKEN=$bot_token" > "$TELEGRAM_CONF"
    echo "TELEGRAM_CHAT_ID=$chat_id" >> "$TELEGRAM_CONF"
    
    echo "✅ Telegram configuration saved"
    return 0
}

function backup_simple() {
    echo "=== Backup ZiVPN Configuration ==="
    
    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo "Telegram belum diatur. Setup dulu:"
        setup_telegram
    fi
    
    source "$TELEGRAM_CONF" 2>/dev/null
    
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "❌ Telegram config tidak valid"
        return 1
    fi
    
    # Buat backup lokal
    BACKUP_FILE="/tmp/zivpn_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$BACKUP_FILE" -C /etc zivpn/ 2>/dev/null
    
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "❌ Gagal membuat backup"
        return 1
    fi
    
    echo "📦 Backup created: $(basename $BACKUP_FILE)"
    
    # Kirim ke Telegram (sederhana)
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=📦 ZIVPN Backup
📅 $(date '+%Y-%m-%d %H:%M:%S')
💾 Backup berhasil dibuat" \
        --form "document=@$BACKUP_FILE" \
        > /dev/null 2>&1
    
    echo "✅ Backup dikirim ke Telegram"
    rm -f "$BACKUP_FILE"
}

function restore_simple() {
    echo "=== Restore ZiVPN Configuration ==="
    
    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo "❌ Telegram belum diatur"
        return 1
    fi
    
    source "$TELEGRAM_CONF"
    
    read -p "Masukkan File ID dari Telegram: " file_id
    
    if [ -z "$file_id" ]; then
        echo "❌ File ID tidak boleh kosong"
        return 1
    fi
    
    echo "📥 Mendownload backup..."
    
    # Get file path
    response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getFile?file_id=${file_id}")
    file_path=$(echo "$response" | grep -o '"file_path":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$file_path" ]; then
        echo "❌ File tidak ditemukan"
        return 1
    fi
    
    # Download file
    BACKUP_FILE="/tmp/zivpn_restore.tar.gz"
    curl -s -o "$BACKUP_FILE" "https://api.telegram.org/file/bot${TELEGRAM_BOT_TOKEN}/${file_path}"
    
    if [ ! -s "$BACKUP_FILE" ]; then
        echo "❌ Gagal mendownload file"
        return 1
    fi
    
    # Restore
    echo "🔄 Restoring configuration..."
    tar -xzf "$BACKUP_FILE" -C / --keep-old-files 2>/dev/null
    
    # Restart service
    systemctl restart zivpn.service
    
    echo "✅ Restore berhasil"
    rm -f "$BACKUP_FILE"
}

function send_notification() {
    local message="$1"
    
    if [ ! -f "$TELEGRAM_CONF" ]; then
        return 1
    fi
    
    source "$TELEGRAM_CONF"
    
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=$message" \
        > /dev/null 2>&1
}

# Main menu
case "$1" in
    "setup")
        setup_telegram
        ;;
    "backup")
        backup_simple
        ;;
    "restore")
        restore_simple
        ;;
    "notify")
        send_notification "$2"
        ;;
    *)
        echo "Usage:"
        echo "  $0 setup        - Setup Telegram"
        echo "  $0 backup       - Backup to Telegram"
        echo "  $0 restore      - Restore from Telegram"
        echo "  $0 notify 'msg' - Send notification"
        ;;
esac
