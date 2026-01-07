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
CONFIG_FILE="/etc/zivpn/config.json"
DEVICE_DB="/etc/zivpn/devices.db"
LOCKED_DB="/etc/zivpn/locked.db"
FAIL2BAN_LOG="/var/log/fail2ban.log"
FAIL2BAN_JAIL="/etc/fail2ban/jail.local"

# ================================================
# --- Utility Functions ---
function restart_zivpn() {
    echo "Restarting ZIVPN service..."
    
    # Cek apakah service zivpn ada
    if systemctl list-unit-files | grep -q zivpn.service; then
        systemctl restart zivpn.service
        echo "Service restarted."
    elif systemctl list-unit-files | grep -q "udp-custom\|udp-zivpn\|zivpn-udp"; then
        # Coba cari service dengan nama lain
        local service_name=$(systemctl list-unit-files | grep -E "udp-custom|udp-zivpn|zivpn-udp" | head -1 | awk '{print $1}')
        systemctl restart "$service_name"
        echo "Service $service_name restarted."
    elif [ -f "/etc/init.d/zivpn" ]; then
        /etc/init.d/zivpn restart
        echo "Service restarted via init.d."
    else
        echo -e "${YELLOW}Warning: ZIVPN service not found. Please restart manually.${NC}"
        echo -e "${YELLOW}You may need to run: systemctl restart zivpn${NC}"
    fi
}

# --- Fail2Ban Functions ---
function install_fail2ban() {
    echo -e "${YELLOW}Menginstall fail2ban untuk proteksi...${NC}"
    
    if ! command -v fail2ban-server &> /dev/null; then
        apt-get update
        apt-get install -y fail2ban
    fi
    
    # Buat config fail2ban untuk ZIVPN
    cat > /etc/fail2ban/jail.d/zivpn.conf << EOF
[zivpn]
enabled = true
port = 443,80
filter = zivpn
logpath = /var/log/zivpn.log
maxretry = 3
bantime = 3600
findtime = 600
EOF
    
    # Buat filter untuk ZIVPN
    cat > /etc/fail2ban/filter.d/zivpn.conf << EOF
[Definition]
failregex = ^.*Failed login for user: <HOST>.*$
ignoreregex =
EOF
    
    # Buat log file jika belum ada
    touch /var/log/zivpn.log
    chmod 644 /var/log/zivpn.log
    
    systemctl restart fail2ban
    echo -e "${GREEN}Fail2Ban installed and configured for ZIVPN protection${NC}"
}

# --- Check Device Limit ---
function check_device_limit() {
    local username="$1"
    local current_ip="$2"
    local max_devices=2  # Default limit 2 device/IP
    
    if [ ! -f "$DEVICE_DB" ]; then
        touch "$DEVICE_DB"
    fi
    
    # Hitung jumlah device yang terdaftar
    local device_count=$(grep -c "^${username}:" "$DEVICE_DB" 2>/dev/null || echo "0")
    
    if [ "$device_count" -ge "$max_devices" ]; then
        # Cek apakah IP saat ini sudah terdaftar
        if ! grep -q "^${username}:${current_ip}" "$DEVICE_DB"; then
            # Akun melebihi limit, lock account
            echo -e "${RED}⚠️  Account ${username} melebihi limit device (max: $max_devices)${NC}"
            lock_account "$username" "Melebihi limit IP/device (max: $max_devices)"
            
            # Log ke fail2ban
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Account $username blocked for exceeding device limit from IP $current_ip" >> /var/log/zivpn.log
            
            return 1
        fi
    fi
    
    return 0
}

# --- Register Device ---
function register_device() {
    local username="$1"
    local ip_address="$2"
    
    # Hapus entry lama dengan IP yang sama
    sed -i "/^${username}:${ip_address}/d" "$DEVICE_DB" 2>/dev/null
    
    # Tambah entry baru
    local timestamp=$(date +%s)
    echo "${username}:${ip_address}:${timestamp}" >> "$DEVICE_DB"
    
    # Hapus device yang sudah lama (lebih dari 7 hari)
    local week_ago=$(date -d "7 days ago" +%s)
    while IFS=':' read -r user ip time; do
        if [ "$time" -lt "$week_ago" ]; then
            sed -i "/^${user}:${ip}:${time}/d" "$DEVICE_DB" 2>/dev/null
        fi
    done < "$DEVICE_DB"
}

# --- Lock Account ---
function lock_account() {
    local username="$1"
    local reason="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    echo -e "${RED}🔒 Mengunci akun: $username - Alasan: $reason${NC}"
    
    # Hapus dari users.db
    sed -i "/^${username}:/d" "$USER_DB"
    
    # Tambah ke locked database
    echo "${username}:${timestamp}:${reason}" >> "$LOCKED_DB"
    
    # Hapus dari config.json
    if [ -f "$CONFIG_FILE" ]; then
        jq --arg pass "$username" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE"
    fi
    
    # Hapus dari device DB
    sed -i "/^${username}:/d" "$DEVICE_DB" 2>/dev/null
    
    # Restart service
    restart_zivpn
}

# --- Unlock Account ---
function unlock_account() {
    local username="$1"
    
    if [ -f "$LOCKED_DB" ]; then
        sed -i "/^${username}:/d" "$LOCKED_DB"
        echo -e "${GREEN}🔓 Membuka kunci akun: $username${NC}"
    fi
}

# --- Auto Delete Expired Accounts ---
function delete_expired_accounts() {
    local current_timestamp=$(date +%s)
    local deleted_count=0
    
    if [ ! -f "$USER_DB" ]; then
        return
    fi
    
    # Buat file temporary untuk menyimpan akun yang masih aktif
    local temp_file=$(mktemp)
    
    while IFS=':' read -r password expiry_date client_name; do
        if [[ -n "$password" ]]; then
            if [ $expiry_date -gt $current_timestamp ]; then
                # Akun masih aktif, simpan ke temp file
                echo "${password}:${expiry_date}:${client_name}" >> "$temp_file"
            else
                # Akun expired, hapus dari config.json
                echo -e "${YELLOW}Menghapus akun expired: ${password}${NC}"
                deleted_count=$((deleted_count + 1))
                
                # Hapus dari config.json jika file ada
                if [ -f "$CONFIG_FILE" ]; then
                    jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE" 2>/dev/null
                fi
                
                # Hapus dari device DB
                sed -i "/^${password}:/d" "$DEVICE_DB" 2>/dev/null
            fi
        fi
    done < "$USER_DB"
    
    # Ganti file database dengan yang baru
    mv "$temp_file" "$USER_DB"
    
    if [ $deleted_count -gt 0 ]; then
        echo -e "${GREEN}Menghapus $deleted_count akun expired${NC}"
        # Restart service hanya jika ada perubahan
        restart_zivpn
    fi
}

# --- Create Account (dengan limit 2 IP/device) ---
function create_account() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       ${WHITE}BUAT AKUN UDP PREMIUM${BLUE}             ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Hapus akun expired sebelum membuat akun baru
    delete_expired_accounts
    
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

    if grep -q "^${password}:" "$USER_DB"; then
        echo -e "${YELLOW}Password '${password}' sudah ada.${NC}"
        return
    fi

    local expiry_date
    expiry_date=$(date -d "+$days days" +%s)
    echo "${password}:${expiry_date}:${client_name}" >> "$USER_DB"
    
    # Update config.json
    if [ -f "$CONFIG_FILE" ]; then
        jq --arg pass "$password" '.auth.config += [$pass]' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE"
    else
        echo -e "${YELLOW}Config file not found: $CONFIG_FILE${NC}"
        echo -e "${YELLOW}Creating new config file...${NC}"
        mkdir -p /etc/zivpn
        echo '{"auth": {"config": []}}' > "$CONFIG_FILE"
        jq --arg pass "$password" '.auth.config += [$pass]' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE"
    fi
    
    local CERT_CN=""
    if [ -f "/etc/zivpn/zivpn.crt" ]; then
        CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    fi
    
    local HOST
    if [ -z "$CERT_CN" ] || [ "$CERT_CN" == "zivpn" ]; then
        HOST=$(curl -s ifconfig.me 2>/dev/null || echo "127.0.0.1")
    else
        HOST=$CERT_CN
    fi

    local EXPIRE_FORMATTED
    EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y")
    
    clear
    echo -e "${BLUE}╔══════════════════════════╗${NC}"
    echo -e "${BLUE}║  ${WHITE}✅  AKUN BERHASIL DIBUAT${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Nama: ${WHITE}$client_name${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Host: ${WHITE}$HOST${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Pass: ${WHITE}$password${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Expi: ${WHITE}$EXPIRE_FORMATTED${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${YELLOW}⚠️  PERHATIAN:${NC}"
    echo -e "${BLUE}║${WHITE}Limit: 2 IP/Device${NC}"
    echo -e "${BLUE}║${WHITE}Akun akan dilock jika melebihi limit${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}Terima kasih sudah order!${NC}"
    echo -e "${BLUE}║${YELLOW}PONDOK VPN${NC}"
    echo -e "${BLUE}╚══════════════════════════╝${NC}"
    
    restart_zivpn
    read -p "Tekan Enter untuk kembali ke menu..."
}

# --- Create Trial Account ---
function trial_account() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        ${WHITE}BUAT AKUN TRIAL${BLUE}              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Hapus akun expired sebelum membuat trial baru
    delete_expired_accounts
    
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

    local expiry_date
    expiry_date=$(date -d "+$minutes minutes" +%s)
    echo "${password}:${expiry_date}:${client_name}" >> "$USER_DB"
    
    # Update config.json
    if [ -f "$CONFIG_FILE" ]; then
        jq --arg pass "$password" '.auth.config += [$pass]' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE"
    fi
    
    local CERT_CN=""
    if [ -f "/etc/zivpn/zivpn.crt" ]; then
        CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    fi
    
    local HOST
    if [ -z "$CERT_CN" ] || [ "$CERT_CN" == "zivpn" ]; then
        HOST=$(curl -s ifconfig.me 2>/dev/null || echo "127.0.0.1")
    else
        HOST=$CERT_CN
    fi

    local EXPIRE_FORMATTED
    EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y %H:%M:%S")
    
    clear
    echo -e "${BLUE}╔══════════════════════════╗${NC}"
    echo -e "${BLUE}║  ${WHITE}✅ AKUN TRIAL BERHASIL${BLUE}        ║${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Nama: ${WHITE}$client_name${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Host: ${WHITE}$HOST${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Pass: ${WHITE}$password${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Expire: ${WHITE}$EXPIRE_FORMATTED${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${YELLOW}⚠️  PERHATIAN:${NC}"
    echo -e "${BLUE}║${WHITE}Limit: 1 IP/Device${NC}"
    echo -e "${BLUE}║${WHITE}Akun akan dilock jika melebihi limit${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}Terima kasih sudah mencoba${NC}"
    echo -e "${BLUE}║${YELLOW}PONDOK VPN${NC}"
    echo -e "${BLUE}╚══════════════════════════╝${NC}"
    
    restart_zivpn
    read -p "Tekan Enter untuk kembali ke menu..."
}

# --- Renew Account ---
function renew_account() {
    clear
    
    # Hapus akun expired terlebih dahulu
    delete_expired_accounts
    
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${WHITE}RENEW AKUN ZIVPN${BLUE}               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════════${NC}"
    echo -e "${LIGHT_BLUE}  ${WHITE}No.  Nama User           Password           Expired${NC}"
    echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════════${NC}"
    
    local count=0
    while IFS=':' read -r password expiry_date client_name; do
        if [[ -n "$password" ]]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - $(date +%s)))
            local remaining_days=$((remaining_seconds / 86400))
            if [ $remaining_days -gt 0 ]; then
                local expire_date=$(date -d "@$expiry_date" +"%d-%m-%Y")
                printf "${LIGHT_BLUE}  ${WHITE}%2d. %-18s %-18s %s${NC}\n" "$count" "$client_name" "$password" "$expire_date"
            else
                printf "${LIGHT_BLUE}  ${WHITE}%2d. %-18s %-18s ${RED}Expired${NC}\n" "$count" "$client_name" "$password"
            fi
        fi
    done < "$USER_DB"
    
    echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    read -p "Masukkan nomor akun yang akan di-renew [1-$count]: " account_number
    
    if ! [[ "$account_number" =~ ^[0-9]+$ ]] || [ "$account_number" -lt 1 ] || [ "$account_number" -gt "$count" ]; then
        echo -e "${RED}Nomor akun tidak valid!${NC}"
        sleep 2
        return
    fi
    
    local selected_password=""
    local current_expiry_date=0
    local current_client_name=""
    local current=0
    while IFS=':' read -r password expiry_date client_name; do
        if [[ -n "$password" ]]; then
            current=$((current + 1))
            if [ $current -eq $account_number ]; then
                selected_password=$password
                current_expiry_date=$expiry_date
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
    echo ""
    read -p "Pilih opsi [1-2]: " renew_option
    
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
            
            sed -i "s/^${selected_password}:.*/${selected_password}:${new_expiry_date}:${current_client_name}/" "$USER_DB"
            
            # Reset device tracking saat renew
            sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
            echo -e "${LIGHT_GREEN}Device tracking telah di-reset!${NC}"
            
            local new_expiry_formatted
            new_expiry_formatted=$(date -d "@$new_expiry_date" +"%d %B %Y")
            echo -e "${GREEN}Masa aktif akun '${selected_password}' ditambah ${days} hari.${NC}"
            echo -e "${LIGHT_BLUE}Expire baru: ${WHITE}${new_expiry_formatted}${NC}"
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
            
            sed -i "s/^${selected_password}:.*/${new_password}:${current_expiry_date}:${current_client_name}/" "$USER_DB"
            
            # Update device tracking dengan password baru
            sed -i "s/^${selected_password}:/${new_password}:/" "$DEVICE_DB" 2>/dev/null
            
            jq --arg old "$selected_password" --arg new "$new_password" '.auth.config |= map(if . == $old then $new else . end)' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
            
            echo -e "${GREEN}Password akun berhasil diganti!${NC}"
            echo -e "${LIGHT_BLUE}Password lama: ${WHITE}${selected_password}${NC}"
            echo -e "${LIGHT_BLUE}Password baru: ${WHITE}${new_password}${NC}"
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

# --- Delete Account ---
function delete_account() {
    clear
    
    # Hapus akun expired terlebih dahulu
    delete_expired_accounts
    
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${WHITE}HAPUS AKUN ZIVPN${BLUE}               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════════${NC}"
    echo -e "${LIGHT_BLUE}  ${WHITE}No.  Nama User           Password           Expired${NC}"
    echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════════${NC}"
    
    local count=0
    while IFS=':' read -r password expiry_date client_name; do
        if [[ -n "$password" ]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - $(date +%s)))
            local remaining_days=$((remaining_seconds / 86400))
            if [ $remaining_days -gt 0 ]; then
                local expire_date=$(date -d "@$expiry_date" +"%d-%m-%Y")
                printf "${LIGHT_BLUE}  ${WHITE}%2d. %-18s %-18s %s${NC}\n" "$count" "$client_name" "$password" "$expire_date"
            else
                printf "${LIGHT_BLUE}  ${WHITE}%2d. %-18s %-18s ${RED}Expired${NC}\n" "$count" "$client_name" "$password"
            fi
        fi
    done < "$USER_DB"
    
    echo -e "${LIGHT_BLUE}═════════════════════════════════════════════════════════════${NC}"
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
    local current_client_name=""
    local current=0
    while IFS=':' read -r password expiry_date client_name; do
        if [[ -n "$password" ]]; then
            current=$((current + 1))
            if [ $current -eq $account_number ]; then
                selected_password=$password
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
    echo -e "${YELLOW}Apakah Anda yakin ingin menghapus akun:${NC}"
    echo -e "${WHITE}Nama: ${current_client_name}${NC}"
    echo -e "${WHITE}Password: ${selected_password}${NC}"
    read -p "Konfirmasi (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Penghapusan dibatalkan.${NC}"
        sleep 1
        return
    fi
    
    # Hapus dari database
    sed -i "/^${selected_password}:/d" "$USER_DB"
    
    # Hapus dari device DB
    sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
    
    # Hapus dari config.json
    jq --arg pass "$selected_password" 'del(.auth.config[] | select(. == $pass))' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    
    echo -e "${GREEN}Akun '${selected_password}' berhasil dihapus.${NC}"
    
    restart_zivpn
    sleep 2
}

# --- Add Bot Token ---
function add_bot_token() {
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
    
    mkdir -p /etc/zivpn
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
    echo -e "${LIGHT_BLUE}║   ${WHITE}3) ${CYAN}Install Fail2Ban${LIGHT_BLUE}                    ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}0) ${CYAN}Kembali ke Menu${LIGHT_BLUE}                     ║${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Pilih menu [0-3]: " choice
    
    case $choice in
        1)
            echo "Membuat backup..."
            mkdir -p /backup/zivpn
            cp -r /etc/zivpn /backup/zivpn/
            tar -czf /backup/zivpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz /backup/zivpn
            
            # Kirim notifikasi ke Telegram jika ada
            if [ -f "/etc/zivpn/telegram.conf" ]; then
                source /etc/zivpn/telegram.conf 2>/dev/null
                if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                        -d "chat_id=${TELEGRAM_CHAT_ID}" \
                        -d "text=✅ Backup berhasil dibuat! 
📁 File: zivpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz
📅 Tanggal: $(date '+%d %B %Y %H:%M:%S')
📱 PONDOK VPN" \
                        -d "parse_mode=Markdown" > /dev/null 2>&1
                fi
            fi
            
            echo -e "${GREEN}Backup berhasil dibuat!${NC}"
            sleep 2
            ;;
        2)
            echo "Restore data..."
            echo -e "${YELLOW}Fitur restore dalam pengembangan${NC}"
            sleep 2
            ;;
        3)
            install_fail2ban
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

# --- Restart Service ---
function restart_service() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${WHITE}RESTART SERVIS${BLUE}                 ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Hapus akun expired terlebih dahulu
    delete_expired_accounts
    
    echo -e "${YELLOW}Merestart service ZIVPN...${NC}"
    restart_zivpn
    echo -e "${GREEN}Service berhasil di-restart!${NC}"
    
    # Kirim notifikasi ke Telegram jika ada
    if [ -f "/etc/zivpn/telegram.conf" ]; then
        source /etc/zivpn/telegram.conf 2>/dev/null
        if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d "chat_id=${TELEGRAM_CHAT_ID}" \
                -d "text=🔄 Service ZIVPN telah di-restart!
✅ Service aktif dan berjalan
📅 $(date '+%d %B %Y %H:%M:%S')
📱 PONDOK VPN" \
                -d "parse_mode=Markdown" > /dev/null 2>&1
        fi
    fi
    
    read -p "Tekan Enter untuk kembali ke menu..."
}

# --- Domain Management Functions ---
function change_domain() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              ${WHITE}GANTI DOMAIN${BLUE}                ║${NC}"
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

# --- Info Panel Function ---
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
    
    # Format ISP info
    isp_info=$(echo "$isp_info" | awk '{print $1}')
    
    # Format OS info
    os_info=$(echo "$os_info" | cut -d' ' -f1-2)
    
    # Format IP info
    if [ ${#ip_info} -gt 15 ]; then
        ip_info="${ip_info:0:15}..."
    fi
    
    # Format host info
    if [ ${#host_info} -gt 15 ]; then
        host_info="${host_info:0:15}..."
    fi
    
    # Display Info Panel
    echo -e "${BLUE}╔═════════════════ ${GOLD}✦ UDP ZIVPN ✦ ${BLUE}══════════════════╗${NC}"
    # Baris 1: OS dan ISP
    printf "  ${RED}%-5s${GOLD}%-20s ${RED}%-5s${GOLD}%-23s\n" "OS:" "$os_info" "ISP:" "$isp_info"
    # Baris 2: IP dan Host
    printf "  ${RED}%-5s${GOLD}%-20s ${RED}%-5s${GOLD}%-23s\n" "IP:" "$ip_info" "Host:" "$host_info"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
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
        echo -e "${BLUE}║           ${LIGHT_CYAN}PONDOK VPN${BLUE}                    ║${NC}"
        echo -e "${BLUE}║        ${YELLOW}ZIVPN MANAGER${BLUE}                        ║${NC}"
        echo -e "${BLUE}║     ${WHITE}Telegram: @bendakerep${BLUE}                    ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
    fi
}

# --- Main Menu ---
function show_menu() {
    while true; do
        display_banner
        
        # Display info panel
        display_info_panel
        echo ""
        
        # Main Menu sesuai permintaan
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║             ${GOLD} ZIVPN MANAGER MENU ${BLUE}           ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
        echo -e "${BLUE}║                                          ║${NC}"
        echo -e "${BLUE}║   ${WHITE}1) ${CYAN}CREATE ACCOUNT${BLUE}     ${WHITE}5) ${CYAN}ADD BOT TOKEN${BLUE}  ║${NC}"
        echo -e "${BLUE}║   ${WHITE}2) ${CYAN}TRIAL ACCOUNT${BLUE}      ${WHITE}6) ${CYAN}BACKUP/RESTART${BLUE} ║${NC}"
        echo -e "${BLUE}║   ${WHITE}3) ${CYAN}RENEW ACCOUNT${BLUE}      ${WHITE}7) ${CYAN}RESTART SERVIS${BLUE} ║${NC}"
        echo -e "${BLUE}║   ${WHITE}4) ${CYAN}DELETE ACCOUNT${BLUE}     ${WHITE}0) ${CYAN}EXIT${BLUE}           ║${NC}"
        echo -e "${BLUE}║                                          ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
        echo -e "${BLUE}║             ${YELLOW}CREATED BY : PONDOK VPN ${BLUE}     ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        
        read -p "Pilih menu [0-7]: " choice

        case $choice in
            1) create_account ;;
            2) trial_account ;;
            3) renew_account ;;
            4) delete_account ;;
            5) add_bot_token ;;
            6) backup_restart ;;
            7) restart_service ;;
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
    
    # Initialize database if it doesn't exist
    mkdir -p /etc/zivpn
    
    if [ ! -f "$USER_DB" ]; then
        touch "$USER_DB"
    fi
    
    if [ ! -f "$DEVICE_DB" ]; then
        touch "$DEVICE_DB"
    fi
    
    if [ ! -f "$LOCKED_DB" ]; then
        touch "$LOCKED_DB"
    fi
    
    # Create config.json if not exists
    if [ ! -f "$CONFIG_FILE" ]; then
        echo '{"auth": {"config": []}}' > "$CONFIG_FILE"
    fi
    
    # Hapus akun expired saat startup
    delete_expired_accounts
    
    show_menu
fi
