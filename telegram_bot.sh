#!/bin/bash
# ============================================
#           TELEGRAM BOT FOR ZIVPN
#                 BY: PONDOK VPN
#         Telegram: @bendakerep
# ============================================

# CONFIGURATION
TELEGRAM_CONF="/etc/zivpn/telegram.conf"
USER_DB="/etc/zivpn/users.db"
DEVICE_DB="/etc/zivpn/devices.db"
LOCKED_DB="/etc/zivpn/locked.db"
CONFIG_JSON="/etc/zivpn/config.json"
LOG_FILE="/var/log/zivpn_bot.log"

# Load Telegram config
if [ ! -f "$TELEGRAM_CONF" ]; then
    echo "Telegram config not found!" >> "$LOG_FILE"
    exit 1
fi

source "$TELEGRAM_CONF"

# --- Logging Function ---
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# --- Send Telegram Message ---
send_telegram() {
    local chat_id="$1"
    local message="$2"
    local parse_mode="${3:-Markdown}"
    
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${chat_id}" \
        -d "text=${message}" \
        -d "parse_mode=${parse_mode}" \
        -d "disable_web_page_preview=true" > /dev/null
}

# --- Send Telegram with Keyboard ---
send_telegram_keyboard() {
    local chat_id="$1"
    local message="$2"
    local keyboard="$3"
    
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${chat_id}" \
        -d "text=${message}" \
        -d "parse_mode=Markdown" \
        -d "reply_markup={\"inline_keyboard\":${keyboard},\"resize_keyboard\":true}" > /dev/null
}

# --- Get Host Info ---
get_host_info() {
    local CERT_CN
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    local HOST
    
    if [ "$CERT_CN" == "zivpn" ] || [ -z "$CERT_CN" ]; then
        HOST=$(curl -s ifconfig.me)
    else
        HOST=$CERT_CN
    fi
    
    echo "$HOST"
}

# --- Get System Info ---
get_system_info() {
    local os_info=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "Unknown OS")
    local ip_info=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown IP")
    local isp_info=$(curl -s ipinfo.io/org 2>/dev/null | head -1 || echo "Unknown ISP")
    
    echo "┃ 🔹 *OS:* \`${os_info}\`
┃ 🔹 *IP:* \`${ip_info}\`
┃ 🔹 *ISP:* \`${isp_info}\`"
}

# --- Create Account via Bot ---
create_account_via_bot() {
    local chat_id="$1"
    local client_name="$2"
    local password="$3"
    local days="$4"
    local max_devices="${5:-2}"
    
    if [ -z "$password" ] || [ -z "$days" ]; then
        send_telegram "$chat_id" "┏━━━━━━━━━━━━━━━━━━━━┓
┃      ❌ ERROR      ┃
┗━━━━━━━━━━━━━━━━━━━━┛
┃
┃ Password dan masa aktif
┃ harus diisi!"
        return
    fi
    
    if grep -q "^${password}:" "$USER_DB"; then
        send_telegram "$chat_id" "┏━━━━━━━━━━━━━━━━━━━━┓
┃      ❌ ERROR      ┃
┗━━━━━━━━━━━━━━━━━━━━┛
┃
┃ Password '${password}'
┃ sudah ada!"
        return
    fi
    
    local expiry_date
    expiry_date=$(date -d "+$days days" +%s)
    echo "${password}:${expiry_date}:${max_devices}:${client_name}" >> "$USER_DB"
    
    # Add to config.json
    jq --arg pass "$password" '.auth.config += [$pass]' "$CONFIG_JSON" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_JSON"
    
    # Restart service
    systemctl restart zivpn.service
    
    local HOST
    HOST=$(get_host_info)
    local EXPIRE_FORMATTED
    EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y")
    
    local message="┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃     ✅ AKUN BARU DIBUAT     ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃        📋 DETAIL AKUN         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ 🔸 *Nama:* \`${client_name}\`
┃ 🔸 *Host:* \`${HOST}\`
┃ 🔸 *Password:* \`${password}\`
┃ 🔸 *Expire:* ${EXPIRE_FORMATTED}
┃ 🔸 *Masa Aktif:* ${days} hari
┃ 🔸 *Limit Device:* ${max_devices} device
┃
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃        📱 PONDOK VPN         ┃
┃        ☎️ @bendakerep        ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
    
    send_telegram "$chat_id" "$message"
    log_message "Account created via bot: $password for $days days"
}

# --- Delete Account via Bot ---
delete_account_via_bot() {
    local chat_id="$1"
    local account_number="$2"
    
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        send_telegram "$chat_id" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃       ❌ ERROR           ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ Tidak ada akun yang ditemukan!"
        return
    fi
    
    local count=0
    local selected_password=""
    
    while IFS=':' read -r password expiry_date max_devices client_name; do
        if [[ -n "$password" ]]; then
            count=$((count + 1))
            if [ $count -eq "$account_number" ]; then
                selected_password=$password
                break
            fi
        fi
    done < "$USER_DB"
    
    if [ -z "$selected_password" ]; then
        send_telegram "$chat_id" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃       ❌ ERROR           ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ Akun tidak ditemukan!"
        return
    fi
    
    # Delete from databases
    sed -i "/^${selected_password}:/d" "$USER_DB"
    sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
    
    # Delete from config.json
    jq --arg pass "$selected_password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_JSON" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_JSON"
    
    # Restart service
    systemctl restart zivpn.service
    
    send_telegram "$chat_id" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃       ✅ AKUN DIHAPUS        ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃        📋 DETAIL AKUN         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ 🔸 *Password:* \`${selected_password}\`
┃ 🔸 *Status:* Berhasil dihapus
┃
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃        📱 PONDOK VPN         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
    
    log_message "Account deleted via bot: $selected_password"
}

# --- List Accounts via Bot ---
list_accounts_via_bot() {
    local chat_id="$1"
    
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        send_telegram "$chat_id" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃       📋 DAFTAR AKUN         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ ❌ Tidak ada akun yang ditemukan."
        return
    fi
    
    local message="┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃       📋 DAFTAR AKUN AKTIF   ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n\n"
    local count=0
    local current_date=$(date +%s)
    
    while IFS=':' read -r password expiry_date max_devices client_name; do
        if [[ -n "$password" ]]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - current_date))
            local remaining_days=$((remaining_seconds / 86400))
            
            if [ $remaining_days -gt 0 ]; then
                message+="┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃        AKUN #${count}           ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ 🔸 *Nama:* \`${client_name}\`
┃ 🔸 *Password:* \`${password}\`
┃ 🔸 *Device:* ${max_devices} device
┃ 🔸 *Sisa:* ${remaining_days} hari
┃\n"
            else
                message+="┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃        AKUN #${count}           ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ 🔸 *Nama:* \`${client_name}\`
┃ 🔸 *Password:* \`${password}\`
┃ 🔸 *Device:* ${max_devices} device
┃ 🔸 *Status:* ⛔ EXPIRED
┃\n"
            fi
        fi
    done < "$USER_DB"
    
    message+="┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃          📊 STATISTIK         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ Total: ${count} akun
┃
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃        📱 PONDOK VPN         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
    
    send_telegram "$chat_id" "$message"
}

# --- Show Main Menu in Telegram ---
show_main_menu() {
    local chat_id="$1"
    
    local keyboard='[
        [{"text":"📋 List Akun","callback_data":"list_accounts"}],
        [{"text":"➕ Buat Akun","callback_data":"create_account"}],
        [{"text":"🗑️ Hapus Akun","callback_data":"delete_account"}],
        [{"text":"🔄 Renew Akun","callback_data":"renew_account"}],
        [{"text":"ℹ️ System Info","callback_data":"system_info"}]
    ]'
    
    local HOST
    HOST=$(get_host_info)
    local system_info
    system_info=$(get_system_info)
    
    local message="┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃   🤖 ZIVPN TELEGRAM BOT    ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃         🌐 SERVER INFO        ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
${system_info}
┃ 🔹 *Host:* \`${HOST}\`
┃
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃         📱 PONDOK VPN         ┃
┃         ☎️ @bendakerep        ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Pilih menu di bawah:"
    
    send_telegram_keyboard "$chat_id" "$message" "$keyboard"
}

# --- Handle Callback Queries ---
handle_callback_query() {
    local callback_data="$1"
    local chat_id="$2"
    local message_id="$3"
    
    case "$callback_data" in
        "list_accounts")
            list_accounts_via_bot "$chat_id"
            ;;
        "create_account")
            send_telegram "$chat_id" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃       ➕ BUAT AKUN BARU      ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ Gunakan format:
┃ \`/create Nama Password Hari Limit\`
┃
┃ Contoh:
┃ \`/create JohnDoe pass123 30 2\`"
            ;;
        "delete_account")
            send_telegram "$chat_id" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃       🗑️ HAPUS AKUN         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ Gunakan format:
┃ \`/delete nomor_akun\`
┃
┃ Gunakan /list untuk melihat
┃ daftar akun."
            ;;
        "renew_account")
            send_telegram "$chat_id" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃       🔄 RENEW AKUN         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ Gunakan format:
┃ \`/renew nomor_akun hari_tambahan\`
┃
┃ Gunakan /list untuk melihat
┃ daftar akun."
            ;;
        "system_info")
            local HOST
            HOST=$(get_host_info)
            local system_info
            system_info=$(get_system_info)
            
            local message="┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃       ℹ️ SYSTEM INFO         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃         📊 INFORMASI          ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
${system_info}
┃ 🔹 *Host:* \`${HOST}\`
┃ 🔹 *Status:* ✅ Online
┃ 🔹 *Service:* 🟢 Running
┃
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃         📱 PONDOK VPN         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
            
            send_telegram "$chat_id" "$message"
            ;;
        "main_menu")
            show_main_menu "$chat_id"
            ;;
    esac
}

# --- Handle Text Commands ---
handle_text_command() {
    local chat_id="$1"
    local text="$2"
    
    # Convert to lowercase for case-insensitive matching
    local command=$(echo "$text" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
    
    case "$command" in
        "/start"|"/menu")
            show_main_menu "$chat_id"
            ;;
        "/list")
            list_accounts_via_bot "$chat_id"
            ;;
        "/create"*)
            # Format: /create Nama Password Hari Limit
            local client_name=$(echo "$text" | awk '{print $2}')
            local password=$(echo "$text" | awk '{print $3}')
            local days=$(echo "$text" | awk '{print $4}')
            local max_devices=$(echo "$text" | awk '{print $5}')
            
            if [ -z "$max_devices" ]; then
                max_devices=2
            fi
            
            create_account_via_bot "$chat_id" "$client_name" "$password" "$days" "$max_devices"
            ;;
        "/delete"*)
            # Format: /delete nomor_akun
            local account_number=$(echo "$text" | awk '{print $2}')
            delete_account_via_bot "$chat_id" "$account_number"
            ;;
        "/renew"*)
            # Format: /renew nomor_akun hari_tambahan
            local account_number=$(echo "$text" | awk '{print $2}')
            local days=$(echo "$text" | awk '{print $3}')
            
            # This is a placeholder - you need to implement renew logic
            send_telegram "$chat_id" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃       🔄 RENEW AKUN         ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ Fitur renew via bot sedang dalam
┃ pengembangan.
┃
┃ Silakan gunakan menu di VPS
┃ untuk renew akun."
            ;;
        "/help")
            send_telegram "$chat_id" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃       🤖 ZIVPN BOT HELP      ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃      📜 PERINTAH TERSEDIA     ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ /menu  - Tampilkan menu utama
┃ /list  - Tampilkan daftar akun
┃ /create - Buat akun baru
┃ /delete - Hapus akun
┃ /renew  - Renew akun
┃ /help  - Tampilkan bantuan
┃
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃      📝 FORMAT PERINTAH       ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ • Buat akun:
┃   \`/create Nama Password Hari Limit\`
┃
┃ • Hapus akun:
┃   \`/delete nomor_akun\`
┃
┃ • Renew akun:
┃   \`/renew nomor_akun hari_tambahan\`
┃
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃        📱 PONDOK VPN         ┃
┃        ☎️ @bendakerep        ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
            ;;
        *)
            send_telegram "$chat_id" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃       ❌ PERINTAH ERROR       ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ Perintah tidak dikenali!
┃
┃ Gunakan /help untuk melihat
┃ daftar perintah yang tersedia."
            ;;
    esac
}

# --- Main Bot Loop ---
main_bot_loop() {
    log_message "Starting Telegram Bot..."
    
    # Get last update ID
    local last_update_id=0
    
    while true; do
        # Get updates from Telegram
        local updates=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates" \
            -d "offset=$((last_update_id + 1))" \
            -d "timeout=30")
        
        # Parse updates
        local update_count=$(echo "$updates" | jq '.result | length')
        
        for ((i=0; i<update_count; i++)); do
            local update=$(echo "$updates" | jq ".result[$i]")
            last_update_id=$(echo "$update" | jq '.update_id')
            
            # Check for callback query
            local callback_query=$(echo "$update" | jq -r '.callback_query // empty')
            if [ -n "$callback_query" ]; then
                local callback_data=$(echo "$callback_query" | jq -r '.data')
                local chat_id=$(echo "$callback_query" | jq -r '.message.chat.id')
                local message_id=$(echo "$callback_query" | jq -r '.message.message_id')
                
                handle_callback_query "$callback_data" "$chat_id" "$message_id"
                continue
            fi
            
            # Check for text message
            local message=$(echo "$update" | jq -r '.message // empty')
            if [ -n "$message" ]; then
                local chat_id=$(echo "$message" | jq -r '.chat.id')
                local text=$(echo "$message" | jq -r '.text // empty')
                
                if [ -n "$text" ]; then
                    handle_text_command "$chat_id" "$text"
                fi
            fi
        done
        
        sleep 1
    done
}

# --- Run as service or command ---
case "$1" in
    "start")
        main_bot_loop
        ;;
    "send")
        send_telegram "$TELEGRAM_CHAT_ID" "$2"
        ;;
    "test")
        echo "Testing Telegram Bot..."
        send_telegram "$TELEGRAM_CHAT_ID" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃      🤖 TEST MESSAGE        ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
┃
┃ ✅ Bot Telegram ZIVPN aktif
┃    dan berjalan!
┃
┃ 🕐 $(date '+%Y-%m-%d %H:%M:%S')
┃
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃        📱 PONDOK VPN         ┃
┃        ☎️ @bendakerep        ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
        ;;
    *)
        echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
        echo "┃      ZIVPN BOT USAGE          ┃"
        echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
        echo ""
        echo "Usage: $0 {start|send|test}"
        echo ""
        echo "  start - Start bot in background"
        echo "  send <message> - Send message"
        echo "  test - Send test message"
        echo ""
        echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
        echo "┃        PONDOK VPN             ┃"
        echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
        exit 1
        ;;
esac
