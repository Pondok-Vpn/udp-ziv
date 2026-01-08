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
BAN_LIST="/etc/zivpn/banlist.db"
LOG_FILE="/var/log/zivpn_auth.log"

# ================================================
# --- FUNGSI UTILITY ---
# ================================================

# Fungsi restart service
function restart_zivpn() {
    echo -e "${YELLOW}Restarting ZIVPN service...${NC}"
    systemctl restart zivpn.service 2>/dev/null
    sleep 2
    echo -e "${GREEN}✓ Service restarted${NC}"
}

# Cek dan install dependencies
function check_dependencies() {
    echo -e "${YELLOW}Checking dependencies...${NC}"
    
    # List dependencies
    deps=("jq" "curl" "openssl" "iptables" "conntrack")
    
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            echo -e "${YELLOW}Installing $dep...${NC}"
            apt-get update > /dev/null 2>&1
            apt-get install -y $dep > /dev/null 2>&1
        fi
    done
    
    # Install figlet dan lolcat untuk banner
    if ! command -v figlet &> /dev/null || ! command -v lolcat &> /dev/null; then
        echo -e "${YELLOW}Installing figlet & lolcat...${NC}"
        apt-get install -y figlet lolcat > /dev/null 2>&1
    fi
}

# Initialize files
function initialize_files() {
    mkdir -p /etc/zivpn
    
    # Buat file jika belum ada
    touch "$USER_DB"
    touch "$DEVICE_DB"
    touch "$LOCKED_DB"
    touch "$BAN_LIST"
    touch "$LOG_FILE"
    
    chmod 600 "$USER_DB" "$DEVICE_DB" "$LOCKED_DB" "$BAN_LIST"
    
    # Buat config.json jika belum ada
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["pondok123"]
  }
}
EOF
    fi
    
    # Buat cert jika belum ada
    if [ ! -f "/etc/zivpn/zivpn.crt" ] || [ ! -f "/etc/zivpn/zivpn.key" ]; then
        openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
            -subj "/C=ID/CN=zivpn" \
            -keyout "/etc/zivpn/zivpn.key" \
            -out "/etc/zivpn/zivpn.crt" 2>/dev/null
    fi
}

# ================================================
# --- FUNGSI AUTO BAN SYSTEM ---
# ================================================

# Cek IP sudah di-ban atau belum
function is_ip_banned() {
    local ip="$1"
    if [ -f "$BAN_LIST" ] && grep -q "^${ip}:" "$BAN_LIST"; then
        return 0  # IP banned
    fi
    return 1  # IP not banned
}

# Ban IP
function ban_ip() {
    local ip="$1"
    local reason="$2"
    local timestamp=$(date +%s)
    
    # Tambah ke ban list
    echo "${ip}:${timestamp}:${reason}" >> "$BAN_LIST"
    
    # Drop traffic dari IP ini
    iptables -A INPUT -s "$ip" -j DROP 2>/dev/null
    
    # Log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] BANNED: $ip - $reason" >> "$LOG_FILE"
}

# Unban IP
function unban_ip() {
    local ip="$1"
    
    # Hapus dari ban list
    sed -i "/^${ip}:/d" "$BAN_LIST" 2>/dev/null
    
    # Hapus iptables rule
    iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
    
    # Log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] UNBANNED: $ip" >> "$LOG_FILE"
}

# Cek device limit dan auto ban
function check_device_and_ban() {
    local username="$1"
    local client_ip="$2"
    local max_devices="$3"
    
    # Skip jika unlimited atau trial
    if [ "$max_devices" -eq 0 ] || [ "$max_devices" -eq 999 ]; then
        return 0
    fi
    
    # Get current devices for this user
    current_devices=$(grep -c "^${username}:" "$DEVICE_DB" 2>/dev/null || echo "0")
    
    # Jika sudah mencapai limit
    if [ "$current_devices" -ge "$max_devices" ]; then
        # Cek apakah IP ini sudah terdaftar
        if ! grep -q "^${username}:${client_ip}" "$DEVICE_DB"; then
            # AUTO BAN - melebihi limit
            ban_ip "$client_ip" "Melebihi limit device (max: $max_devices)"
            
            # Lock account
            lock_account "$username" "Auto-ban: melebihi limit device"
            
            # Log
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] AUTO-BAN: $username from $client_ip - Device limit exceeded" >> "$LOG_FILE"
            return 1
        fi
    fi
    
    return 0
}

# Register device/IP
function register_device_ip() {
    local username="$1"
    local client_ip="$2"
    
    # Hapus entry lama untuk IP ini
    sed -i "/^${username}:${client_ip}/d" "$DEVICE_DB" 2>/dev/null
    
    # Tambah entry baru
    local timestamp=$(date +%s)
    echo "${username}:${client_ip}:${timestamp}" >> "$DEVICE_DB"
    
    # Hapus entry yang terlalu lama (> 7 hari)
    local week_ago=$(( $(date +%s) - 604800 ))
    awk -F: -v limit="$week_ago" '$3 < limit {print $1 ":" $2}' "$DEVICE_DB" | while read line; do
        sed -i "/^${line}/d" "$DEVICE_DB" 2>/dev/null
    done
}

# Lock account
function lock_account() {
    local username="$1"
    local reason="$2"
    
    # Hapus dari user database
    sed -i "/^${username}:/d" "$USER_DB" 2>/dev/null
    
    # Hapus dari config.json
    jq --arg pass "$username" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE"
    
    # Tambah ke locked database
    local timestamp=$(date +%s)
    echo "${username}:${timestamp}:${reason}" >> "$LOCKED_DB"
    
    # Hapus semua device/IP untuk user ini
    sed -i "/^${username}:/d" "$DEVICE_DB" 2>/dev/null
    
    # Log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] LOCKED: $username - $reason" >> "$LOG_FILE"
}

# Unlock account
function unlock_account() {
    local username="$1"
    
    # Hapus dari locked database
    sed -i "/^${username}:/d" "$LOCKED_DB" 2>/dev/null
    
    # Hapus dari ban list jika ada
    sed -i "/:${username}$/d" "$BAN_LIST" 2>/dev/null
    
    # Log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] UNLOCKED: $username" >> "$LOG_FILE"
}

# Cleanup expired bans (lebih dari 24 jam)
function cleanup_expired_bans() {
    if [ ! -f "$BAN_LIST" ]; then
        return
    fi
    
    local day_ago=$(( $(date +%s) - 86400 ))
    
    while IFS=':' read -r ip timestamp reason; do
        if [ "$timestamp" -lt "$day_ago" ]; then
            unban_ip "$ip"
        fi
    done < "$BAN_LIST"
}

# ================================================
# --- FUNGSI BANNER & DISPLAY ---
# ================================================

# Display banner dengan figlet warna-warni
function display_banner() {
    clear
    
    # Cek jika figlet dan lolcat ada
    if command -v figlet &> /dev/null && command -v lolcat &> /dev/null; then
        echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                                                              ║${NC}"
        figlet -f slant "PONDOK VPN" | lolcat
        figlet -f digital "ZIVPN MANAGER" | lolcat
        echo -e "${BLUE}║                                                              ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    else
        # Fallback banner jika tidak ada figlet
        echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                                                              ║${NC}"
        echo -e "${BLUE}║           ${LIGHT_CYAN}╔═╗╔═╗╔╗╔╔═╗╔╦╗╔═╗╦  ╦${BLUE}                ║${NC}"
        echo -e "${BLUE}║           ${LIGHT_CYAN}║ ╦╠═╣║║║║╣ ║║║╠═╣║  ║${BLUE}                ║${NC}"
        echo -e "${BLUE}║           ${LIGHT_CYAN}╚═╝╩ ╩╝╚╝╚═╝╩ ╩╩ ╩╩═╝╩${BLUE}                ║${NC}"
        echo -e "${BLUE}║           ${YELLOW}╔═╗╦╔═╗╔═╗╔═╗╔═╗${BLUE}                       ║${NC}"
        echo -e "${BLUE}║           ${YELLOW}╠═╝║║  ╠╣ ║ ║║╣ ${BLUE}                       ║${NC}"
        echo -e "${BLUE}║           ${YELLOW}╩  ╩╚═╝╚  ╚═╝╚═╝${BLUE}                       ║${NC}"
        echo -e "${BLUE}║                                                              ║${NC}"
        echo -e "${BLUE}║              ${WHITE}Telegram: @bendakerep${BLUE}                   ║${NC}"
        echo -e "${BLUE}║                                                              ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    fi
    echo ""
}

# Display system info
function display_system_info() {
    local ip_address=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
    local server_status=$(systemctl is-active zivpn.service 2>/dev/null || echo "Not running")
    local total_accounts=$(wc -l < "$USER_DB" 2>/dev/null || echo "0")
    local banned_ips=$(wc -l < "$BAN_LIST" 2>/dev/null || echo "0")
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                     ${WHITE}SYSTEM INFORMATION${BLUE}                    ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}• ${WHITE}Server IP   : ${GREEN}$ip_address${BLUE}                          ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}• ${WHITE}Port        : ${YELLOW}5667 UDP${BLUE}                              ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}• ${WHITE}Status      : $([ "$server_status" = "active" ] && echo "${GREEN}● RUNNING${BLUE}" || echo "${RED}● STOPPED${BLUE}")                        ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}• ${WHITE}Total Akun  : ${LIGHT_PURPLE}$total_accounts user(s)${BLUE}                      ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}• ${WHITE}Banned IPs  : ${RED}$banned_ips IP(s)${BLUE}                         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ================================================
# --- FUNGSI MANAJEMEN AKUN ---
# ================================================

# Buat akun premium
function create_regular_account() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                     ${WHITE}BUAT AKUN PREMIUM${BLUE}                      ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "  Masukkan nama client        : " client_name
    if [ -z "$client_name" ]; then
        echo -e "\n${RED}Nama tidak boleh kosong.${NC}"
        sleep 2
        return
    fi

    read -p "  Masukkan password           : " password
    if [ -z "$password" ]; then
        echo -e "\n${RED}Password tidak boleh kosong.${NC}"
        sleep 2
        return
    fi

    read -p "  Masa aktif (hari)          : " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "\n${RED}Jumlah hari tidak valid.${NC}"
        sleep 2
        return
    fi

    read -p "  Limit device (default: 2)  : " max_devices
    if [ -z "$max_devices" ]; then
        max_devices=2
    elif ! [[ "$max_devices" =~ ^[0-9]+$ ]]; then
        echo -e "\n${RED}Jumlah device tidak valid, menggunakan default: 2${NC}"
        max_devices=2
    fi

    # Cek jika password sudah ada
    if grep -q "^${password}:" "$USER_DB"; then
        echo -e "\n${YELLOW}Password '${password}' sudah ada.${NC}"
        sleep 2
        return
    fi

    # Hitung expiry date
    local expiry_date=$(date -d "+$days days" +%s)
    
    # Simpan ke database
    echo "${password}:${expiry_date}:${max_devices}:${client_name}" >> "$USER_DB"
    
    # Tambah ke config.json
    jq --arg pass "$password" '.auth.config += [$pass]' "$CONFIG_FILE" > /tmp/config.json.tmp
    if [ $? -eq 0 ]; then
        mv /tmp/config.json.tmp "$CONFIG_FILE"
    else
        echo -e "\n${RED}Gagal update config.json!${NC}"
        sleep 2
        return
    fi
    
    # Format tanggal expiry
    local EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y")
    
    # Tampilkan hasil
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                  ${WHITE}✅ AKUN BERHASIL DIBUAT${BLUE}                  ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║                                                              ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 ${WHITE}Nama Client    : ${GREEN}$client_name${BLUE}                         ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 ${WHITE}Password       : ${YELLOW}$password${BLUE}                           ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 ${WHITE}Expiry Date    : ${LIGHT_PURPLE}$EXPIRE_FORMATTED${BLUE}                       ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 ${WHITE}Masa Aktif     : ${GREEN}$days hari${BLUE}                            ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 ${WHITE}Limit Device   : ${RED}$max_devices device${BLUE}                       ║${NC}"
    echo -e "${BLUE}║                                                              ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║  ${YELLOW}⚠️  PERINGATAN:${BLUE}                                                ║${NC}"
    echo -e "${BLUE}║  ${WHITE}Akun akan otomatis di-BAN jika melebihi ${RED}$max_devices${WHITE} device!${BLUE}      ║${NC}"
    echo -e "${BLUE}║  ${WHITE}Sistem auto-ban aktif 24/7.${BLUE}                                    ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║  ${LIGHT_GREEN}Terima kasih sudah order!${BLUE}                                ║${NC}"
    echo -e "${BLUE}║  ${YELLOW}PONDOK VPN - @bendakerep${BLUE}                                    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    # Restart service
    restart_zivpn
    
    echo ""
    read -p "  Tekan Enter untuk kembali ke menu..."
}

# Buat akun trial
function create_trial_account() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                      ${WHITE}BUAT AKUN TRIAL${BLUE}                       ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "  Masukkan nama client        : " client_name
    if [ -z "$client_name" ]; then
        echo -e "\n${RED}Nama tidak boleh kosong.${NC}"
        sleep 2
        return
    fi

    read -p "  Masa aktif (jam)           : " hours
    if ! [[ "$hours" =~ ^[0-9]+$ ]]; then
        echo -e "\n${RED}Jumlah jam tidak valid.${NC}"
        sleep 2
        return
    fi

    # Generate password otomatis
    local password="trial$(shuf -i 10000-99999 -n 1)"
    local max_devices=1  # Trial hanya 1 device

    # Hitung expiry date
    local expiry_date=$(date -d "+$hours hours" +%s)
    
    # Simpan ke database
    echo "${password}:${expiry_date}:${max_devices}:${client_name}" >> "$USER_DB"
    
    # Tambah ke config.json
    jq --arg pass "$password" '.auth.config += [$pass]' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE"
    
    # Format tanggal expiry
    local EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y %H:%M")
    
    # Tampilkan hasil
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                  ${WHITE}✅ AKUN TRIAL BERHASIL${BLUE}                  ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║                                                              ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 ${WHITE}Nama Client    : ${GREEN}$client_name${BLUE}                         ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 ${WHITE}Password       : ${YELLOW}$password${BLUE}                           ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 ${WHITE}Expiry         : ${LIGHT_PURPLE}$EXPIRE_FORMATTED${BLUE}                       ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 ${WHITE}Masa Aktif     : ${GREEN}$hours jam${BLUE}                            ║${NC}"
    echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 ${WHITE}Limit Device   : ${RED}$max_devices device${BLUE}                       ║${NC}"
    echo -e "${BLUE}║                                                              ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║  ${YELLOW}⚠️  AKUN TRIAL:${BLUE}                                                ║${NC}"
    echo -e "${BLUE}║  ${WHITE}Hanya ${RED}1 device${WHITE} yang diperbolehkan!${BLUE}                              ║${NC}"
    echo -e "${BLUE}║  ${WHITE}Auto-ban aktif jika melebihi limit.${BLUE}                              ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║  ${LIGHT_GREEN}Terima kasih sudah mencoba!${BLUE}                              ║${NC}"
    echo -e "${BLUE}║  ${YELLOW}PONDOK VPN - @bendakerep${BLUE}                                    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    # Restart service
    restart_zivpn
    
    echo ""
    read -p "  Tekan Enter untuk kembali ke menu..."
}

# Menu buat akun
function create_account() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                      ${WHITE}BUAT AKUN BARU${BLUE}                        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║                                                              ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}1) ${CYAN}BUAT AKUN PREMIUM${LIGHT_BLUE}                                  ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}2) ${CYAN}BUAT AKUN TRIAL${LIGHT_BLUE}                                    ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}0) ${CYAN}KEMBALI KE MENU${LIGHT_BLUE}                                    ║${NC}"
    echo -e "${LIGHT_BLUE}║                                                              ║${NC}"
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "  Pilih menu [0-2]: " choice

    case $choice in
        1) create_regular_account ;;
        2) create_trial_account ;;
        0) return ;;
        *) echo -e "\n${RED}Pilihan tidak valid!${NC}"; sleep 1 ;;
    esac
}

# Hapus akun
function delete_account() {
    clear
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "  Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                      ${WHITE}HAPUS AKUN${BLUE}                          ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║ ${WHITE}No.  Nama Client           Password               Limit     Sisa Hari${BLUE}               ║${NC}"
    echo -e "${LIGHT_BLUE}╠══════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    local count=0
    local current_date=$(date +%s)
    
    while IFS=':' read -r password expiry_date max_devices client_name; do
        if [[ -n "$password" ]]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - current_date))
            local remaining_days=$((remaining_seconds / 86400))
            
            if [ $remaining_days -gt 0 ]; then
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-20s %-20s %-8s %s hari${BLUE}                    ║\n" \
                    "$count" "$client_name" "$password" "$max_devices" "$remaining_days"
            else
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-20s %-20s %-8s ${RED}Expired${BLUE}                     ║\n" \
                    "$count" "$client_name" "$password" "$max_devices"
            fi
        fi
    done < "$USER_DB"
    
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "  Tekan Enter untuk kembali..."
        return
    fi
    
    read -p "  Masukkan nomor akun [1-$count]: " account_number
    
    if ! [[ "$account_number" =~ ^[0-9]+$ ]] || [ "$account_number" -lt 1 ] || [ "$account_number" -gt "$count" ]; then
        echo -e "\n${RED}Nomor akun tidak valid!${NC}"
        sleep 2
        return
    fi
    
    # Ambil password yang dipilih
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
        echo -e "\n${RED}Akun tidak ditemukan!${NC}"
        sleep 2
        return
    fi
    
    echo -e "\n${YELLOW}Konfirmasi hapus akun: ${WHITE}$selected_password${NC}"
    read -p "  Yakin? (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "\n${YELLOW}Dibatalkan.${NC}"
        sleep 1
        return
    fi
    
    # Hapus dari user database
    sed -i "/^${selected_password}:/d" "$USER_DB"
    
    # Hapus dari config.json
    jq --arg pass "$selected_password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE"
    
    # Hapus device tracking
    sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
    
    # Unban IP jika ada
    awk -F: -v user="$selected_password" '$1 == user {print $2}' "$BAN_LIST" | while read ip; do
        unban_ip "$ip"
    done
    
    echo -e "\n${GREEN}Akun berhasil dihapus!${NC}"
    
    restart_zivpn
    sleep 2
}

# List akun
function list_accounts() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                     ${WHITE}DAFTAR AKUN${BLUE}                          ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
    else
        echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${LIGHT_BLUE}║ ${WHITE}No.  Nama Client           Password               Limit     Sisa Hari${BLUE}               ║${NC}"
        echo -e "${LIGHT_BLUE}╠══════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
        
        local count=0
        local current_date=$(date +%s)
        local total_active=0
        local total_expired=0
        
        while IFS=':' read -r password expiry_date max_devices client_name; do
            if [[ -n "$password" ]]; then
                count=$((count + 1))
                local remaining_seconds=$((expiry_date - current_date))
                
                if [ $remaining_seconds -gt 0 ]; then
                    local remaining_days=$((remaining_seconds / 86400))
                    printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-20s %-20s %-8s %s hari${BLUE}                    ║\n" \
                        "$count" "$client_name" "$password" "$max_devices" "$remaining_days"
                    total_active=$((total_active + 1))
                else
                    printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-20s %-20s %-8s ${RED}Expired${BLUE}                     ║\n" \
                        "$count" "$client_name" "$password" "$max_devices"
                    total_expired=$((total_expired + 1))
                fi
            fi
        done < "$USER_DB"
        
        echo -e "${LIGHT_BLUE}╠══════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${LIGHT_BLUE}║ ${WHITE}Total: ${count} akun | ${GREEN}Aktif: ${total_active} | ${RED}Expired: ${total_expired}${BLUE}                            ║${NC}"
        echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
    fi
    
    echo ""
    read -p "  Tekan Enter untuk kembali ke menu..."
}

# Renew akun
function renew_account() {
    clear
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "  Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                      ${WHITE}RENEW AKUN${BLUE}                          ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║ ${WHITE}No.  Nama Client           Password               Limit     Sisa Hari${BLUE}               ║${NC}"
    echo -e "${LIGHT_BLUE}╠══════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    local count=0
    local current_date=$(date +%s)
    
    while IFS=':' read -r password expiry_date max_devices client_name; do
        if [[ -n "$password" ]]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - current_date))
            local remaining_days=$((remaining_seconds / 86400))
            
            if [ $remaining_days -gt 0 ]; then
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-20s %-20s %-8s %s hari${BLUE}                    ║\n" \
                    "$count" "$client_name" "$password" "$max_devices" "$remaining_days"
            else
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-20s %-20s %-8s ${RED}Expired${BLUE}                     ║\n" \
                    "$count" "$client_name" "$password" "$max_devices"
            fi
        fi
    done < "$USER_DB"
    
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "  Masukkan nomor akun [1-$count]: " account_number
    
    if ! [[ "$account_number" =~ ^[0-9]+$ ]] || [ "$account_number" -lt 1 ] || [ "$account_number" -gt "$count" ]; then
        echo -e "\n${RED}Nomor akun tidak valid!${NC}"
        sleep 2
        return
    fi
    
    # Ambil data akun
    local selected_password=""
    local current_expiry=0
    local current_max_devices=0
    local current_name=""
    local current=0
    
    while IFS=':' read -r password expiry_date max_devices client_name; do
        if [[ -n "$password" ]]; then
            current=$((current + 1))
            if [ $current -eq $account_number ]; then
                selected_password=$password
                current_expiry=$expiry_date
                current_max_devices=$max_devices
                current_name=$client_name
                break
            fi
        fi
    done < "$USER_DB"
    
    if [ -z "$selected_password" ]; then
        echo -e "\n${RED}Akun tidak ditemukan!${NC}"
        sleep 2
        return
    fi
    
    echo -e "\n${LIGHT_CYAN}Akun terpilih: ${WHITE}$current_name ($selected_password)${NC}"
    read -p "  Tambah berapa hari? : " add_days
    
    if ! [[ "$add_days" =~ ^[0-9]+$ ]] || [ "$add_days" -lt 1 ]; then
        echo -e "\n${RED}Jumlah hari tidak valid!${NC}"
        sleep 2
        return
    fi
    
    # Hitung expiry baru
    local new_expiry=$((current_expiry + (add_days * 86400)))
    local new_expiry_formatted=$(date -d "@$new_expiry" +"%d %B %Y")
    
    # Update database
    sed -i "s/^${selected_password}:${current_expiry}:${current_max_devices}:${current_name}$/${selected_password}:${new_expiry}:${current_max_devices}:${current_name}/" "$USER_DB"
    
    # Unlock account jika terkunci
    unlock_account "$selected_password"
    
    # Reset device tracking
    sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
    
    echo -e "\n${GREEN}✅ Akun berhasil di-renew!${NC}"
    echo -e "${LIGHT_BLUE}Ditambahkan ${add_days} hari"
    echo -e "Expiry baru: ${new_expiry_formatted}${NC}"
    
    restart_zivpn
    sleep 2
}

# ================================================
# --- FUNGSI BAN MANAGEMENT ---
# ================================================

# List banned IPs
function list_banned_ips() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                     ${WHITE}DAFTAR IP BANNED${BLUE}                     ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ ! -f "$BAN_LIST" ] || [ ! -s "$BAN_LIST" ]; then
        echo -e "${GREEN}Tidak ada IP yang di-ban.${NC}"
    else
        echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${LIGHT_BLUE}║ ${WHITE}No.  IP Address            Waktu Ban              Alasan${BLUE}                         ║${NC}"
        echo -e "${LIGHT_BLUE}╠══════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
        
        local count=0
        local current_date=$(date +%s)
        
        while IFS=':' read -r ip timestamp reason; do
            if [[ -n "$ip" ]]; then
                count=$((count + 1))
                local ban_time=$(date -d "@$timestamp" +"%d/%m %H:%M")
                local hours_ago=$(( (current_date - timestamp) / 3600 ))
                
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-20s %-20s %s${BLUE}                    ║\n" \
                    "$count" "$ip" "$ban_time" "$reason"
            fi
        done < "$BAN_LIST"
        
        echo -e "${LIGHT_BLUE}╠══════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${LIGHT_BLUE}║ ${WHITE}Total: ${count} IP banned${BLUE}                                                     ║${NC}"
        echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
        
        echo -e "\n${YELLOW}Options:${NC}"
        echo -e "  ${WHITE}u [nomor]${NC} - Unban IP"
        echo -e "  ${WHITE}c${NC}        - Clear all bans"
        echo -e "  ${WHITE}0${NC}        - Kembali"
        echo ""
        
        read -p "  Pilih: " option
        
        case $option in
            u*)
                local num=${option:1}
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$count" ]; then
                    local banned_ip=""
                    local current=0
                    while IFS=':' read -r ip timestamp reason; do
                        if [[ -n "$ip" ]]; then
                            current=$((current + 1))
                            if [ $current -eq $num ]; then
                                banned_ip=$ip
                                break
                            fi
                        fi
                    done < "$BAN_LIST"
                    
                    if [ -n "$banned_ip" ]; then
                        unban_ip "$banned_ip"
                        echo -e "\n${GREEN}IP $banned_ip berhasil di-unban!${NC}"
                        sleep 2
                    fi
                fi
                ;;
            c)
                read -p "  Yakin hapus semua ban? (y/n): " confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    > "$BAN_LIST"
                    echo -e "\n${GREEN}Semua ban berhasil dihapus!${NC}"
                    sleep 2
                fi
                ;;
        esac
    fi
    
    read -p "  Tekan Enter untuk kembali..."
}

# ================================================
# --- FUNGSI TELEGRAM & BACKUP ---
# ================================================

# Setup Telegram
function telegram_setup() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                     ${WHITE}TELEGRAM SETUP${BLUE}                      ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "  Bot Token  : " bot_token
    read -p "  Chat ID    : " chat_id
    
    if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
        echo -e "\n${RED}Token dan Chat ID tidak boleh kosong!${NC}"
        sleep 2
        return
    fi
    
    # Simpan config
    echo "TELEGRAM_BOT_TOKEN=$bot_token" > /etc/zivpn/telegram.conf
    echo "TELEGRAM_CHAT_ID=$chat_id" >> /etc/zivpn/telegram.conf
    
    echo -e "\n${GREEN}✅ Telegram berhasil diatur!${NC}"
    
    # Test connection
    echo -e "${YELLOW}Menguji koneksi...${NC}"
    response=$(curl -s "https://api.telegram.org/bot${bot_token}/getMe")
    
    if echo "$response" | grep -q '"ok":true'; then
        echo -e "${GREEN}Bot valid!${NC}"
    else
        echo -e "${YELLOW}Bot mungkin tidak valid${NC}"
    fi
    
    sleep 2
}

# Backup data
function backup_data() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                      ${WHITE}BACKUP DATA${BLUE}                         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    mkdir -p /backup/zivpn
    local backup_file="/backup/zivpn/zivpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    echo -e "${YELLOW}Membuat backup...${NC}"
    tar -czf "$backup_file" -C /etc zivpn/ 2>/dev/null
    
    if [ -f "$backup_file" ]; then
        local file_size=$(du -h "$backup_file" | cut -f1)
        echo -e "\n${GREEN}✅ Backup berhasil dibuat!${NC}"
        echo -e "${LIGHT_BLUE}File: $backup_file"
        echo -e "Size: $file_size${NC}"
        
        # Kirim ke Telegram jika config ada
        if [ -f "/etc/zivpn/telegram.conf" ]; then
            source /etc/zivpn/telegram.conf
            if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
                echo -e "\n${YELLOW}Mengirim ke Telegram...${NC}"
                curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                    -d "chat_id=${TELEGRAM_CHAT_ID}" \
                    -d "text=📦 Backup ZIVPN Berhasil!
📅 $(date '+%d/%m/%Y %H:%M:%S')
💾 Size: $file_size
🔐 Total Akun: $(wc -l < "$USER_DB")" \
                    --form "document=@$backup_file" \
                    > /dev/null 2>&1
                echo -e "${GREEN}✅ Terkirim ke Telegram!${NC}"
            fi
        fi
    else
        echo -e "\n${RED}❌ Gagal membuat backup!${NC}"
    fi
    
    echo ""
    read -p "  Tekan Enter untuk kembali..."
}

# ================================================
# --- MAIN MENU ---
# ================================================

# Tampilkan main menu
function show_menu() {
    while true; do
        # Cleanup expired bans setiap kali buka menu
        cleanup_expired_bans
        
        display_banner
        display_system_info
        
        # Main Menu
        echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                    ${WHITE}ZIVPN MAIN MENU${BLUE}                        ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${BLUE}║                                                              ║${NC}"
        echo -e "${BLUE}║   ${WHITE}1) ${CYAN}BUAT AKUN BARU${BLUE}                                 ${WHITE}6) ${CYAN}BANNED IP LIST${BLUE}        ║${NC}"
        echo -e "${BLUE}║   ${WHITE}2) ${CYAN}HAPUS AKUN${BLUE}                                     ${WHITE}7) ${CYAN}TELEGRAM SETUP${BLUE}        ║${NC}"
        echo -e "${BLUE}║   ${WHITE}3) ${CYAN}RENEW AKUN${BLUE}                                     ${WHITE}8) ${CYAN}BACKUP DATA${BLUE}           ║${NC}"
        echo -e "${BLUE}║   ${WHITE}4) ${CYAN}LIST AKUN${BLUE}                                      ${WHITE}9) ${CYAN}RESTART SERVICE${BLUE}       ║${NC}"
        echo -e "${BLUE}║   ${WHITE}5) ${CYAN}UBAH PASSWORD${BLUE}                                  ${WHITE}0) ${CYAN}EXIT${BLUE}                  ║${NC}"
        echo -e "${BLUE}║                                                              ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${BLUE}║     ${YELLOW}⚠️  AUTO-BAN SYSTEM: Melebihi limit = AUTO BAN!${BLUE}       ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${BLUE}║              ${YELLOW}PONDOK VPN - Telegram: @bendakerep${BLUE}              ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -p "  Pilih menu [0-9]: " choice

        case $choice in
            1) create_account ;;
            2) delete_account ;;
            3) renew_account ;;
            4) list_accounts ;;
            5) echo -e "\n${YELLOW}Fitur ubah password dalam pengembangan...${NC}"; sleep 2 ;;
            6) list_banned_ips ;;
            7) telegram_setup ;;
            8) backup_data ;;
            9) restart_zivpn ;;
            0) 
                echo -e "\n${GREEN}Terima kasih! Goodbye! 👋${NC}\n"
                exit 0
                ;;
            *) 
                echo -e "\n${RED}Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

# ================================================
# --- START PROGRAM ---
# ================================================

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check dependencies
    check_dependencies
    
    # Initialize files
    initialize_files
    
    # Show menu
    show_menu
fi
