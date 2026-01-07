#!/bin/bash
# =============================
# UDP ZIVPN MODULE MANAGER
# BY: PONDOK VPN
# Telegram: @bendakerep
# =============================

# WARNA BIRU TELOR ASIN
BLUE='\033[0;94m'      # Biru utama
LIGHT_BLUE='\033[1;94m' # Biru terang
CYAN='\033[0;96m'      # Cyan
LIGHT_CYAN='\033[1;96m' # Cyan terang
WHITE='\033[1;97m'     # Putih
GREEN='\033[0;92m'     # Hijau
LIGHT_GREEN='\033[1;92m' # Hijau terang
YELLOW='\033[0;93m'    # Kuning (Gold)
LIGHT_YELLOW='\033[1;93m' # Kuning terang
RED='\033[0;91m'       # Merah
LIGHT_RED='\033[1;91m' # Merah terang
PURPLE='\033[0;95m'    # Ungu
LIGHT_PURPLE='\033[1;95m' # Ungu terang
GOLD='\033[0;93m'      # Gold untuk label
NC='\033[0m'           # No Color

# VARIABEL
USER_DB="/etc/zivpn/users.db"
DEVICE_DB="/etc/zivpn/devices.db"
CONFIG_FILE="/etc/zivpn/config.json"
LOCKED_DB="/etc/zivpn/locked.db"

# ================================================
# --- Utility Functions ---
function restart_zivpn() {
    echo "Restarting ZIVPN service..."
    systemctl restart zivpn.service
    echo "Service restarted."
}

# --- Check if Account is Locked ---
function is_account_locked() {
    local password="$1"
    if [ -f "$LOCKED_DB" ] && grep -q "^${password}:" "$LOCKED_DB"; then
        return 0  # Account is locked
    fi
    return 1  # Account is not locked
}

# --- Lock Account ---
function lock_account() {
    local password="$1"
    local reason="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Remove from main users.db
    sed -i "/^${password}:/d" "$USER_DB"
    
    # Add to locked database
    echo "${password}:${timestamp}:${reason}" >> "$LOCKED_DB"
    
    # Remove from config.json
    jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE"
    
    # Remove from device DB
    sed -i "/^${password}:/d" "$DEVICE_DB" 2>/dev/null
}

# --- Unlock Account (via renew) ---
function unlock_account() {
    local password="$1"
    if [ -f "$LOCKED_DB" ]; then
        sed -i "/^${password}:/d" "$LOCKED_DB"
    fi
}

# --- Device Limit Management Functions ---
function check_device_limit() {
    local username="$1"
    local max_devices="$2"
    local current_ip="$3"
    
    if [ ! -f "$DEVICE_DB" ]; then
        touch "$DEVICE_DB"
    fi
    
    local device_count=$(grep -c "^${username}:" "$DEVICE_DB" 2>/dev/null || echo "0")
    
    if [ "$device_count" -ge "$max_devices" ]; then
        if ! grep -q "^${username}:${current_ip}" "$DEVICE_DB"; then
            # Account exceeded limit, lock it
            lock_account "$username" "Melebihi limit IP/device (max: $max_devices)"
            return 1
        fi
    fi
    
    return 0
}

function register_device() {
    local username="$1"
    local ip_address="$2"
    
    sed -i "/^${username}:${ip_address}/d" "$DEVICE_DB" 2>/dev/null
    
    local timestamp=$(date +%s)
    echo "${username}:${ip_address}:${timestamp}" >> "$DEVICE_DB"
}

# --- Domain Management Functions ---
function change_domain() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║             ${WHITE}GANTI DOMAIN${BLUE}                ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    local current_domain=""
    if [ -f "/etc/zivpn/zivpn.crt" ]; then
        current_domain=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    fi
    
    if [ -n "$current_domain" ]; then
        echo -e "${LIGHT_BLUE}Domain saat ini: ${WHITE}${current_domain}${NC}"
        echo ""
    fi
    
    read -p "Masukkan domain baru (contoh: vpn.pondok.com): " domain
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain tidak boleh kosong!${NC}"
        sleep 2
        return
    fi
    
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}Format domain tidak valid!${NC}"
        sleep 2
        return
    fi
    
    echo ""
    echo -e "${LIGHT_BLUE}Membuat sertifikat SSL untuk domain: ${WHITE}${domain}${NC}"
    echo -e "${YELLOW}Proses ini mungkin memakan waktu beberapa detik...${NC}"
    
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=PONDOK VPN/OU=VPN Service/CN=${domain}" \
        -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Sertifikat SSL berhasil dibuat untuk ${domain}${NC}"
        
        if [ -f "/etc/zivpn/config.json" ]; then
            cp /etc/zivpn/config.json /etc/zivpn/config.json.backup
            
            jq --arg domain "$domain" '.tls.sni = $domain' /etc/zivpn/config.json > /tmp/config.json.tmp
            if [ $? -eq 0 ]; then
                mv /tmp/config.json.tmp /etc/zivpn/config.json
                
                echo -e "${LIGHT_GREEN}Domain berhasil diganti ke ${domain}${NC}"
                restart_zivpn
                
                echo ""
                echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
                echo -e "${BLUE}║        ${WHITE}✅ DOMAIN BERHASIL DIGANTI${BLUE}      ║${NC}"
                echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
                echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Domain Lama: ${WHITE}${current_domain:-"Tidak ada"}${BLUE}  ║${NC}"
                echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Domain Baru: ${WHITE}${domain}${BLUE}               ║${NC}"
                echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Status: ${WHITE}Aktif${BLUE}                       ║${NC}"
                echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 SSL: ${WHITE}Valid (365 hari)${BLUE}              ║${NC}"
                echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
                echo -e "${BLUE}║   ${YELLOW}Service ZIVPN telah di-restart${BLUE}     ║${NC}"
                echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
            else
                echo -e "${RED}Gagal update config.json!${NC}"
                cp /etc/zivpn/config.json.backup /etc/zivpn/config.json
            fi
        fi
    else
        echo -e "${RED}Gagal membuat sertifikat SSL!${NC}"
    fi
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

# --- Telegram Bot Management Menu ---
function telegram_bot_menu() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║            ${WHITE}TELEGRAM BOT MANAGER${BLUE}         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}1) ${CYAN}ADD BOTTOKEN${LIGHT_BLUE}                        ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}2) ${CYAN}CHANGE BOTTOKEN${LIGHT_BLUE}                     ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}3) ${CYAN}BACKUP/RESTART via Telegram${LIGHT_BLUE}         ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}0) ${CYAN}KEMBALI KE MENU${LIGHT_BLUE}                     ║${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
    
    read -p "Pilih menu [0-3]: " choice

    case $choice in
        1) setup_telegram_bot ;;
        2) change_bot_token ;;
        3) telegram_backup_restart ;;
        0) return ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1 ;;
    esac
}

# --- Setup Telegram Bot ---
function setup_telegram_bot() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          ${WHITE}ADD BOT TOKEN${BLUE}               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Masukkan Bot Token Telegram: " bot_token
    read -p "Masukkan Chat ID Telegram: " chat_id
    
    if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
        echo -e "${RED}Token dan Chat ID tidak boleh kosong!${NC}"
        sleep 2
        return
    fi
    
    # Validasi format token
    if [[ ! "$bot_token" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Format Token tidak valid!${NC}"
        sleep 2
        return
    fi
    
    echo "TELEGRAM_BOT_TOKEN=${bot_token}" > /etc/zivpn/telegram.conf
    echo "TELEGRAM_CHAT_ID=${chat_id}" >> /etc/zivpn/telegram.conf
    echo "TELEGRAM_ENABLED=true" >> /etc/zivpn/telegram.conf
    
    echo -e "${GREEN}Bot Telegram berhasil diatur!${NC}"
    echo -e "${LIGHT_BLUE}Token: ${WHITE}${bot_token:0:15}...${NC}"
    echo -e "${LIGHT_BLUE}Chat ID: ${WHITE}${chat_id}${NC}"
    
    # Test send message
    echo ""
    echo -e "${YELLOW}Menguji pengiriman pesan...${NC}"
    if command -v curl &> /dev/null; then
        response=$(curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
            -d "chat_id=${chat_id}" \
            -d "text=✅ Bot Telegram ZIVPN berhasil diatur!")
        
        if [[ $response == *"ok\":true"* ]]; then
            echo -e "${GREEN}Pesan test berhasil dikirim!${NC}"
        else
            echo -e "${YELLOW}Pesan test gagal dikirim (mungkin Chat ID salah)${NC}"
        fi
    fi
    
    sleep 3
}

# --- Change Bot Token ---
function change_bot_token() {
    clear
    if [ ! -f "/etc/zivpn/telegram.conf" ]; then
        echo -e "${RED}Bot Telegram belum diatur!${NC}"
        echo -e "${YELLOW}Silakan gunakan menu 'ADD BOTTOKEN' terlebih dahulu${NC}"
        sleep 2
        return
    fi
    
    source /etc/zivpn/telegram.conf 2>/dev/null
    echo -e "${LIGHT_BLUE}Token saat ini: ${WHITE}${TELEGRAM_BOT_TOKEN:0:15}...${NC}"
    echo -e "${LIGHT_BLUE}Chat ID saat ini: ${WHITE}${TELEGRAM_CHAT_ID}${NC}"
    echo ""
    
    read -p "Masukkan Bot Token baru: " new_token
    read -p "Masukkan Chat ID baru: " new_chat_id
    
    if [ -z "$new_token" ] || [ -z "$new_chat_id" ]; then
        echo -e "${RED}Token dan Chat ID tidak boleh kosong!${NC}"
        sleep 2
        return
    fi
    
    if [[ ! "$new_token" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Format Token tidak valid!${NC}"
        sleep 2
        return
    fi
    
    echo "TELEGRAM_BOT_TOKEN=${new_token}" > /etc/zivpn/telegram.conf
    echo "TELEGRAM_CHAT_ID=${new_chat_id}" >> /etc/zivpn/telegram.conf
    echo "TELEGRAM_ENABLED=true" >> /etc/zivpn/telegram.conf
    
    echo -e "${GREEN}Token berhasil diubah!${NC}"
    
    # Test new token
    echo ""
    echo -e "${YELLOW}Menguji token baru...${NC}"
    if command -v curl &> /dev/null; then
        response=$(curl -s -X POST "https://api.telegram.org/bot${new_token}/getMe")
        if [[ $response == *"ok\":true"* ]]; then
            echo -e "${GREEN}Token valid!${NC}"
        else
            echo -e "${YELLOW}Token mungkin tidak valid${NC}"
        fi
    fi
    
    sleep 2
}

# --- Telegram Backup/Restart ---
function telegram_backup_restart() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   ${WHITE}BACKUP/RESTART TO BOT${BLUE}       ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ ! -f "/etc/zivpn/telegram.conf" ]; then
        echo -e "${RED}Bot Telegram belum diatur!${NC}"
        echo -e "${YELLOW}Silakan atur bot token terlebih dahulu${NC}"
        sleep 2
        return
    fi
    
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}1) ${CYAN}Backup Data & Kirim ke Telegram${LIGHT_BLUE}    ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}2) ${CYAN}Restart Service & Notifikasi${LIGHT_BLUE}       ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}0) ${CYAN}Kembali ke Menu${LIGHT_BLUE}                    ║${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Pilih menu [0-2]: " choice
    
    case $choice in
        1)
            echo "Membuat backup dan mengirim ke Telegram..."
            mkdir -p /backup/zivpn
            cp -r /etc/zivpn /backup/zivpn/
            tar -czf /backup/zivpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz /backup/zivpn
            
            source /etc/zivpn/telegram.conf 2>/dev/null
            if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
                curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                    -d "chat_id=${TELEGRAM_CHAT_ID}" \
                    -d "text=✅ Backup berhasil dibuat! 
📁 File: zivpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz
📅 Tanggal: $(date '+%d %B %Y %H:%M:%S')
📱 PONDOK VPN" \
                    -d "parse_mode=Markdown"
            fi
            
            echo -e "${GREEN}Backup berhasil dibuat dan notifikasi dikirim!${NC}"
            sleep 2
            ;;
        2)
            echo "Merestart service dan mengirim notifikasi..."
            restart_zivpn
            
            source /etc/zivpn/telegram.conf 2>/dev/null
            if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
                curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                    -d "chat_id=${TELEGRAM_CHAT_ID}" \
                    -d "text=🔄 Service ZIVPN telah di-restart!
✅ Service aktif dan berjalan
📅 $(date '+%d %B %Y %H:%M:%S')
📱 PONDOK VPN" \
                    -d "parse_mode=Markdown"
            fi
            
            echo -e "${GREEN}Service berhasil di-restart dan notifikasi dikirim!${NC}"
            sleep 2
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid!${NC}"
            sleep 1
            ;;
    esac
}

# --- Create Account (Regular) ---
function create_regular_account() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       ${WHITE}BUAT AKUN PREMIUM${BLUE}             ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Masukkan nama anda: " client_name
    if [ -z "$client_name" ]; then
        echo -e "${RED}Nama tidak boleh kosong.${NC}"
        return
    fi

    read -p "Masukkan password: " password
    if [ -z "$password" ]; then
        echo -e "${RED}Password tidak boleh kosong.${NC}"
        return
    fi

    read -p "Masukkan masa aktif (hari): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Jumlah hari tidak valid.${NC}"
        return
    fi

    read -p "Masukkan limit IP/device (default: 2): " max_devices
    if [ -z "$max_devices" ]; then
        max_devices=2
    elif ! [[ "$max_devices" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Jumlah device tidak valid, menggunakan default: 2${NC}"
        max_devices=2
    fi

    if grep -q "^${password}:" "$USER_DB"; then
        echo -e "${YELLOW}Password '${password}' sudah ada.${NC}"
        return
    fi

    local expiry_date
    expiry_date=$(date -d "+$days days" +%s)
    echo "${password}:${expiry_date}:${max_devices}:${client_name}" >> "$USER_DB"
    
    jq --arg pass "$password" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    
    local CERT_CN
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    local HOST
    if [ "$CERT_CN" == "zivpn" ]; then
        HOST=$(curl -s ifconfig.me)
    else
        HOST=$CERT_CN
    fi

    local EXPIRE_FORMATTED
    EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y")
    
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        ${WHITE}✅ AKUN BERHASIL DIBUAT${BLUE}        ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Nama: ${WHITE}$client_name${BLUE}               '${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Host: ${WHITE}$HOST${BLUE}                   '${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Password: ${WHITE}$password${BLUE}            '${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Expire: ${WHITE}$EXPIRE_FORMATTED${BLUE}      '${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Masa Aktif: ${WHITE}$days hari${BLUE}         '${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Limit IP/Device: ${WHITE}$max_devices${BLUE}       '${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║   ${YELLOW}⚠️  PERHATIAN:${BLUE}                        ║${NC}"
    echo -e "${BLUE}║   ${WHITE}Akun akan di-lock jika melebihi${BLUE}         ║${NC}"
    echo -e "${BLUE}║   ${WHITE}$max_devices IP/Device yang terdaftar${BLUE}  ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║   ${LIGHT_CYAN}Terima kasih sudah order!${BLUE}              ║${NC}"
    echo -e "${BLUE}║   ${YELLOW}PONDOK VPN${BLUE}                             ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    
    restart_zivpn
    read -p "Tekan Enter untuk kembali ke menu..."
}

# --- Create Trial Account ---
function create_trial_account() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        ${WHITE}BUAT AKUN TRIAL${BLUE}              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Masukkan nama anda: " client_name
    if [ -z "$client_name" ]; then
        echo -e "${RED}Nama tidak boleh kosong.${NC}"
        return
    fi

    read -p "Masukkan masa aktif (menit): " minutes
    if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Jumlah menit tidak valid.${NC}"
        return
    fi

    local password="trial$(shuf -i 10000-99999 -n 1)"
    local max_devices=1  # Trial hanya 1 device

    local expiry_date
    expiry_date=$(date -d "+$minutes minutes" +%s)
    echo "${password}:${expiry_date}:${max_devices}:${client_name}" >> "$USER_DB"
    
    jq --arg pass "$password" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    
    local CERT_CN
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    local HOST
    if [ "$CERT_CN" == "zivpn" ]; then
        HOST=$(curl -s ifconfig.me)
    else
        HOST=$CERT_CN
    fi

    local EXPIRE_FORMATTED
    EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y %H:%M:%S")
    
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    ${WHITE}✅ AKUN TRIAL BERHASIL${BLUE}       ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Nama: ${WHITE}$client_name${BLUE}               ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Host: ${WHITE}$HOST${BLUE}                    ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Password: ${WHITE}$password${BLUE}            ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Expire: ${WHITE}$EXPIRE_FORMATTED${BLUE}      ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Limit IP/Device: ${WHITE}$max_devices${BLUE}       ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║   ${YELLOW}⚠️  AKUN TRIAL:${BLUE}                            ║${NC}"
    echo -e "${BLUE}║   ${WHITE}Hanya 1 device yang diperbolehkan${BLUE}        ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║   ${LIGHT_CYAN}Terima kasih sudah mencoba!${BLUE}          ║${NC}"
    echo -e "${BLUE}║   ${YELLOW}PONDOK VPN${BLUE}                            ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    
    restart_zivpn
    read -p "Tekan Enter untuk kembali ke menu..."
}

# --- Create Account Menu ---
function create_account() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║             ${WHITE}BUAT AKUN ZIVPN${BLUE}             ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}║     ${WHITE}1) ${CYAN}BUAT AKUN ZIVPN${LIGHT_BLUE}                  ║${NC}"
    echo -e "${LIGHT_BLUE}║     ${WHITE}2) ${CYAN}BUAT AKUN TRIAL${LIGHT_BLUE}                  ║${NC}"
    echo -e "${LIGHT_BLUE}║     ${WHITE}0) ${CYAN}KEMBALI KE MENU${LIGHT_BLUE}                  ║${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
    
    read -p "Pilih menu [0-2]: " choice

    case $choice in
        1) create_regular_account ;;
        2) create_trial_account ;;
        0) return ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1 ;;
    esac
}

# --- Delete Account ---
function delete_account() {
    clear
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${WHITE}HAPUS AKUN ZIVPN${BLUE}              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Header tanpa penutup kanan
    echo -e "${LIGHT_BLUE}╔═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${LIGHT_BLUE}  ${WHITE}No.  Nama User           Password           Limit   Expired${NC}"
    echo -e "${LIGHT_BLUE}════════════════════════════════════════════════════════════════════════${NC}"
    
    local count=0
    while IFS=':' read -r password expiry_date max_devices client_name; do
        if [[ -n "$password" ]]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - $(date +%s)))
            local remaining_days=$((remaining_seconds / 86400))
            if [ $remaining_days -gt 0 ]; then
                printf "${LIGHT_BLUE}  ${WHITE}%2d. %-18s %-18s %-7s %s hari${NC}\n" "$count" "$client_name" "$password" "$max_devices" "$remaining_days"
            else
                printf "${LIGHT_BLUE}  ${WHITE}%2d. %-18s %-18s %-7s ${RED}Expired${NC}\n" "$count" "$client_name" "$password" "$max_devices"
            fi
        fi
    done < "$USER_DB"
    
    echo -e "${LIGHT_BLUE}════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    read -p "Masukkan nomor akun yang akan dihapus [1-$count]: " account_number
    
    if ! [[ "$account_number" =~ ^[0-9]+$ ]] || [ "$account_number" -lt 1 ] || [ "$account_number" -gt "$count" ]; then
        echo -e "${RED}Nomor akun tidak valid!${NC}"
        sleep 2
        return
    fi
    
    local selected_password=""
    local current=0
    while IFS=':' read -r password expiry_date max_devices client_name; do
        if [[ -n "$password" ]]; then
            current=$((current + 1))
            if [ $current -eq $account_number ]; then
                selected_password=$password
                break
            fi
        fi
    done < "$USER_DB"
    
    if [ -z "$selected_password" ]; then
        echo -e "${RED}Akun tidak ditemukan!${NC}"
        sleep 2
        return
    fi
    
    echo ""
    echo -e "${YELLOW}Apakah Anda yakin ingin menghapus akun:${NC}"
    echo -e "${WHITE}$selected_password${NC}"
    read -p "Konfirmasi (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Penghapusan dibatalkan.${NC}"
        sleep 1
        return
    fi
    
    sed -i "/^${selected_password}:/d" "$USER_DB"
    sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
    
    echo -e "${GREEN}Akun '${selected_password}' berhasil dihapus.${NC}"
    
    jq --arg pass "$selected_password" 'del(.auth.config[] | select(. == $pass))' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    restart_zivpn
    
    sleep 2
}

# --- Renew Account (with unlock capability) ---
function renew_account() {
    clear
    
    # Check for locked accounts
    if [ -f "$LOCKED_DB" ] && [ -s "$LOCKED_DB" ]; then
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║       ${WHITE}AKUN TERKUNCI${BLUE}                 ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        
        # Header tanpa penutup kanan
        echo -e "${LIGHT_BLUE}╔════════════════════════════════════════════════════════${NC}"
        echo -e "${LIGHT_BLUE}  ${WHITE}No.  Password           Alasan Lock${NC}"
        echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════${NC}"
        
        local locked_count=0
        while IFS=':' read -r password timestamp reason; do
            if [[ -n "$password" ]]; then
                locked_count=$((locked_count + 1))
                printf "${LIGHT_BLUE}  ${WHITE}%2d. %-18s %s${NC}\n" "$locked_count" "$password" "$reason"
            fi
        done < "$LOCKED_DB"
        
        echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════${NC}"
        echo ""
        
        if [ $locked_count -gt 0 ]; then
            echo -e "${YELLOW}Ada akun yang terkunci. Renew akan membuka kunci.${NC}"
            echo ""
        fi
    fi
    
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${WHITE}RENEW AKUN ZIVPN${BLUE}               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Header tanpa penutup kanan dengan warna berbeda
    echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════════${NC}"
    echo -e "${LIGHT_BLUE}  ${WHITE}No.  ${LIGHT_CYAN}Nama User${WHITE}           ${LIGHT_GREEN}Password${WHITE}           ${YELLOW}Limit${WHITE}   ${LIGHT_PURPLE}Expired${NC}"
    echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════════${NC}"
    
    local count=0
    while IFS=':' read -r password expiry_date max_devices client_name; do
        if [[ -n "$password" ]]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - $(date +%s)))
            local remaining_days=$((remaining_seconds / 86400))
            if [ $remaining_days -gt 0 ]; then
                printf "${LIGHT_BLUE}  ${WHITE}%2d. ${LIGHT_CYAN}%-18s ${LIGHT_GREEN}%-18s ${YELLOW}%-7s ${LIGHT_PURPLE}%s hari${NC}\n" "$count" "$client_name" "$password" "$max_devices" "$remaining_days"
            else
                printf "${LIGHT_BLUE}  ${WHITE}%2d. ${LIGHT_CYAN}%-18s ${LIGHT_GREEN}%-18s ${YELLOW}%-7s ${RED}Expired${NC}\n" "$count" "$client_name" "$password" "$max_devices"
            fi
        fi
    done < "$USER_DB"
    
    echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    read -p "Masukkan nomor akun yang akan di-renew [1-$count]: " account_number
    
    if ! [[ "$account_number" =~ ^[0-9]+$ ]] || [ "$account_number" -lt 1 ] || [ "$account_number" -gt "$count" ]; then
        echo -e "${RED}Nomor akun tidak valid!${NC}"
        sleep 2
        return
    fi
    
    local selected_password=""
    local current_expiry_date=0
    local current_max_devices=0
    local current_client_name=""
    local current=0
    while IFS=':' read -r password expiry_date max_devices client_name; do
        if [[ -n "$password" ]]; then
            current=$((current + 1))
            if [ $current -eq $account_number ]; then
                selected_password=$password
                current_expiry_date=$expiry_date
                current_max_devices=$max_devices
                current_client_name=$client_name
                break
            fi
        fi
    done < "$USER_DB"
    
    if [ -z "$selected_password" ]; then
        echo -e "${RED}Akun tidak ditemukan!${NC}"
        sleep 2
        return
    fi
    
    echo ""
    echo -e "${LIGHT_GREEN}Akun yang dipilih:${NC}"
    echo -e "${WHITE}Nama: ${current_client_name}${NC}"
    echo -e "${WHITE}Password: ${selected_password}${NC}"
    echo ""
    
    echo -e "${LIGHT_BLUE}1) ${WHITE}Tambah masa aktif${NC}"
    echo -e "${LIGHT_BLUE}2) ${WHITE}Ganti password${NC}"
    echo -e "${LIGHT_BLUE}3) ${WHITE}Ubah limit IP/device${NC}"
    echo ""
    read -p "Pilih opsi [1-3]: " renew_option
    
    case $renew_option in
        1)
            read -p "Masukkan jumlah hari untuk ditambahkan: " days
            if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
                echo -e "${RED}Jumlah hari tidak valid!${NC}"
                sleep 2
                return
            fi
            
            local seconds_to_add=$((days * 86400))
            local new_expiry_date=$((current_expiry_date + seconds_to_add))
            
            sed -i "s/^${selected_password}:.*/${selected_password}:${new_expiry_date}:${current_max_devices}:${current_client_name}/" "$USER_DB"
            
            local new_expiry_formatted
            new_expiry_formatted=$(date -d "@$new_expiry_date" +"%d %B %Y")
            echo -e "${GREEN}Masa aktif akun '${selected_password}' ditambah ${days} hari.${NC}"
            echo -e "${LIGHT_BLUE}Expire baru: ${WHITE}${new_expiry_formatted}${NC}"
            
            # Unlock account if it was locked
            unlock_account "$selected_password"
            
            sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
            echo -e "${LIGHT_GREEN}Device tracking telah di-reset!${NC}"
            ;;
        2)
            read -p "Masukkan password baru: " new_password
            if [ -z "$new_password" ]; then
                echo -e "${RED}Password tidak boleh kosong!${NC}"
                sleep 2
                return
            fi
            
            if grep -q "^${new_password}:" "$USER_DB"; then
                echo -e "${RED}Password '${new_password}' sudah ada!${NC}"
                sleep 2
                return
            fi
            
            sed -i "s/^${selected_password}:.*/${new_password}:${current_expiry_date}:${current_max_devices}:${current_client_name}/" "$USER_DB"
            
            sed -i "s/^${selected_password}:/${new_password}:/" "$DEVICE_DB" 2>/dev/null
            
            jq --arg old "$selected_password" --arg new "$new_password" '.auth.config |= map(if . == $old then $new else . end)' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
            
            # Unlock account if it was locked
            unlock_account "$selected_password"
            
            echo -e "${GREEN}Password akun berhasil diganti!${NC}"
            echo -e "${LIGHT_BLUE}Password lama: ${WHITE}${selected_password}${NC}"
            echo -e "${LIGHT_BLUE}Password baru: ${WHITE}${new_password}${NC}"
            ;;
        3)
            echo -e "${LIGHT_BLUE}Limit IP/device saat ini: ${WHITE}${current_max_devices}${NC}"
            read -p "Masukkan limit IP/device baru: " new_max_devices
            
            if ! [[ "$new_max_devices" =~ ^[0-9]+$ ]] || [ "$new_max_devices" -lt 1 ]; then
                echo -e "${RED}Limit device tidak valid!${NC}"
                sleep 2
                return
            fi
            
            sed -i "s/^${selected_password}:.*/${selected_password}:${current_expiry_date}:${new_max_devices}:${current_client_name}/" "$USER_DB"
            
            # Unlock account if it was locked
            unlock_account "$selected_password"
            
            echo -e "${GREEN}Limit IP/device berhasil diubah!${NC}"
            echo -e "${LIGHT_BLUE}Limit lama: ${WHITE}${current_max_devices} device${NC}"
            echo -e "${LIGHT_BLUE}Limit baru: ${WHITE}${new_max_devices} device${NC}"
            
            if [ "$new_max_devices" -lt "$current_max_devices" ]; then
                sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
                echo -e "${LIGHT_GREEN}Device tracking telah di-reset!${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid!${NC}"
            sleep 2
            return
            ;;
    esac
    
    restart_zivpn
    sleep 2
}

# --- List Accounts ---
function _display_accounts() {
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo "Tidak ada akun ditemukan."
        return
    fi

    local current_date
    current_date=$(date +%s)
    
    # Header tanpa penutup kanan dengan warna berbeda
    echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════════${NC}"
    echo -e "${LIGHT_BLUE}  ${WHITE}No.  ${LIGHT_CYAN}Nama User${WHITE}           ${LIGHT_GREEN}Password${WHITE}           ${YELLOW}Limit${WHITE}   ${LIGHT_PURPLE}Sisa Hari${NC}"
    echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════════${NC}"
    
    local count=0
    while IFS=':' read -r password expiry_date max_devices client_name; do
        if [[ -n "$password" ]]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - current_date))
            if [ $remaining_seconds -gt 0 ]; then
                local remaining_days=$((remaining_seconds / 86400))
                printf "${LIGHT_BLUE}  ${WHITE}%2d. ${LIGHT_CYAN}%-18s ${LIGHT_GREEN}%-18s ${YELLOW}%-7s ${LIGHT_PURPLE}%s hari${NC}\n" "$count" "$client_name" "$password" "$max_devices" "$remaining_days"
            else
                printf "${LIGHT_BLUE}  ${WHITE}%2d. ${LIGHT_CYAN}%-18s ${LIGHT_GREEN}%-18s ${YELLOW}%-7s ${RED}Expired${NC}\n" "$count" "$client_name" "$password" "$max_devices"
            fi
        fi
    done < "$USER_DB"
    
    echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════════${NC}"
    echo -e "${LIGHT_BLUE}  ${WHITE}Total: ${count} akun${NC}"
}

function list_accounts() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${WHITE}DAFTAR AKUN AKTIF${BLUE}              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    _display_accounts
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

# --- Backup/Restart ---
function backup_restart() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${WHITE}BACKUP / RESTART${BLUE}               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}1) ${CYAN}Backup Data${LIGHT_BLUE}                         ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}2) ${CYAN}Restore Data${LIGHT_BLUE}                        ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}0) ${CYAN}Kembali ke Menu${LIGHT_BLUE}                     ║${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Pilih menu [0-2]: " choice
    
    case $choice in
        1)
            echo "Membuat backup..."
            mkdir -p /backup/zivpn
            cp -r /etc/zivpn /backup/zivpn/
            tar -czf /backup/zivpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz /backup/zivpn
            echo -e "${GREEN}Backup berhasil dibuat!${NC}"
            sleep 2
            ;;
        2)
            echo "Restore data..."
            echo -e "${YELLOW}Fitur restore dalam pengembangan${NC}"
            sleep 2
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid!${NC}"
            sleep 1
            ;;
    esac
}

# --- Info Panel Function (format seperti menu manager) ---
function display_info_panel() {
    # Get OS info
    local os_info=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"' 2>/dev/null | cut -d' ' -f1-3 || echo "Unknown OS")
    
    # Get ISP info
    local isp_info=$(curl -s ipinfo.io/org 2>/dev/null | head -1 | awk '{print $1}' || echo "Unknown ISP")
    
    # Get IP Address
    local ip_info=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown IP")
    
    # Get Domain/Host
    local host_info=""
    if [ -f "/etc/zivpn/zivpn.crt" ]; then
        host_info=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    fi
    
    if [ -z "$host_info" ] || [ "$host_info" == "zivpn" ]; then
        host_info=$ip_info
    fi
    
    # Get Client Name from file if exists
    local client_info="N/A"
    if [ -f "/etc/zivpn/.client_info" ]; then
        client_info=$(cat /etc/zivpn/.client_info 2>/dev/null || echo "N/A")
    fi
    
    # Get Expiry info if exists
    local expiry_info="N/A"
    if [ -f "/etc/zivpn/.expiry_info" ]; then
        expiry_info=$(cat /etc/zivpn/.expiry_info 2>/dev/null || echo "N/A")
    fi
    
    # Get bandwidth info
    local today_bw="0.00 MiB"
    local month_bw="0.00 MiB"
    
    # Try to get bandwidth if vnstat is installed
    if command -v vnstat &> /dev/null; then
        # Get bandwidth in KiB (raw numbers)
        local vnstat_output=$(vnstat --oneline 2>/dev/null)
        
        if [ -n "$vnstat_output" ]; then
            # Parse today's bandwidth (field 11 for today in KiB)
            local today_kib=$(echo "$vnstat_output" | cut -d';' -f11 2>/dev/null)
            # Parse month's bandwidth (field 10 for month in KiB)
            local month_kib=$(echo "$vnstat_output" | cut -d';' -f10 2>/dev/null)
            
            # Convert today's bandwidth
            if [[ "$today_kib" =~ ^[0-9]+$ ]] && [ "$today_kib" -gt 0 ]; then
                if [ "$today_kib" -gt 1048576 ]; then
                    today_bw=$(awk -v kib="$today_kib" 'BEGIN { printf "%.2f GiB", kib/1048576 }')
                else
                    today_bw=$(awk -v kib="$today_kib" 'BEGIN { printf "%.2f MiB", kib/1024 }')
                fi
            fi
            
            # Convert month's bandwidth
            if [[ "$month_kib" =~ ^[0-9]+$ ]] && [ "$month_kib" -gt 0 ]; then
                if [ "$month_kib" -gt 1048576 ]; then
                    month_bw=$(awk -v kib="$month_kib" 'BEGIN { printf "%.2f GiB", kib/1048576 }')
                else
                    month_bw=$(awk -v kib="$month_kib" 'BEGIN { printf "%.2f MiB", kib/1024 }')
                fi
            fi
        fi
    fi
    
    # Format ISP info (ambil hanya bagian pertama)
    isp_info=$(echo "$isp_info" | awk '{print $1}')
    
    # Format OS info (singkatkan)
    os_info=$(echo "$os_info" | cut -d' ' -f1-2)
    
    # Format IP info (tampilkan 15 karakter pertama jika terlalu panjang)
    if [ ${#ip_info} -gt 15 ]; then
        ip_info="${ip_info:0:15}..."
    fi
    
    # Format host info (tampilkan 15 karakter pertama jika terlalu panjang)
    if [ ${#host_info} -gt 15 ]; then
        host_info="${host_info:0:15}..."
    fi
    
    # Format client info (tampilkan 10 karakter pertama)
    if [ ${#client_info} -gt 10 ]; then
        client_info="${client_info:0:10}..."
    fi
    
    # Format expiry info (singkatkan jika terlalu panjang)
    if [ ${#expiry_info} -gt 10 ]; then
        expiry_info="${expiry_info:0:10}..."
    fi
    
    # Display Info Panel dengan format yang sama persis
    echo -e "${BLUE}╔═══════════════════ ${GOLD}✦ UDP ZIVPN ✦ ${BLUE}════════════════════╗${NC}"
    # Baris 1: OS dan ISP
    printf "  ${RED}%-5s${GOLD}%-20s ${GOLD}%-5s${RED}%-23s\n" "OS:" "$os_info" "ISP:" "$isp_info"
    # Baris 2: IP dan Host
    printf "  ${RED}%-5s${GOLD}%-20s ${GOLD}%-5s${RED}%-23s\n" "IP:" "$ip_info" "Host:" "$host_info"
    # Baris 3: Client dan Expiry
    printf "  ${RED}%-5s${GOLD}%-20s ${GOLD}%-5s${RED}%-23s\n" "Client:" "$client_info" "EXP:" "$expiry_info"
    # Baris 4: Today dan Month bandwidth
    printf "  ${RED}%-5s${GOLD}%-20s ${GOLD}%-5s${RED}%-23s\n" "Today:" "$today_bw" "Month:" "$month_bw"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
}

# --- Display Figlet Banner ---
function display_banner() {
    # Cek apakah figlet dan lolcat terinstall
    if command -v figlet &> /dev/null && command -v lolcat &> /dev/null; then
        clear
        figlet "PONDOK VPN" | lolcat
        echo ""
    else
        # Jika tidak ada figlet/lolcat, tampilkan banner sederhana
        clear
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║           ${LIGHT_CYAN}PONDOK VPN${BLUE}              ║${NC}"
        echo -e "${BLUE}║        ${YELLOW}ZIVPN MANAGER${BLUE}                  ║${NC}"
        echo -e "${BLUE}║     ${WHITE}Telegram: @bendakerep${BLUE}              ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
    fi
}

# --- Main Menu (2 Column Layout dengan spacing presisi) ---
function show_menu() {
    while true; do
        display_banner
        
        # Display info panel
        display_info_panel
        echo ""
        
        # Main Menu dengan 2 kolom dan spacing presisi - PANJANG SAMA DENGAN INFO PANEL
        echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                  ${GOLD} ZIVPN MANAGER MENU ${BLUE}               ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "${BLUE}║                                                      ║${NC}"
        echo -e "${BLUE}║ ${WHITE}1) ${CYAN}CREATE ACCOUNT${BLUE}  ${WHITE}6) ${CYAN}TELEGRAM BOT${BLUE}  ║${NC}"
        echo -e "${BLUE}║ ${WHITE}2) ${CYAN}RENEW ACCOUNT${BLUE}   ${WHITE}7) ${CYAN}BACKUP/RESTART${BLUE}║${NC}"
        echo -e "${BLUE}║ ${WHITE}3) ${CYAN}DELETE ACCOUNT${BLUE}  ${WHITE}8) ${CYAN}RESTART SERVIS${BLUE}║${NC}"
        echo -e "${BLUE}║ ${WHITE}4) ${CYAN}CHANGE DOMAIN${BLUE}   ${WHITE}9) ${CYAN}LIST ACCOUNT${BLUE}  ║${NC}"
        echo -e "${BLUE}║ ${WHITE}5) ${CYAN}TRIAL ACCOUNT${BLUE}   ${WHITE}0) ${CYAN}EXIT${BLUE}       ║${NC}"
        echo -e "${BLUE}║                                                      ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
        echo -e "${BLUE}║               ${YELLOW}CREATED BY : PONDOK VPN ${BLUE}              ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -p "Pilih menu [0-9]: " choice

        case $choice in
            1) create_account ;;
            2) renew_account ;;
            3) delete_account ;;
            4) change_domain ;;
            5) create_trial_account ;;
            6) telegram_bot_menu ;;
            7) backup_restart ;;
            8) restart_zivpn ;;
            9) list_accounts ;;
            0) 
                echo -e "${GREEN}Terima kasih!${NC}"
                exit 0
                ;;
            *) 
                echo -e "${RED}Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

# --- Auto Install Dependencies ---
function install_dependencies() {
    echo -e "${YELLOW}Memeriksa dependencies...${NC}"
    
    # Install figlet dan lolcat untuk banner
    if ! command -v figlet &> /dev/null; then
        echo -e "${YELLOW}Menginstall figlet...${NC}"
        apt-get update && apt-get install -y figlet > /dev/null 2>&1
    fi
    
    if ! command -v lolcat &> /dev/null; then
        echo -e "${YELLOW}Menginstall lolcat...${NC}"
        apt-get install -y lolcat > /dev/null 2>&1
    fi
    
    # Install jq untuk JSON parsing
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Menginstall jq...${NC}"
        apt-get install -y jq > /dev/null 2>&1
    fi
    
    # Install curl untuk HTTP requests
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}Menginstall curl...${NC}"
        apt-get install -y curl > /dev/null 2>&1
    fi
    
    echo -e "${GREEN}Dependencies siap!${NC}"
    sleep 1
}

# --- Main Execution ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Install dependencies jika belum ada
    install_dependencies
    
    # Initialize databases if they don't exist
    touch "$USER_DB"
    touch "$DEVICE_DB"
    touch "$LOCKED_DB"
    
    # Create client info file if not exists
    if [ ! -f "/etc/zivpn/.client_info" ]; then
        read -p "Masukkan nama client: " client_name
        echo "$client_name" > /etc/zivpn/.client_info
    fi
    
    # Create expiry info file if not exists
    if [ ! -f "/etc/zivpn/.expiry_info" ]; then
        echo "Tidak ada expiry" > /etc/zivpn/.expiry_info
    fi
    
    show_menu
fi
