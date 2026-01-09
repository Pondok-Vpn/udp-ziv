#!/bin/bash
# ===========================================
# ZIVPN USER MANAGEMENT - COMPLETE VERSION
# Version: 3.0
# Telegram: @bendakerep
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
CYAN='\033[0;96m'
PURPLE='\033[0;95m'
ORANGE='\033[38;5;214m'
LIGHT_CYAN='\033[1;96m'
WHITE='\033[1;37m'
NC='\033[0m'

# Paths
CONFIG_DIR="/etc/zivpn"
CONFIG_FILE="$CONFIG_DIR/config.json"
USER_DB="$CONFIG_DIR/users.db"
LOG_FILE="/var/log/zivpn_menu.log"
TELEGRAM_CONF="$CONFIG_DIR/telegram.conf"
BACKUP_DIR="/var/backups/zivpn"

# Logging
log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check and install figlet & lolcat
check_and_install_figlet() {
    if ! command -v figlet &> /dev/null; then
        echo -e "${YELLOW}Installing figlet...${NC}"
        apt-get update > /dev/null 2>&1
        apt-get install -y figlet > /dev/null 2>&1
    fi
    
    if ! command -v lolcat &> /dev/null; then
        echo -e "${YELLOW}Installing lolcat...${NC}"
        apt-get install -y lolcat > /dev/null 2>&1
    fi
}

# Get system info
get_system_info() {
    # IP Address
    IP_ADDRESS=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    # Host dari SSL
    if [ -f "$CONFIG_DIR/zivpn.crt" ]; then
        HOST_NAME=$(openssl x509 -in "$CONFIG_DIR/zivpn.crt" -noout -subject 2>/dev/null | sed -n 's/.*CN = //p')
        if [ "$HOST_NAME" = "zivpn" ] || [ -z "$HOST_NAME" ]; then
            HOST_NAME="$IP_ADDRESS"
        fi
    else
        HOST_NAME="$IP_ADDRESS"
    fi
    
    # OS Info
    OS_INFO=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Unknown")
    OS_SHORT=$(echo "$OS_INFO" | awk '{print $1}')
    
    # ISP Info
    ISP_INFO=$(curl -s ipinfo.io/org 2>/dev/null | cut -d' ' -f2- | head -1 || echo "Unknown")
    ISP_SHORT=$(echo "$ISP_INFO" | awk '{print $1}')
    
    # RAM Info - FIXED ERROR
    RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
    RAM_USED=$(free -m 2>/dev/null | awk '/^Mem:/{print $3}' || echo "0")
    
    # FIX: Arithmetic calculation tanpa 2>/dev/null di dalam $(( ))
    if [ "$RAM_TOTAL" -gt 0 ] 2>/dev/null; then
        RAM_PERCENT=$((RAM_USED * 100 / RAM_TOTAL))
    else
        RAM_PERCENT=0
    fi
    
    RAM_INFO="${RAM_USED}MB/${RAM_TOTAL}MB"
    
    # CPU Info
    CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | cut -d: -f2 | sed 's/^[ \t]*//' | head -1 || echo "Unknown")
    CPU_CORES=$(nproc 2>/dev/null || echo "1")
    CPU_INFO="$CPU_CORES cores"
    
    # License Info
    if [ -f "/etc/zivpn/.license_info" ]; then
        LICENSE_USER=$(head -1 /etc/zivpn/.license_info 2>/dev/null || echo "Unknown")
        LICENSE_EXP=$(tail -1 /etc/zivpn/.license_info 2>/dev/null || echo "Unknown")
    else
        LICENSE_USER="Unknown"
        LICENSE_EXP="Unknown"
    fi
    
    # Total Users
    TOTAL_USERS=$(wc -l < "$USER_DB" 2>/dev/null || echo "0")
    
    # Service Status
    if systemctl is-active --quiet zivpn.service; then
        SERVICE_STATUS="${GREEN}active${NC}"
    else
        SERVICE_STATUS="${RED}stopped${NC}"
    fi
}

# Display info panel
show_info_panel() {
    get_system_info
    
    clear
    
    check_and_install_figlet
    
    # Banner dengan figlet dan lolcat
    echo ""
    echo -e "${BLUE}"
    figlet -f small "PONDOK VPN" | lolcat
    echo -e "${NC}"
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE}  IP VPS : ${CYAN}$(printf '%-15s' "$IP_ADDRESS")${WHITE}        HOST : ${CYAN}$(printf '%-20s' "$HOST_NAME")${NC}"
    echo -e "${BLUE}║${WHITE}  OS     : ${CYAN}$(printf '%-15s' "$OS_SHORT")${WHITE}        EXP  : ${CYAN}$(printf '%-20s' "$LICENSE_EXP")${NC}"
    echo -e "${BLUE}║${WHITE}  ISP    : ${CYAN}$(printf '%-15s' "$ISP_SHORT")${WHITE}        RAM  : ${CYAN}$(printf '%-20s' "$RAM_INFO")${NC}"
    echo -e "${BLUE}║${WHITE}  CPU    : ${CYAN}$(printf '%-15s' "$CPU_INFO")${WHITE}        USER : ${CYAN}$(printf '%-20s' "$TOTAL_USERS")${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "                    ${WHITE}Status : ${SERVICE_STATUS}${NC}"
}

show_main_menu() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                    ║${NC}"
    echo -e "${BLUE}║${YELLOW}  1)${CYAN} BUAT AKUN ZIVPN${YELLOW}            5)${CYAN} BOT SETTING${WHITE}      ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                    ║${NC}"
    echo -e "${BLUE}║${YELLOW}  2)${CYAN} BUAT AKUN TRIAL${YELLOW}            6)${CYAN} BACK/REST${WHITE}        ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                    ║${NC}"
    echo -e "${BLUE}║${YELLOW}  3)${CYAN} RENEW AKUN${YELLOW}                 7)${CYAN} HAPUS AKUN${WHITE}       ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                    ║${NC}"
    echo -e "${BLUE}║${YELLOW}  4)${CYAN} RESTART SERVIS${YELLOW}             0)${CYAN} EXIT${WHITE}             ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
}

# Create account function
create_account() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f digital "CREATE ACCOUNT" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═══════════════════════════╗${NC}"
    echo -e "${WHITE}    📝 BUAT AKUN ZIVPN${NC}"
    echo -e "${BLUE}╚═══════════════════════════╝${NC}"
    
    echo ""
    read -p "Masukkan nama client: " client_name
    read -p "Masukkan password (min 6 karakter): " password
    read -p "Masukkan masa aktif (hari): " days
    
    # Validasi
    if [ -z "$client_name" ] || [ -z "$password" ] || [ -z "$days" ]; then
        echo -e "${RED}Error: Semua field harus diisi!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    if [ ${#password} -lt 6 ]; then
        echo -e "${RED}Error: Password minimal 6 karakter!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Masa aktif harus angka!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    # Generate expiry date
    expiry_date=$(date -d "+$days days" +"%d %B %Y")
    expiry_timestamp=$(date -d "+$days days" +%s)
    
    # Simpan ke database
    echo "$password:$expiry_timestamp:$client_name" >> "$USER_DB"
    
    # Update config.json
    if [ -f "$CONFIG_FILE" ]; then
        current_config=$(cat "$CONFIG_FILE")
        echo "$current_config" | jq --arg pass "$password" '.auth.config += [$pass]' > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
    
    # Restart service
    systemctl restart zivpn.service
    
    # Show success box
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f small "SUCCESS" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE} ✅ AKUN BERHASIL DIBUAT${NC}"
    echo -e "${BLUE}╠═════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} Nama client : ${CYAN}$client_name${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} IP/Host     : ${CYAN}$HOST_NAME${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} Password    : ${CYAN}$password${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} Expiry Date : ${CYAN}$expiry_date${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} Limit Device: ${CYAN}1 device${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}╠═════════════════════════╣${NC}"
    echo -e "${BLUE}║${RED}     ⚠️  PERINGATAN${NC}"
    echo -e "${BLUE}║${WHITE} Akun akan otomatis di-Band${NC}"
    echo -e "${BLUE}║${WHITE} jika IP melebihi ketentuan${NC}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}╠═════════════════════════╣${NC}"
    echo -e "${BLUE}║${WHITE} Terima kasih sudah order!${NC}"
    echo -e "${BLUE}║${WHITE} Bot: @bendakerep${NC}"
    echo -e "${BLUE}╚═════════════════════════╝${NC}"
    
    log_action "Created account: $client_name, expires: $expiry_date"
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

# Create trial account
create_trial_account() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f digital "TRIAL ACCOUNT" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═══════════════════════════╗${NC}"
    echo -e "${WHITE}    🆓 BUAT AKUN TRIAL${NC}"
    echo -e "${BLUE}╚═══════════════════════════╝${NC}"
    
    echo ""
    read -p "Masukkan masa aktif (menit): " minutes
    
    if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Masa aktif harus angka!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    # Generate password
    password="trial$(shuf -i 10000-99999 -n 1)"
    client_name="Trial User"
    
    # Generate expiry date
    expiry_date=$(date -d "+$minutes minutes" +"%d %B %Y %H:%M")
    expiry_timestamp=$(date -d "+$minutes minutes" +%s)
    
    # Simpan ke database
    echo "$password:$expiry_timestamp:$client_name" >> "$USER_DB"
    
    # Update config.json
    if [ -f "$CONFIG_FILE" ]; then
        current_config=$(cat "$CONFIG_FILE")
        echo "$current_config" | jq --arg pass "$password" '.auth.config += [$pass]' > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
    
    # Restart service
    systemctl restart zivpn.service
    
    # Show success box
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f small "SUCCESS" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═════════════════════════╗${NC}"
    echo -e "${WHITE}   ✅ AKUN TRIAL BERHASIL${NC}"
    echo -e "${BLUE}╠═════════════════════════╣${NC}"
    echo -e "║"
    echo -e "║  Nama client : ${CYAN}$client_name${WHITE}"
    echo -e "║"
    echo -e "║  IP/Host     : ${CYAN}$HOST_NAME${WHITE}"
    echo -e "║"
    echo -e "║  Password    : ${CYAN}$password${WHITE}"
    echo -e "║"
    echo -e "║  Expiry Date : ${CYAN}$expiry_date${WHITE}"
    echo -e "║"
    echo -e "║  Limit Device: ${CYAN}1 device${WHITE}"
    echo -e "║"
    echo -e "${BLUE}╠═════════════════════════╣${NC}"
    echo -e "${WHITE}        ⚠️  PERINGATAN${NC}"
    echo -e "${WHITE}   Akun akan otomatis di-Band${NC}"
    echo -e "${WHITE}    jika IP melebihi ketentuan${NC}"
    echo -e "${WHITE}"
    echo -e "${BLUE}╠═════════════════════════╣${NC}"
    echo -e "${WHITE}   Terima kasih sudah order!${NC}"
    echo -e "${WHITE}        @bendakerep${NC}"
    echo -e "${BLUE}╚═════════════════════════╝${NC}"
    
    log_action "Created trial account: $password, expires: $expiry_date"
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

# Renew account
renew_account() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f small "RENEW AKUN" | lolcat
    echo -e "${NC}"
    
    # Load accounts
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${RED}Tidak ada akun yang tersedia!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${BLUE}╔═════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE}                      RENEW AKUN                     ${BLUE}║${NC}"
    echo -e "${BLUE}╚═════════════════════════════════════════════════════╝${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}No.   Nama Client           Password          Expired${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    
    # Display accounts dengan format tabel rapi
    count=1
    while IFS=':' read -r password expiry_timestamp client_name; do
        if [ -n "$password" ]; then
            expiry_date=$(date -d "@$expiry_timestamp" +"%m-%d-%Y")
            printf "${WHITE}%-4s  ${CYAN}%-20s${WHITE}  %-15s  %-10s${NC}\n" "$count." "$client_name" "$password" "$expiry_date"
            count=$((count + 1))
        fi
    done < "$USER_DB"
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    read -p "Pilih nomor untuk renew akun: " choice
}
# Delete account
delete_account() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f small "HAPUS AKUN" | lolcat
    echo -e "${NC}"
    
    # Load accounts
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${RED}Tidak ada akun yang tersedia!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${BLUE}╔═════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE}                      HAPUS AKUN                      ${BLUE}║${NC}"
    echo -e "${BLUE}╚═════════════════════════════════════════════════════╝${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}No.   Nama Client           Password          Expired${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    
    # Display accounts dengan format tabel rapi
    count=1
    while IFS=':' read -r password expiry_timestamp client_name; do
        if [ -n "$password" ]; then
            expiry_date=$(date -d "@$expiry_timestamp" +"%m-%d-%Y")
            printf "${WHITE}%-4s  ${CYAN}%-20s${WHITE}  %-15s  %-10s${NC}\n" "$count." "$client_name" "$password" "$expiry_date"
            count=$((count + 1))
        fi
    done < "$USER_DB"
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    read -p "Pilih nomor untuk hapus akun: " choice
}

# Restart service
restart_service() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f small "RESTART" | lolcat
    echo -e "${NC}"
    
    echo -e "${YELLOW}Restarting ZIVPN service...${NC}"
    systemctl restart zivpn.service
    
    sleep 2
    
    if systemctl is-active --quiet zivpn.service; then
        echo -e "${GREEN}✅ Service berhasil di-restart!${NC}"
    else
        echo -e "${RED}❌ Gagal restart service!${NC}"
    fi
    
    log_action "Restarted ZIVPN service"
    
    read -p "Tekan Enter untuk kembali ke menu..."
}

# Bot setting (Telegram setup)
bot_setting() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f digital "_BOT SETTING" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═══════════════════════════╗${NC}"
    echo -e "${WHITE}    🤖 TELEGRAM BOT SETUP${NC}"
    echo -e "${BLUE}╚═══════════════════════════╝${NC}"
    
    echo ""
    echo -e "${CYAN}Instruksi:${NC}"
    echo "1. Buat bot via @BotFather"
    echo "2. Dapatkan bot token"
    echo "3. Dapatkan chat ID dari @userinfobot"
    echo ""
    
    read -p "Masukkan Bot Token: " bot_token
    read -p "Masukkan Chat ID  : " chat_id
    
    if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
        echo -e "${RED}Token dan Chat ID tidak boleh kosong!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    # Validasi format token
    if [[ ! "$bot_token" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Format token salah!${NC}"
        echo -e "${YELLOW}Contoh: 1234567890:ABCdefGHIjklMNopQRSTuvwxyz${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    # Test bot token
    echo -e "${YELLOW}Testing bot token...${NC}"
    response=$(curl -s "https://api.telegram.org/bot${bot_token}/getMe")
    
    if echo "$response" | grep -q '"ok":true'; then
        bot_name=$(echo "$response" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
        echo -e "${GREEN}✅ Bot ditemukan: @${bot_name}${NC}"
    else
        echo -e "${RED}❌ Token bot tidak valid!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    # Save configuration
    mkdir -p "$CONFIG_DIR"
    echo "TELEGRAM_BOT_TOKEN=${bot_token}" > "$TELEGRAM_CONF"
    echo "TELEGRAM_CHAT_ID=${chat_id}" >> "$TELEGRAM_CONF"
    chmod 600 "$TELEGRAM_CONF"
    
    # Send test message
    echo -e "${YELLOW}Mengirim pesan test...${NC}"
    
    message="✅ ZiVPN Telegram Bot Connected!
📅 $(date '+%Y-%m-%d %H:%M:%S')
🤖 Bot: @${bot_name}
📱 Ready to receive notifications!"
    
    curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${message}" \
        -d "parse_mode=Markdown" > /dev/null
    
    echo -e "${GREEN}✅ Telegram bot berhasil di-setup!${NC}"
    
    log_action "Telegram bot setup completed"
    
    read -p "Tekan Enter untuk kembali ke menu..."
}

# Backup/Restore menu
backup_restore() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f digital "BACKUP/RESTORE" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═══════════════════════════╗${NC}"
    echo -e "${WHITE}    💾 BACKUP & RESTORE${NC}"
    echo -e "${BLUE}╚═══════════════════════════╝${NC}"
    
    echo ""
    echo -e "${WHITE} 1)${CYAN} Backup Data${NC}"
    echo -e "${WHITE} 2)${CYAN} Restore Data${NC}"
    echo -e "${WHITE} 3)${CYAN} Auto Backup${NC}"
    echo -e "${WHITE} 0)${CYAN} Kembali${NC}"
    echo ""
    
    read -p "Pilih menu [0-3]: " choice
    
    case $choice in
        1)
            backup_data
            ;;
        2)
            restore_data
            ;;
        3)
            auto_backup_setup
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid!${NC}"
            read -p "Tekan Enter untuk kembali..."
            ;;
    esac
}

# Backup data
backup_data() {
    echo -e "${YELLOW}Membuat backup...${NC}"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Create backup file
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_file="${BACKUP_DIR}/zivpn_backup_${timestamp}.tar.gz"
    
    tar -czf "$backup_file" -C /etc zivpn/ 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Backup berhasil: ${backup_file}${NC}"
    else
        echo -e "${RED}❌ Gagal membuat backup!${NC}"
    fi
    
    read -p "Tekan Enter untuk kembali..."
}

# Restore data
restore_data() {
    echo -e "${YELLOW}Restoring data...${NC}"
    
    # List available backups
    backups=($(ls -1t "${BACKUP_DIR}/zivpn_backup_"*.tar.gz 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}Tidak ada backup yang tersedia!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${CYAN}Backup yang tersedia:${NC}"
    for i in "${!backups[@]}"; do
        echo "$((i+1)). $(basename ${backups[$i]})"
    done
    
    echo ""
    read -p "Pilih backup [1-${#backups[@]}]: " choice
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
        echo -e "${RED}Pilihan tidak valid!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    backup_file="${backups[$((choice-1))]}"
    
    read -p "Yakin restore dari $(basename $backup_file)? (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Dibatalkan!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    # Stop service
    systemctl stop zivpn.service
    
    # Restore
    tar -xzf "$backup_file" -C / 2>/dev/null
    
    # Start service
    systemctl start zivpn.service
    
    echo -e "${GREEN}✅ Restore berhasil!${NC}"
    
    log_action "Restored from backup: $(basename $backup_file)"
    
    read -p "Tekan Enter untuk kembali..."
}

# Auto backup setup
auto_backup_setup() {
    echo -e "${YELLOW}Setup auto backup...${NC}"
    
    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo -e "${RED}Telegram belum di-setup!${NC}"
        echo -e "${YELLOW}Setup Telegram terlebih dahulu di menu Bot Setting${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    read -p "Interval backup (jam, 0=disable): " interval
    
    if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Input tidak valid!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    # Remove existing cron job
    (crontab -l 2>/dev/null | grep -v "# zivpn-auto-backup") | crontab -
    
    if [ "$interval" -gt 0 ]; then
        # Add new cron job
        (crontab -l 2>/dev/null; echo "0 */${interval} * * * /usr/local/bin/zivpn_helper.sh backup # zivpn-auto-backup") | crontab -
        echo -e "${GREEN}✅ Auto backup di-set setiap ${interval} jam${NC}"
    else
        echo -e "${YELLOW}Auto backup dimatikan${NC}"
    fi
    
    read -p "Tekan Enter untuk kembali..."
}

# Main loop
main_menu() {
    while true; do
        show_info_panel
        show_main_menu
        
        echo ""
        read -p "Pilih menu (0-7): " choice
        
        case $choice in
            1)
                create_account
                ;;
            2)
                create_trial_account
                ;;
            3)
                renew_account
                ;;
            4)
                restart_service
                ;;
            5)
                bot_setting
                ;;
            6)
                backup_restore
                ;;
            7)
                delete_account
                ;;
            0)
                clear
                echo ""
                figlet -f small "PONDOK VPN" | lolcat
                echo -e "${CYAN}Terima kasih telah menggunakan ZIVPN!${NC}"
                echo -e "${WHITE}Telegram: @bendakerep${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Script harus dijalankan sebagai root!${NC}"
    echo -e "${YELLOW}Gunakan: sudo bash $0${NC}"
    exit 1
fi

# Check if ZIVPN is installed
if [ ! -f "/etc/systemd/system/zivpn.service" ]; then
    echo -e "${RED}ZIVPN belum terinstall!${NC}"
    echo -e "${YELLOW}Jalankan install_zivpn.sh terlebih dahulu${NC}"
    exit 1
fi

# Start main menu
main_menu
