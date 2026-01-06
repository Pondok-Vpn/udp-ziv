#!/bin/bash
# ══════════════════════════════
# UDP ZIVPN MODULE MANAGER SHELL
# BY : PONDOK VPN (C) 2026-01-04
# TELEGRAM : @bendakerep
# EMAIL : redzall55@gmail.com
# ══════════════════════════════

# ════ VALIDASI WARNA ════
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD_WHITE='\033[1;37m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
LIGHT_GREEN='\033[1;32m'
NC='\033[0m' 
WHITE='\033[1;97m'
LIGHT_BLUE='\033[1;94m'
LIGHT_CYAN='\033[1;96m'
PURPLE='\033[1;95m'


# ════ Fungsi Utilitas ════
function backup_config() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p /etc/zivpn/backups
    cp /etc/zivpn/config.json "/etc/zivpn/backups/config_${timestamp}.json" 2>/dev/null
    cp /etc/zivpn/users.db "/etc/zivpn/backups/users_${timestamp}.db" 2>/dev/null
    echo "Backup created: config_${timestamp}.json"
}

function restart_zivpn() {
    echo "Restarting ZIVPN service..."
    systemctl restart zivpn.service
    echo "Service restarted."
}

function _create_account_logic() {
   backup_config
    local password="$1"
    local days="$2"
    local db_file="/etc/zivpn/users.db"
    if [ -z "$password" ] || [ -z "$days" ]; then
        echo "Error: Password and days are required."
        return 1
    fi
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid number of days."
        return 1
    fi
    if grep -q "^${password}:" "$db_file"; then
        echo "Error: Password '${password}' already exists."
        return 1
    fi
    local expiry_date
    expiry_date=$(date -d "+$days days" +%s)
    echo "${password}:${expiry_date}" >> "$db_file"
    jq --arg pass "$password" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    if [ $? -eq 0 ]; then
        echo "Success: Account '${password}' created, expires in ${days} days."
        restart_zivpn
        return 0
    else
        sed -i "/^${password}:/d" "$db_file"
        echo "Error: Failed to update config.json."
        return 1
    fi
}

# ════ Fungsi buat akun & Format akun ════
function create_manual_account() {
    echo "一═⌊✦⌉ 𝗕𝗨𝗔𝗧 𝗔𝗞𝗨𝗡 𝗭𝗜𝗩𝗣𝗡 ⌊✦⌉═一"
    read -p "Buat password: " password
    if [ -z "$password" ]; then
    echo -e "${RED}Password tidak boleh kosong.${NC}"
    return
    fi
    if [ ${#password} -lt 4 ]; then
    echo -e "${RED}Password minimal 4 karakter.${NC}"
    return
    fi
    read -p "Enter active period (in days): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo "Invalid number of days."
        return
    fi
    local result
    result=$(_create_account_logic "$password" "$days")
    if [[ "$result" == "Success"* ]]; then
        local db_file="/etc/zivpn/users.db"
        local user_line
        user_line=$(grep "^${password}:" "$db_file")
        if [ -n "$user_line" ]; then
            local expiry_date
            expiry_date=$(echo "$user_line" | cut -d: -f2)
            local CERT_CN
            CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
            local HOST
            if [ "$CERT_CN" == "zivpn" ]; then
                HOST=$(curl -s ifconfig.me)
            else
                HOST=$CERT_CN
            fi
            local EXPIRE_FORMATTED
            EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y") # BY : PONDOK VPN
            
            clear
    echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_GREEN}║     ${WHITE}✅ AKUN BERHASIL DIBUAT${LIGHT_GREEN}      ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Host: ${WHITE}$HOST${LIGHT_GREEN}                   ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Password: ${WHITE}$password${LIGHT_GREEN}           ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Expire: ${WHITE}$EXPIRE_FORMATTED${LIGHT_GREEN}     ║${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║   ${LIGHT_CYAN}Terima kasih sudah order!${LIGHT_GREEN}            ║${NC}"
    echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
        fi
    else
        echo "$result"
    fi
    read -p "Tekan Enter untuk kembali ke menu..."
}

# ════ Fungsi trial akun & Format akun ════
function _create_trial_account_logic() {
    local minutes="$1"
    local db_file="/etc/zivpn/users.db"
    if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid number of minutes."
        return 1
    fi
    local password="trial$(shuf -i 10000-99999 -n 1)"
    local expiry_date
    expiry_date=$(date -d "+$minutes minutes" +%s)
    echo "${password}:${expiry_date}" >> "$db_file"
    jq --arg pass "$password" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    if [ $? -eq 0 ]; then
        echo "Success: Trial account '${password}' created, expires in ${minutes} minutes."
        restart_zivpn
        return 0
    else
        sed -i "/^${password}:/d" "$db_file"
        echo "Error: Failed to update config.json."
        return 1
    fi
}

function create_trial_account() {
    echo "一═⌊✦⌉ 𝗕𝗨𝗔𝗧 𝗧𝗥𝗜𝗔𝗟 𝗔𝗞𝗨𝗡 𝗭𝗜𝗩𝗣𝗡 ⌊✦⌉═一"
    read -p "Enter active period (in minutes): " minutes
    if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
        echo "Invalid number of minutes."
        return
    fi
    local result
    result=$(_create_trial_account_logic "$minutes")
    if [[ "$result" == "Success"* ]]; then
        local password
        password=$(echo "$result" | sed -n "s/Success: Trial account '\([^']*\)'.*/\1/p")
        local db_file="/etc/zivpn/users.db"
        local user_line
        user_line=$(grep "^${password}:" "$db_file")
        if [ -n "$user_line" ]; then
            local expiry_date
            expiry_date=$(echo "$user_line" | cut -d: -f2)
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
    echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_GREEN}║     ${WHITE}✅ AKUN TRIAL BERHASIL DIBUAT${LIGHT_GREEN}  ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Host: ${WHITE}$HOST${LIGHT_GREEN}                   ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Password: ${WHITE}$password${LIGHT_GREEN}           ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Expire: ${WHITE}$EXPIRE_FORMATTED${LIGHT_GREEN}     ║${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║   ${LIGHT_CYAN}Terima kasih sudah order!${LIGHT_GREEN}            ║${NC}"
    echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
        fi
    else
        echo "$result"
    fi
    read -p "Tekan Enter untuk kembali ke menu..."
}

# ════ Fungsi perbaruan akun ════
function _renew_account_logic() {
    local password="$1"
    local days="$2"
    local db_file="/etc/zivpn/users.db"
    if [ -z "$password" ] || [ -z "$days" ]; then
        echo "Error: Password and days are required."
        return 1
    fi
    if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: Invalid number of days."
        return 1
    fi
    local user_line
    user_line=$(grep "^${password}:" "$db_file")
    if [ -z "$user_line" ]; then
        echo "Error: Account '${password}' not found."
        return 1
    fi
    local current_expiry_date
    current_expiry_date=$(echo "$user_line" | cut -d: -f2)

    if ! [[ "$current_expiry_date" =~ ^[0-9]+$ ]]; then
        echo "Error: Corrupted database entry for user '$password'."
        return 1
    fi
    local seconds_to_add=$((days * 86400))
    local new_expiry_date=$((current_expiry_date + seconds_to_add))
    sed -i "s/^${password}:.*/${password}:${new_expiry_date}/" "$db_file"
    echo "Success: Account '${password}' has been renewed for ${days} days."
    return 0
}

function _display_accounts() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║ ${LIGHT_CYAN}一═⌊✦⌉ 𝗗𝗔𝗙𝗧𝗔𝗥 𝗔𝗞𝗨𝗡 𝗔𝗞𝗧𝗜𝗙 ⌊✦⌉═一${PURPLE} ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"    echo ""
    echo ""
    USER_FILE="/etc/zivpn/users.db"
    if [ ! -f "$USER_FILE" ] || [ ! -s "$USER_FILE" ]; then
        echo -e "${YELLOW}Tidak ada akun ditemukan.${NC}"
        echo ""
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    local current_date
    current_date=$(date +%s)
    local count=0
    echo -e "${LIGHT_BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║ ${WHITE}No.  Password                              Expired${LIGHT_BLUE}       ║${NC}"
    echo -e "${LIGHT_BLUE}╠════════════════════════════════════════════════════════════════════╣${NC}"
    while IFS=':' read -r password expiry_date; do
        if [[ -n "$password" && -n "$expiry_date" ]]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - current_date))
            if [ "$remaining_seconds" -gt 0 ]; then
                local remaining_days=$((remaining_seconds / 86400))
                local expired_str
                expired_str=$(date -d "@$expiry_date" +"%d-%m-%Y")
                if [ "$remaining_days" -lt 1 ]; then
                    expired_str="<1 hari"
                fi
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-35s %-15s${LIGHT_BLUE} ║${NC}\n" \
                    "$count" "$password" "$expired_str"
            else
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-35s ${RED}EXPIRED${WHITE}         ${LIGHT_BLUE} ║${NC}\n" \
                    "$count" "$password"
            fi
        fi
    done < "$USER_FILE"
    echo -e "${LIGHT_BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${LIGHT_GREEN}Total akun: $count${NC}"
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

function renew_account() {
    clear
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║   ${LIGHT_CYAN}一═⌊✦⌉ 𝗥𝗘𝗡𝗘𝗪 𝗔𝗖𝗖𝗢𝗨𝗡𝗧 ⌊✦⌉═一${PURPLE}      ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
USER_FILE="/etc/zivpn/users.db"    if [ ! -f "$USER_FILE" ] || [ ! -s "$USER_FILE" ]; then
        echo -e "${YELLOW}Tidak ada akun ditemukan.${NC}"
        echo ""
        read -p "Tekan Enter untuk kembali ke menu..."
        return
    fi
    local current_date
    current_date=$(date +%s)
    local count=0
    declare -a account_list
    declare -a password_list
    echo -e "${LIGHT_BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║ ${WHITE}No.  Password                              Expired${LIGHT_BLUE}       ║${NC}"
    echo -e "${LIGHT_BLUE}╠════════════════════════════════════════════════════════════════════╣${NC}"
    while IFS=':' read -r password expiry_date; do
        if [[ -n "$password" && -n "$expiry_date" ]]; then
            count=$((count + 1))
            password_list[$count]=$password
            local remaining_seconds=$((expiry_date - current_date))
            if [ "$remaining_seconds" -gt 0 ]; then
                local remaining_days=$((remaining_seconds / 86400))
                local expired_str
                expired_str=$(date -d "@$expiry_date" +"%d-%m-%Y")
                if [ "$remaining_days" -lt 1 ]; then
                    expired_str="<1 hari"
                fi
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-35s %-15s${LIGHT_BLUE} ║${NC}\n" \
                    "$count" "$password" "$expired_str"
            else
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-35s ${RED}EXPIRED${WHITE}         ${LIGHT_BLUE} ║${NC}\n" \
                    "$count" "$password"
            fi
        fi
    done < "$USER_FILE"
    echo -e "${LIGHT_BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${LIGHT_GREEN}Total akun: $count${NC}"
    echo ""
    read -p "Masukkan nomor akun yang akan diperpanjang (0 untuk batal): " account_number
    if [ -z "$account_number" ] || [ "$account_number" -eq 0 ]; then
        echo -e "${YELLOW}Batal memperpanjang akun.${NC}"
        read -p "Tekan Enter untuk kembali ke menu..."
        return
    fi
    if ! [[ "$account_number" =~ ^[0-9]+$ ]] || [ "$account_number" -lt 1 ] || [ "$account_number" -gt "$count" ]; then
        echo -e "${RED}Nomor akun tidak valid.${NC}"
        read -p "Tekan Enter untuk kembali ke menu..."
        return
    fi
    local password="${password_list[$account_number]}"
    if [ -z "$password" ]; then
        echo -e "${RED}Gagal mendapatkan password dari nomor akun.${NC}"
        read -p "Tekan Enter untuk kembali ke menu..."
        return
    fi
    echo -e "${CYAN}Akun terpilih: ${WHITE}$password${NC}"
    read -p "Masukkan jumlah hari untuk memperpanjang: " days
    if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RED}Jumlah hari tidak valid. Harus angka positif.${NC}"
        read -p "Tekan Enter untuk kembali ke menu..."
        return
    fi
    local result
    result=$(_renew_account_logic "$password" "$days")
    if [[ "$result" == "Success"* ]]; then
        local db_file="/etc/zivpn/users.db"
        local user_line
        user_line=$(grep "^${password}:" "$db_file")
        local new_expiry_date
        new_expiry_date=$(echo "$user_line" | cut -d: -f2)
        local new_expiry_formatted
        new_expiry_formatted=$(date -d "@$new_expiry_date" +"%d %B %Y")
        echo ""
        echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
        echo -e "${LIGHT_GREEN}║     ${WHITE}✅ AKUN BERHASIL DIPERPANJANG${LIGHT_GREEN}    ║${NC}"
        echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
        echo -e "${LIGHT_GREEN}║                                          ║${NC}"
        echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Password: ${WHITE}$password${LIGHT_GREEN}           ║${NC}"
        echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Expire Baru: ${WHITE}$new_expiry_formatted${LIGHT_GREEN}  ║${NC}"
        echo -e "${LIGHT_GREEN}║                                          ║${NC}"
        echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
        echo -e "${LIGHT_GREEN}║   ${LIGHT_CYAN}Terima kasih sudah order!${LIGHT_GREEN}            ║${NC}"
        echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
    else
        echo ""
        echo -e "${RED}Gagal memperpanjang akun: $result${NC}"
    fi
    
    read -p "Tekan Enter untuk kembali ke menu..."
}

# ════ Fungsi hapus akun ════
function _delete_account_logic() {
    local password="$1"
    local db_file="/etc/zivpn/users.db"
    local config_file="/etc/zivpn/config.json"
    local tmp_config_file="${config_file}.tmp"
    if [ -z "$password" ]; then
        echo "Error: Password is required."
        return 1
    fi
    if [ ! -f "$db_file" ] || ! grep -q "^${password}:" "$db_file"; then
        echo "Error: Password '${password}' not found." # BY : @bendakerep
        return 1
    fi
    jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' "$config_file" > "$tmp_config_file"
    if [ $? -eq 0 ]; then
        sed -i "/^${password}:/d" "$db_file"
        mv "$tmp_config_file" "$config_file"
        echo "Success: Account '${password}' deleted."
        restart_zivpn
        return 0
    else
        rm -f "$tmp_config_file"
        echo "Error: Failed to update config.json. No changes were made."
        return 1
    fi
}

function delete_account() {
    clear
    echo "一═⌊✦⌉ 𝗛𝗔𝗣𝗨𝗦 𝗔𝗞𝗨𝗡 𝗭𝗜𝗩𝗣𝗡 ⌊✦⌉═一"
    _display_accounts
    echo ""
    read -p "Enter password to delete: " password
    if [ -z "$password" ]; then
        echo "Password cannot be empty."
        return
    fi
    local result
    result=$(_delete_account_logic "$password")
    echo "$result"
    read -p "Tekan Enter untuk kembali ke menu..."
}

# ════ Fungsi ganti domain ════
function change_domain() {
    echo "一═⌊✦⌉ 𝗚𝗔𝗡𝗧𝗜 𝗗𝗢𝗠𝗔𝗜𝗡 ⌊✦⌉═一"
    read -p "Enter the new domain name for the SSL certificate: " domain
    if [ -z "$domain" ]; then
        echo "Domain name cannot be empty."
        return
    fi
    echo "Generating new certificate for domain '${domain}'..."
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=${domain}" \
        -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
    echo "New certificate generated."
    restart_zivpn
}

function list_accounts() {
    _display_accounts
}

# ════ Fungsi format daftar akun ════
function _list_accounts() {
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║ ${LIGHT_CYAN}一═⌊✦⌉ 𝗗𝗔𝗙𝗧𝗔𝗥 𝗔𝗞𝗨𝗡 𝗔𝗞𝗧𝗜𝗙 ⌊✦⌉═一${PURPLE} ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"    echo ""
        USER_FILE="/etc/zivpn/users.db"
    if [ ! -f "$USER_FILE" ] || [ ! -s "$USER_FILE" ]; then
        echo -e "${YELLOW}Tidak ada akun ditemukan.${NC}"
        echo ""
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    local current_date
    current_date=$(date +%s)
    local count=0
    echo -e "${LIGHT_BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║ ${WHITE}No.  Password                              Expired${LIGHT_BLUE}       ║${NC}"
    echo -e "${LIGHT_BLUE}╠════════════════════════════════════════════════════════════════════╣${NC}"
    while IFS=':' read -r password expiry_date; do
        if [[ -n "$password" && -n "$expiry_date" ]]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - current_date))
            if [ "$remaining_seconds" -gt 0 ]; then
                local remaining_days=$((remaining_seconds / 86400))
                local expired_str
                expired_str=$(date -d "@$expiry_date" +"%d-%m-%Y")
                if [ "$remaining_days" -lt 1 ]; then
                    expired_str="<1 hari"
                fi
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-35s %-15s${LIGHT_BLUE} ║${NC}\n" \
                    "$count" "$password" "$expired_str"
            else
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-35s ${RED}EXPIRED${WHITE}         ${LIGHT_BLUE} ║${NC}\n" \
                    "$count" "$password"
            fi
        fi
    done < "$USER_FILE"
    echo -e "${LIGHT_BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${LIGHT_GREEN}Total akun: $count${NC}"
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

function format_kib_to_human() {
    local kib=$1
    if ! [[ "$kib" =~ ^[0-9]+$ ]] || [ -z "$kib" ]; then
        kib=0
    fi
    if [ "$kib" -lt 1048576 ]; then
        awk -v val="$kib" 'BEGIN { printf "%.2f MiB", val / 1024 }'
    else
        awk -v val="$kib" 'BEGIN { printf "%.2f GiB", val / 1048576 }'
    fi
}

function get_main_interface() {
    ip -o -4 route show to default | awk '{print $5}' | head -n 1
}

# ════ Fungsi informasi panel ════
function _draw_info_panel() {
    local os_info isp_info ip_info host_info bw_today bw_month client_name license_exp
    os_info=$( (hostnamectl 2>/dev/null | grep "Operating System" | cut -d: -f2 | sed 's/^[ \t]*//') || echo "N/A" )
    os_info=${os_info:-"N/A"}
    local ip_data
    ip_data=$(curl -s ipinfo.io)
    ip_info=$(echo "$ip_data" | jq -r '.ip // "N/A"')
    isp_info=$(echo "$ip_data" | jq -r '.org // "N/A"')
    ip_info=${ip_info:-"N/A"}
    isp_info=${isp_info:-"N/A"}
    local CERT_CN
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p' 2>/dev/null || echo "")
    if [ "$CERT_CN" == "zivpn" ] || [ -z "$CERT_CN" ]; then
        host_info=$ip_info
    else
        host_info=$CERT_CN
    fi
    host_info=${host_info:-"N/A"}
    if command -v vnstat &> /dev/null; then
        local iface
        iface=$(get_main_interface)
        local current_year current_month current_day
        current_year=$(date +%Y)
        current_month=$(date +%-m) 
        current_day=$(date +%-d)
        local today_total_kib=0
        local vnstat_daily_json
        vnstat_daily_json=$(vnstat --json d 2>/dev/null)
        if [[ -n "$vnstat_daily_json" && "$vnstat_daily_json" == "{"* ]]; then
            today_total_kib=$(echo "$vnstat_daily_json" | jq --arg iface "$iface" --argjson year "$current_year" --argjson month "$current_month" --argjson day "$current_day" '((.interfaces[] | select(.name == $iface) | .traffic.days // [])[] | select(.date.year == $year and .date.month == $month and .date.day == $day) | .total) // 0' | head -n 1)
        fi
        today_total_kib=${today_total_kib:-0}
        bw_today=$(format_kib_to_human "$today_total_kib")
        local month_total_kib=0
        local vnstat_monthly_json
        vnstat_monthly_json=$(vnstat --json m 2>/dev/null)
        if [[ -n "$vnstat_monthly_json" && "$vnstat_monthly_json" == "{"* ]]; then
            month_total_kib=$(echo "$vnstat_monthly_json" | jq --arg iface "$iface" --argjson year "$current_year" --argjson month "$current_month" '((.interfaces[] | select(.name == $iface) | .traffic.months // [])[] | select(.date.year == $year and .date.month == $month) | .total) // 0' | head -n 1)
        fi
        month_total_kib=${month_total_kib:-0}
        bw_month=$(format_kib_to_human "$month_total_kib")
    else
        bw_today="N/A"
        bw_month="N/A"
    fi
    if [ -f "$LICENSE_INFO_FILE" ]; then
        source "$LICENSE_INFO_FILE"
        client_name=${CLIENT_NAME:-"Registered"}
    else
        client_name="Registered"
    fi
    printf "  ${RED}%-7s${BOLD_WHITE}%-18s ${RED}%-6s${BOLD_WHITE}%-19s${NC}\n" "OS:" "${os_info}" "ISP:" "${isp_info}"
    printf "  ${RED}%-7s${BOLD_WHITE}%-18s ${RED}%-6s${BOLD_WHITE}%-19s${NC}\n" "IP:" "${ip_info}" "Host:" "${host_info}"
    printf "  ${RED}%-7s${BOLD_WHITE}%-18s ${RED}%-6s${BOLD_WHITE}%-19s${NC}\n" "Client:" "${client_name}" "Status:" "Active"
    printf "  ${RED}%-7s${BOLD_WHITE}%-18s ${RED}%-6s${BOLD_WHITE}%-19s${NC}\n" "Today:" "${bw_today}" "Month:" "${bw_month}"
}

function _draw_service_status() {
    local status_text status_color status_output
    local service_status
    service_status=$(systemctl is-active zivpn.service 2>/dev/null)
    if [ "$service_status" = "active" ]; then
        status_text="Running"
        status_color="${LIGHT_GREEN}"
    elif [ "$service_status" = "inactive" ]; then
        status_text="Stopped"
        status_color="${RED}"
    elif [ "$service_status" = "failed" ]; then
        status_text="Error"
        status_color="${RED}"
    else
        status_text="Unknown"
        status_color="${RED}"
    fi
    status_output="${CYAN}Service: ${status_color}${status_text}${NC}"
    local menu_width=55
    local text_len_visible
    text_len_visible=$(echo -e "$status_output" | sed 's/\x1b\[[0-9;]*m//g' | wc -c)
    text_len_visible=$((text_len_visible - 1))
    local padding_total=$((menu_width - text_len_visible))
    local padding_left=$((padding_total / 2))
    local padding_right=$((padding_total - padding_left))
    echo -e "${YELLOW}╠════════════════════════════════════════════════════╣${NC}"
    echo -e "$(printf '%*s' $padding_left)${status_output}$(printf '%*s' $padding_right)"
    echo -e "${YELLOW}╠════════════════════════════════════════════════════╣${NC}"
}

# ════ Template menu zivpn ════
function create_account() {
    clear
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║     ${LIGHT_CYAN}一═⌊✦⌉ 𝗖𝗥𝗘𝗔𝗧𝗘 𝗔𝗖𝗖𝗢𝗨𝗡𝗧 ⌊✦⌉═一${PURPLE}       ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                                                    ║${NC}"
    echo -e "${YELLOW}║     ${RED}1)${NC} ${BOLD_WHITE}Create Zivpn                                 ${YELLOW}║${NC}"
    echo -e "${YELLOW}║     ${RED}2)${NC} ${BOLD_WHITE}Trial Zivpn                                  ${YELLOW}║${NC}"
    echo -e "${YELLOW}║     ${RED}0)${NC} ${BOLD_WHITE}Back to Menu                                ${YELLOW}║${NC}"
    echo -e "${YELLOW}║                                                    ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════╝${NC}"    read -p "Pilih option [0-2]: " choice
    case $choice in
        1) create_manual_account ;;
        2) create_trial_account ;;
        0) return ;;
        *) echo "Invalid option" ;;
    esac
}

function show_menu() {
    clear
    figlet "PONDOK VPN" | lolcat
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║     ${LIGHT_CYAN}一═⌊✦⌉ 𝗨𝗗𝗣 𝗭𝗜𝗩𝗣𝗡 𝗣𝗥𝗘𝗠𝗜𝗨𝗠 ⌊✦⌉═一${PURPLE}      ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"    _draw_info_panel
        _draw_info_panel
    _draw_service_status
    echo -e "${YELLOW}║                                                    ║${NC}"
    echo -e "${YELLOW}║   ${RED}1)${NC} ${BOLD_WHITE}Create Account                                ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}2)${NC} ${BOLD_WHITE}Renew Account                                 ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}3)${NC} ${BOLD_WHITE}Delete Account                                ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}4)${NC} ${BOLD_WHITE}Change Domain                                 ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}5)${NC} ${BOLD_WHITE}List Accounts                                 ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}0)${NC} ${BOLD_WHITE}Exit                                          ${YELLOW}║${NC}"
    echo -e "${YELLOW}║                                                    ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════╝${NC}"
    read -p "pilih option [0-5]: " choice
    case $choice in
        1) create_account ;;
        2) renew_account ;;
        3) delete_account ;;
        4) change_domain ;;
        5) list_accounts ;;
        0) exit 0 ;;
        *) echo "Invalid option. silahkan pilih ulang." ;;
    esac
}

# ════ Fungsi inti ════
function run_setup() {
    verify_license
    echo "═[ Starting Base Installation ]═"
    wget -O zi.sh https://raw.githubusercontent.com/Pondok-Vpn/pondokvip/main/zi.sh
    if [ $? -ne 0 ]; then echo "Failed to download base installer. Aborting."; exit 1; fi
    chmod +x zi.sh
    ./zi.sh
    if [ $? -ne 0 ]; then echo "Base installation script failed. Aborting."; exit 1; fi
    rm zi.sh
    echo "═[ Base Installation Complete ]═"
    echo "--- Setting up Advanced Management ---"
    if ! command -v jq &> /dev/null || ! command -v curl &> /dev/null || ! command -v zip &> /dev/null || ! command -v figlet &> /dev/null || ! command -v lolcat &> /dev/null || ! command -v vnstat &> /dev/null; then
        echo "Installing dependencies (jq, curl, zip, figlet, lolcat, vnstat)..."
        apt-get update && apt-get install -y jq curl zip figlet lolcat vnstat
    fi
    echo "Configuring vnstat for bandwidth monitoring..."
    local net_interface
    net_interface=$(ip -o -4 route show to default | awk '{print $5}' | head -n 1)
    if [ -n "$net_interface" ]; then
        echo "Detected network interface: $net_interface"
        sleep 2
        systemctl stop vnstat
        vnstat -u -i "$net_interface" --force
        systemctl enable vnstat
        systemctl start vnstat
        echo "vnstat setup complete for interface $net_interface."
    else
        echo "Warning: Could not automatically detect network interface for vnstat."
    fi
    echo "Clearing initial password(s) set during base installation..."
    jq '.auth.config = []' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    touch /etc/zivpn/users.db
    RANDOM_PASS="zivpn$(shuf -i 10000-99999 -n 1)"
    EXPIRY_DATE=$(date -d "+1 day" +%s)
    echo "Creating a temporary initial account..."
    echo "${RANDOM_PASS}:${EXPIRY_DATE}" >> /etc/zivpn/users.db
    jq --arg pass "$RANDOM_PASS" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    echo "Setting up expiry check cron job..."
    cat <<'EOF' > /etc/zivpn/expire_check.sh
    
    #!/bin/bash
DB_FILE="/etc/zivpn/users.db"
CONFIG_FILE="/etc/zivpn/config.json"
TMP_DB_FILE="${DB_FILE}.tmp"
CURRENT_DATE=$(date +%s)
SERVICE_RESTART_NEEDED=false

if [ ! -f "$DB_FILE" ]; then exit 0; fi
> "$TMP_DB_FILE"

while IFS=':' read -r password expiry_date; do
    if [[ -z "$password" ]]; then continue; fi

    if [ "$expiry_date" -le "$CURRENT_DATE" ]; then
        echo "User '${password}' has expired. Deleting permanently."
        jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        SERVICE_RESTART_NEEDED=true
    else
        echo "${password}:${expiry_date}" >> "$TMP_DB_FILE"
    fi
done < "$DB_FILE"

mv "$TMP_DB_FILE" "$DB_FILE"

if [ "$SERVICE_RESTART_NEEDED" = true ]; then
    echo "Restarting zivpn service due to user removal."
    systemctl restart zivpn.service
fi
exit 0
EOF
    chmod +x /etc/zivpn/expire_check.sh
    CRON_JOB_EXPIRY="* * * * * /etc/zivpn/expire_check.sh # zivpn-expiry-check"
    (crontab -l 2>/dev/null | grep -v "# zivpn-expiry-check") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON_JOB_EXPIRY") | crontab -
    echo "Skipping license checker setup (expiry check disabled)."
    restart_zivpn
    echo "--- Setting Up REST API Service ---"
    if ! command -v node &> /dev/null; then
        echo "Node.js not found. Installing Node.js v18..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
    else
        echo "Node.js is already installed."
    fi
    mkdir -p /etc/zivpn/api
    cat <<'EOF' > /etc/zivpn/api/package.json
{
  "name": "zivpn-api",
  "version": "1.0.0",
  "description": "API for managing ZIVPN",
  "main": "api.js",
  "scripts": { "start": "node api.js" },
  "dependencies": { "express": "^4.17.1" }
}
EOF

    cat <<'EOF' > /etc/zivpn/api/api.js
const express = require('express');
const { execFile } = require('child_process');
const fs = require('fs');
const app = express();
const PORT = 5888;
const AUTH_KEY_PATH = '/etc/zivpn/api_auth.key';
const ZIVPN_MANAGER_SCRIPT = '/usr/local/bin/zivpn-manager';

const authenticate = (req, res, next) => {
    const providedAuthKey = req.query.auth;
    if (!providedAuthKey) return res.status(401).json({ status: 'error', message: 'Authentication key is required.' });

    fs.readFile(AUTH_KEY_PATH, 'utf8', (err, storedKey) => {
        if (err) return res.status(500).json({ status: 'error', message: 'Could not read authentication key.' });
        if (providedAuthKey.trim() !== storedKey.trim()) return res.status(403).json({ status: 'error', message: 'Invalid authentication key.' });
        next();
    });
};
app.use(authenticate);

const executeZivpnManager = (command, args, res) => {
    execFile('sudo', [ZIVPN_MANAGER_SCRIPT, command, ...args], (error, stdout, stderr) => {
        if (error) {
            const errorMessage = stderr.includes('Error:') ? stderr : 'An internal server error occurred.';
            return res.status(500).json({ status: 'error', message: errorMessage.trim() });
        }
        if (stdout.toLowerCase().includes('success')) {
            res.json({ status: 'success', message: stdout.trim() });
        else {
            res.status(400).json({ status: 'error', message: stdout.trim() });
        }
    });
};

app.all('/create/zivpn', (req, res) => {
    const { password, exp } = req.query;
    if (!password || !exp) return res.status(400).json({ status: 'error', message: 'Parameters password and exp are required.' });
    executeZivpnManager('create_account', [password, exp], res);
});
app.all('/delete/zivpn', (req, res) => {
    const { password } = req.query;
    if (!password) return res.status(400).json({ status: 'error', message: 'Parameter password is required.' });
    executeZivpnManager('delete_account', [password], res);
});
app.all('/renew/zivpn', (req, res) => {
    const { password, exp } = req.query;
    if (!password || !exp) return res.status(400).json({ status: 'error', message: 'Parameters password and exp are required.' });
    executeZivpnManager('renew_account', [password, exp], res);
});
app.all('/trial/zivpn', (req, res) => {
    const { exp } = req.query;
    if (!exp) return res.status(400).json({ status: 'error', message: 'Parameter exp is required.' });
    executeZivpnManager('trial_account', [exp], res);
});

app.listen(PORT, () => console.log('ZIVPN API server running on port ' + PORT));
EOF
    
    echo "Installing API dependencies..."
    npm install --prefix /etc/zivpn/api
    cat <<'EOF' > /etc/systemd/system/zivpn-api.service
[Unit]
Description=ZIVPN REST API Service
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn/api
ExecStart=/usr/bin/node /etc/zivpn/api/api.js
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable zivpn-api.service
    systemctl start zivpn-api.service
    echo "Generating initial API key..."
    local initial_api_key
    initial_api_key=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 6)
    echo "$initial_api_key" > /etc/zivpn/api_auth.key
    chmod 600 /etc/zivpn/api_auth.key
    echo "Opening firewall port 5888 for API..."
    iptables -I INPUT -p tcp --dport 5888 -j ACCEPT
    echo "--- API Setup Complete ---"
    echo "--- Integrating management script into the system ---" # BY : PONDOKVPN
    cp "$0" /usr/local/bin/zivpn-manager
    chmod +x /usr/local/bin/zivpn-manager
    PROFILE_FILE="/root/.bashrc"
    if [ -f "/root/.bash_profile" ]; then PROFILE_FILE="/root/.bash_profile"; fi
    ALIAS_CMD="alias menu='/usr/local/bin/zivpn-manager'"
    AUTORUN_CMD="/usr/local/bin/zivpn-manager"
    grep -qF "$ALIAS_CMD" "$PROFILE_FILE" || echo "$ALIAS_CMD" >> "$PROFILE_FILE"
    grep -qF "$AUTORUN_CMD" "$PROFILE_FILE" || echo "$AUTORUN_CMD" >> "$PROFILE_FILE"
    echo "The 'menu' command is now available."
    echo "The management menu will now open automatically on login."
    echo "-----------------------------------------------------"
    echo "Advanced management setup complete."
    echo "Password for temporary account (expires 24h): ${RANDOM_PASS}"
    echo "-----------------------------------------------------"
    read -p "Press Enter to continue to the management menu..."
}

function main() {
    if [ "$#" -gt 0 ]; then
        local command="$1"
        shift
        case "$command" in
            create_account)
                _create_account_logic "$@"
                ;;
            delete_account)
                _delete_account_logic "$@"
                ;;
            renew_account)
                _renew_account_logic "$@"
                ;;
            trial_account)
                _create_trial_account_logic "$@"
                ;;
            *)
                echo "Error: Unknown command '$command'"
                exit 1
                ;;
        esac
        exit $?
    fi
    if [ ! -f "/etc/systemd/system/zivpn.service" ]; then
        run_setup
    fi
    while true; do
        show_menu
    done
}
# 一═✦⌠𝗣𝗢𝗡𝗗𝗢𝗞 𝗩𝗣𝗡⌡✦═一
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
