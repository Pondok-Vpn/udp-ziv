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

# ================================================
# --- Utility Functions ---
function restart_zivpn() {
    echo "Restarting ZIVPN service..."
    systemctl restart zivpn.service
    echo "Service restarted."
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
                echo -e "${YELLOW}Deleting expired account: ${password}${NC}"
                deleted_count=$((deleted_count + 1))
                
                # Hapus dari config.json jika file ada
                if [ -f "$CONFIG_FILE" ]; then
                    jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE" 2>/dev/null
                fi
            fi
        fi
    done < "$USER_DB"
    
    # Ganti file database dengan yang baru
    mv "$temp_file" "$USER_DB"
    
    if [ $deleted_count -gt 0 ]; then
        echo -e "${GREEN}Deleted $deleted_count expired accounts${NC}"
        restart_zivpn
    fi
}

# --- Create Account (tanpa limit IP) ---
function create_account() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       ${WHITE}CREATE ACCOUNT - ZIVPN${BLUE}            ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Hapus akun expired sebelum membuat akun baru
    delete_expired_accounts
    
    read -p "Masukkan nama pelanggan: " client_name
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

    # Cek apakah password sudah ada
    if grep -q "^${password}:" "$USER_DB"; then
        echo -e "${YELLOW}Password '${password}' sudah ada.${NC}"
        echo -e "${YELLOW}Gunakan password yang berbeda.${NC}"
        sleep 2
        return
    fi

    local expiry_date
    expiry_date=$(date -d "+$days days" +%s)
    
    # Format: password:expiry_date:client_name
    echo "${password}:${expiry_date}:${client_name}" >> "$USER_DB"
    
    # Tambahkan ke config.json ZIVPN
    if [ -f "$CONFIG_FILE" ]; then
        jq --arg pass "$password" '.auth.config += [$pass]' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE"
    fi
    
    local CERT_CN
    if [ -f "/etc/zivpn/zivpn.crt" ]; then
        CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p' 2>/dev/null)
    fi
    
    local HOST
    if [ "$CERT_CN" == "zivpn" ] || [ -z "$CERT_CN" ]; then
        HOST=$(curl -s ifconfig.me)
    else
        HOST=$CERT_CN
    fi

    local EXPIRE_FORMATTED
    EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y")
    
    clear
    echo -e "${BLUE}╔══════════════════════════╗${NC}"
    echo -e "${BLUE}║  ${WHITE}✅ ACCOUNT CREATED SUCCESSFULLY${BLUE} ║${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Name: ${WHITE}$client_name${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Host: ${WHITE}$HOST${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Pass: ${WHITE}$password${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Expiry: ${WHITE}$EXPIRE_FORMATTED${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${WHITE}⚠️  Unlimited IP/Devices${NC}"
    echo -e "${BLUE}║${WHITE}   No IP restrictions${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}Thank you for ordering!${NC}"
    echo -e "${BLUE}║${YELLOW}PONDOK VPN${NC}"
    echo -e "${BLUE}╚══════════════════════════╝${NC}"
    
    restart_zivpn
    read -p "Press Enter to return to menu..."
}

# --- Create Trial Account ---
function trial_account() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        ${WHITE}TRIAL ACCOUNT - ZIVPN${BLUE}            ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Hapus akun expired sebelum membuat trial baru
    delete_expired_accounts
    
    read -p "Masukkan nama pelanggan: " client_name
    if [ -z "$client_name" ]; then
        echo -e "${RED}Nama tidak boleh kosong.${NC}"
        return
    fi

    read -p "Masukkan masa aktif (menit): " minutes
    if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Jumlah menit tidak valid.${NC}"
        return
    fi

    # Generate password trial otomatis
    local password="trial$(shuf -i 10000-99999 -n 1)"
    
    local expiry_date
    expiry_date=$(date -d "+$minutes minutes" +%s)
    
    # Format: password:expiry_date:client_name
    echo "${password}:${expiry_date}:${client_name}" >> "$USER_DB"
    
    # Tambahkan ke config.json ZIVPN
    if [ -f "$CONFIG_FILE" ]; then
        jq --arg pass "$password" '.auth.config += [$pass]' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE"
    fi
    
    local CERT_CN
    if [ -f "/etc/zivpn/zivpn.crt" ]; then
        CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p' 2>/dev/null)
    fi
    
    local HOST
    if [ "$CERT_CN" == "zivpn" ] || [ -z "$CERT_CN" ]; then
        HOST=$(curl -s ifconfig.me)
    else
        HOST=$CERT_CN
    fi

    local EXPIRE_FORMATTED
    EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y %H:%M:%S")
    
    clear
    echo -e "${BLUE}╔══════════════════════════╗${NC}"
    echo -e "${BLUE}║  ${WHITE}✅ TRIAL ACCOUNT CREATED${BLUE}      ║${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Name: ${WHITE}$client_name${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Host: ${WHITE}$HOST${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Pass: ${WHITE}$password${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Expiry: ${WHITE}$EXPIRE_FORMATTED${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${YELLOW}⚠️  TRIAL ACCOUNT - 1 Device Only${NC}"
    echo -e "${BLUE}║${WHITE}   For testing purposes${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}Thank you for trying!${NC}"
    echo -e "${BLUE}║${YELLOW}PONDOK VPN${NC}"
    echo -e "${BLUE}╚══════════════════════════╝${NC}"
    
    restart_zivpn
    read -p "Press Enter to return to menu..."
}

# --- Renew Account ---
function renew_account() {
    clear
    
    # Hapus akun expired terlebih dahulu
    delete_expired_accounts
    
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${YELLOW}No accounts found.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${WHITE}RENEW ACCOUNT${BLUE}                  ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${LIGHT_BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${LIGHT_BLUE}  ${WHITE}No.  Name               Password           Expiry${NC}"
    echo -e "${LIGHT_BLUE}══════════════════════════════════════════════════${NC}"
    
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
    
    echo -e "${LIGHT_BLUE}══════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}No accounts found.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    
    read -p "Enter account number to renew [1-$count]: " account_number
    
    if ! [[ "$account_number" =~ ^[0-9]+$ ]] || [ "$account_number" -lt 1 ] || [ "$account_number" -gt "$count" ]; then
        echo -e "${RED}Invalid account number!${NC}"
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
        echo -e "${RED}Account not found!${NC}"
        sleep 2
        return
    fi
    
    echo ""
    echo -e "${LIGHT_GREEN}Selected account:${NC}"
    echo -e "${WHITE}Name: ${current_client_name}${NC}"
    echo -e "${WHITE}Password: ${selected_password}${NC}"
    echo ""
    
    echo -e "${LIGHT_BLUE}1) ${WHITE}Extend expiry date${NC}"
    echo -e "${LIGHT_BLUE}2) ${WHITE}Change password${NC}"
    echo ""
    read -p "Select option [1-2]: " renew_option
    
    case $renew_option in
        1)
            read -p "Enter days to add: " days
            if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
                echo -e "${RED}Invalid number of days!${NC}"
                sleep 2
                return
            fi
            
            local seconds_to_add=$((days * 86400))
            local new_expiry_date=$((current_expiry_date + seconds_to_add))
            
            # Update database
            sed -i "s/^${selected_password}:.*/${selected_password}:${new_expiry_date}:${current_client_name}/" "$USER_DB"
            
            local new_expiry_formatted
            new_expiry_formatted=$(date -d "@$new_expiry_date" +"%d %B %Y")
            echo -e "${GREEN}Account '${selected_password}' extended by ${days} days.${NC}"
            echo -e "${LIGHT_BLUE}New expiry: ${WHITE}${new_expiry_formatted}${NC}"
            ;;
        2)
            read -p "Enter new password: " new_password
            if [ -z "$new_password" ]; then
                echo -e "${RED}Password cannot be empty!${NC}"
                sleep 2
                return
            fi
            
            if grep -q "^${new_password}:" "$USER_DB"; then
                echo -e "${RED}Password '${new_password}' already exists!${NC}"
                sleep 2
                return
            fi
            
            # Update database
            sed -i "s/^${selected_password}:.*/${new_password}:${current_expiry_date}:${current_client_name}/" "$USER_DB"
            
            # Update config.json
            if [ -f "$CONFIG_FILE" ]; then
                jq --arg old "$selected_password" --arg new "$new_password" '.auth.config |= map(if . == $old then $new else . end)' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE"
            fi
            
            echo -e "${GREEN}Password changed successfully!${NC}"
            echo -e "${LIGHT_BLUE}Old password: ${WHITE}${selected_password}${NC}"
            echo -e "${LIGHT_BLUE}New password: ${WHITE}${new_password}${NC}"
            ;;
        *)
            echo -e "${RED}Invalid option!${NC}"
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
        echo -e "${YELLOW}No accounts found.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${WHITE}DELETE ACCOUNT${BLUE}                 ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${LIGHT_BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${LIGHT_BLUE}  ${WHITE}No.  Name               Password           Expiry${NC}"
    echo -e "${LIGHT_BLUE}══════════════════════════════════════════════════${NC}"
    
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
    
    echo -e "${LIGHT_BLUE}══════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}No accounts found.${NC}"
        read -p "Press Enter to return..."
        return
    fi
    
    read -p "Enter account number to delete [1-$count]: " account_number
    
    if ! [[ "$account_number" =~ ^[0-9]+$ ]] || [ "$account_number" -lt 1 ] || [ "$account_number" -gt "$count" ]; then
        echo -e "${RED}Invalid account number!${NC}"
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
        echo -e "${RED}Account not found!${NC}"
        sleep 2
        return
    fi
    
    echo ""
    echo -e "${YELLOW}Are you sure you want to delete account:${NC}"
    echo -e "${WHITE}Name: ${current_client_name}${NC}"
    echo -e "${WHITE}Password: ${selected_password}${NC}"
    read -p "Confirm (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Deletion cancelled.${NC}"
        sleep 1
        return
    fi
    
    # Hapus dari database
    sed -i "/^${selected_password}:/d" "$USER_DB"
    
    # Hapus dari config.json
    if [ -f "$CONFIG_FILE" ]; then
        jq --arg pass "$selected_password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_FILE"
    fi
    
    echo -e "${GREEN}Account '${selected_password}' deleted successfully.${NC}"
    
    restart_zivpn
    sleep 2
}

# --- Add Bot Token ---
function add_bot_token() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          ${WHITE}ADD BOT TOKEN${BLUE}                   ║${NC}"
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
    echo -e "${YELLOW}Testing message sending...${NC}"
    if command -v curl &> /dev/null; then
        response=$(curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
            -d "chat_id=${chat_id}" \
            -d "text=✅ ZIVPN Bot Telegram successfully configured!")
        
        if [[ $response == *"ok\":true"* ]]; then
            echo -e "${GREEN}Test message sent successfully!${NC}"
        else
            echo -e "${YELLOW}Failed to send test message (maybe Chat ID is wrong)${NC}"
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
    echo -e "${LIGHT_BLUE}║   ${WHITE}0) ${CYAN}Back to Menu${LIGHT_BLUE}                        ║${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Select menu [0-2]: " choice
    
    case $choice in
        1)
            echo "Creating backup..."
            mkdir -p /backup/zivpn
            cp -r /etc/zivpn /backup/zivpn/
            tar -czf /backup/zivpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz /backup/zivpn
            echo -e "${GREEN}Backup created successfully!${NC}"
            
            # Kirim notifikasi ke Telegram jika ada
            if [ -f "/etc/zivpn/telegram.conf" ]; then
                source /etc/zivpn/telegram.conf 2>/dev/null
                if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                        -d "chat_id=${TELEGRAM_CHAT_ID}" \
                        -d "text=✅ Backup berhasil dibuat! 
📁 File: zivpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz
📅 Date: $(date '+%d %B %Y %H:%M:%S')
📱 PONDOK VPN" \
                        -d "parse_mode=Markdown" > /dev/null 2>&1
                fi
            fi
            
            sleep 2
            ;;
        2)
            echo "Restore data..."
            echo -e "${YELLOW}Restore feature under development${NC}"
            sleep 2
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}Invalid choice!${NC}"
            sleep 1
            ;;
    esac
}

# --- Restart Service ---
function restart_service() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${WHITE}RESTART SERVICE${BLUE}                ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Hapus akun expired terlebih dahulu
    delete_expired_accounts
    
    echo -e "${YELLOW}Restarting ZIVPN service...${NC}"
    restart_zivpn
    echo -e "${GREEN}Service restarted successfully!${NC}"
    
    # Kirim notifikasi ke Telegram jika ada
    if [ -f "/etc/zivpn/telegram.conf" ]; then
        source /etc/zivpn/telegram.conf 2>/dev/null
        if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d "chat_id=${TELEGRAM_CHAT_ID}" \
                -d "text=🔄 ZIVPN service has been restarted!
✅ Service is active and running
📅 $(date '+%d %B %Y %H:%M:%S')
📱 PONDOK VPN" \
                -d "parse_mode=Markdown" > /dev/null 2>&1
        fi
    fi
    
    read -p "Press Enter to return to menu..."
}

# --- Domain Management Functions ---
function change_domain() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              ${WHITE}CHANGE DOMAIN${BLUE}               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    local current_domain=""
    if [ -f "/etc/zivpn/zivpn.crt" ]; then
        current_domain=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    fi
    
    if [ -n "$current_domain" ]; then
        echo -e "${LIGHT_BLUE}Current domain: ${WHITE}${current_domain}${NC}"
        echo ""
    fi
    
    read -p "Enter new domain (example: vpn.pondok.com): " domain
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain cannot be empty!${NC}"
        sleep 2
        return
    fi
    
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}Invalid domain format!${NC}"
        sleep 2
        return
    fi
    
    echo ""
    echo -e "${LIGHT_BLUE}Creating SSL certificate for domain: ${WHITE}${domain}${NC}"
    echo -e "${YELLOW}This process may take a few seconds...${NC}"
    
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=PONDOK VPN/OU=VPN Service/CN=${domain}" \
        -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SSL certificate created successfully for ${domain}${NC}"
        
        if [ -f "/etc/zivpn/config.json" ]; then
            cp /etc/zivpn/config.json /etc/zivpn/config.json.backup
            
            jq --arg domain "$domain" '.tls.sni = $domain' /etc/zivpn/config.json > /tmp/config.json.tmp
            if [ $? -eq 0 ]; then
                mv /tmp/config.json.tmp /etc/zivpn/config.json
                
                echo -e "${LIGHT_GREEN}Domain successfully changed to ${domain}${NC}"
                restart_zivpn
                
                echo ""
                echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
                echo -e "${BLUE}║        ${WHITE}✅ DOMAIN CHANGED SUCCESSFULLY${BLUE}      ║${NC}"
                echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
                echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Old Domain: ${WHITE}${current_domain:-"None"}${BLUE}  ║${NC}"
                echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 New Domain: ${WHITE}${domain}${BLUE}               ║${NC}"
                echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Status: ${WHITE}Active${BLUE}                       ║${NC}"
                echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 SSL: ${WHITE}Valid (365 days)${BLUE}              ║${NC}"
                echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
                echo -e "${BLUE}║   ${YELLOW}ZIVPN Service has been restarted${BLUE}     ║${NC}"
                echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
            else
                echo -e "${RED}Failed to update config.json!${NC}"
                cp /etc/zivpn/config.json.backup /etc/zivpn/config.json
            fi
        fi
    else
        echo -e "${RED}Failed to create SSL certificate!${NC}"
    fi
    
    echo ""
    read -p "Press Enter to return to menu..."
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
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${LIGHT_CYAN}PONDOK VPN${BLUE}                    ║${NC}"
    echo -e "${BLUE}║        ${YELLOW}ZIVPN MANAGER${BLUE}                        ║${NC}"
    echo -e "${BLUE}║     ${WHITE}Telegram: @bendakerep${BLUE}                    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
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
        
        read -p "Select menu [0-7]: " choice

        case $choice in
            1) create_account ;;
            2) trial_account ;;
            3) renew_account ;;
            4) delete_account ;;
            5) add_bot_token ;;
            6) backup_restart ;;
            7) restart_service ;;
            0) 
                echo -e "${GREEN}Thank you!${NC}"
                exit 0
                ;;
            *) 
                echo -e "${RED}Invalid choice!${NC}"
                sleep 1
                ;;
        esac
    done
}

# --- Auto Install Dependencies ---
function install_dependencies() {
    echo -e "${YELLOW}Checking dependencies...${NC}"
    
    # Install jq untuk JSON parsing
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Installing jq...${NC}"
        apt-get update && apt-get install -y jq > /dev/null 2>&1
    fi
    
    # Install curl untuk HTTP requests
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}Installing curl...${NC}"
        apt-get install -y curl > /dev/null 2>&1
    fi
    
    echo -e "${GREEN}Dependencies ready!${NC}"
    sleep 1
}

# --- Main Execution ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Install dependencies jika belum ada
    install_dependencies
    
    # Initialize database if it doesn't exist
    if [ ! -f "$USER_DB" ]; then
        mkdir -p /etc/zivpn
        touch "$USER_DB"
        echo "# Format: password:expiry_timestamp:client_name" > "$USER_DB"
    fi
    
    # Create config.json if not exists
    if [ ! -f "$CONFIG_FILE" ]; then
        echo '{"auth": {"config": []}}' > "$CONFIG_FILE"
    fi
    
    # Hapus akun expired saat startup
    delete_expired_accounts
    
    show_menu
fi
