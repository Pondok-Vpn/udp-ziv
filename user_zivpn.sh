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

# ================================================
# --- Utility Functions ---
function restart_zivpn() {
    echo "Restarting ZIVPN service..."
    
    # Cari process ZIVPN
    local zivpn_pid=$(ps aux | grep "zivpn server" | grep -v grep | head -1 | awk '{print $2}')
    
    if [ -n "$zivpn_pid" ]; then
        echo "Found ZIVPN process with PID: $zivpn_pid"
        kill -9 "$zivpn_pid" 2>/dev/null
        echo "Killed old ZIVPN process"
        sleep 1
    fi
    
    # Start ZIVPN
    nohup /usr/local/bin/zivpn server -listen ":5667" \
        -cert "/etc/zivpn/zivpn.crt" \
        -key "/etc/zivpn/zivpn.key" \
        -db "/etc/zivpn/users.db" > /dev/null 2>&1 &
    
    echo "ZIVPN service restarted"
    sleep 2
}

# --- Check Device Limit (simplified) ---
function check_device_limit() {
    local username="$1"
    local current_ip="$2"
    local max_devices=2  # Default limit 2 device/IP
    
    if [ ! -f "$DEVICE_DB" ]; then
        touch "$DEVICE_DB"
        return 0
    fi
    
    local device_count=$(grep -c "^${username}:" "$DEVICE_DB" 2>/dev/null || echo "0")
    
    if [ "$device_count" -ge "$max_devices" ]; then
        if ! grep -q "^${username}:${current_ip}" "$DEVICE_DB"; then
            echo -e "${RED}⚠️  Account ${username} exceeded device limit (max: $max_devices)${NC}"
            return 1
        fi
    fi
    
    return 0
}

# --- Auto Delete Expired Accounts ---
function delete_expired_accounts() {
    local current_timestamp=$(date +%s)
    local deleted_count=0
    
    if [ ! -f "$USER_DB" ]; then
        return
    fi
    
    local temp_file=$(mktemp)
    
    while IFS=':' read -r password expiry_date; do
        if [ -n "$password" ]; then
            if [ $expiry_date -gt $current_timestamp ]; then
                # Akun masih aktif
                echo "${password}:${expiry_date}" >> "$temp_file"
            else
                # Akun expired
                echo -e "${YELLOW}Deleting expired account: ${password}${NC}"
                deleted_count=$((deleted_count + 1))
                sed -i "/^${password}:/d" "$DEVICE_DB" 2>/dev/null
            fi
        fi
    done < "$USER_DB"
    
    mv "$temp_file" "$USER_DB"
    
    if [ $deleted_count -gt 0 ]; then
        echo -e "${GREEN}Deleted $deleted_count expired accounts${NC}"
        restart_zivpn
    fi
}

# --- Create Account (format: password:expiry_date) ---
function create_account() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       ${WHITE}CREATE ACCOUNT - PREMIUM${BLUE}            ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Hapus akun expired
    delete_expired_accounts
    
    read -p "Enter customer name: " client_name
    if [ -z "$client_name" ]; then
        echo -e "${RED}Name cannot be empty.${NC}"
        return
    fi

    read -p "Enter password: " password
    if [ -z "$password" ]; then
        echo -e "${RED}Password cannot be empty.${NC}"
        return
    fi

    read -p "Enter validity period (days): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid number of days.${NC}"
        return
    fi

    if grep -q "^${password}:" "$USER_DB"; then
        echo -e "${YELLOW}Password '${password}' already exists.${NC}"
        return
    fi

    local expiry_date
    expiry_date=$(date -d "+$days days" +%s)
    echo "${password}:${expiry_date}" >> "$USER_DB"
    
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
    echo -e "${BLUE}║  ${WHITE}✅  ACCOUNT CREATED SUCCESSFULLY${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Name: ${WHITE}$client_name${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Host: ${WHITE}$HOST${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Pass: ${WHITE}$password${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Expiry: ${WHITE}$EXPIRE_FORMATTED${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${YELLOW}⚠️  ATTENTION:${NC}"
    echo -e "${BLUE}║${WHITE}Limit: 2 IP/Device${NC}"
    echo -e "${BLUE}║${WHITE}Account will be locked if exceeds limit${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}Thank you for your order!${NC}"
    echo -e "${BLUE}║${YELLOW}PONDOK VPN${NC}"
    echo -e "${BLUE}╚══════════════════════════╝${NC}"
    
    restart_zivpn
    read -p "Press Enter to return to menu..."
}

# --- Create Trial Account ---
function trial_account() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        ${WHITE}CREATE TRIAL ACCOUNT${BLUE}              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    delete_expired_accounts
    
    read -p "Enter customer name: " client_name
    if [ -z "$client_name" ]; then
        echo -e "${RED}Name cannot be empty.${NC}"
        return
    fi

    read -p "Enter validity period (minutes): " minutes
    if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid number of minutes.${NC}"
        return
    fi

    local password="trial$(shuf -i 10000-99999 -n 1)"
    local expiry_date
    expiry_date=$(date -d "+$minutes minutes" +%s)
    echo "${password}:${expiry_date}" >> "$USER_DB"
    
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
    echo -e "${BLUE}║  ${WHITE}✅ TRIAL ACCOUNT CREATED${BLUE}      ║${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Name: ${WHITE}$client_name${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Host: ${WHITE}$HOST${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Pass: ${WHITE}$password${NC}"
    echo -e "${BLUE}║${LIGHT_CYAN}*Expire: ${WHITE}$EXPIRE_FORMATTED${NC}"
    echo -e "${BLUE}╠══════════════════════════╣${NC}"
    echo -e "${BLUE}║${YELLOW}⚠️  ATTENTION:${NC}"
    echo -e "${BLUE}║${WHITE}Limit: 1 IP/Device${NC}"
    echo -e "${BLUE}║${WHITE}Account will be locked if exceeds limit${NC}"
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
    echo -e "${LIGHT_BLUE}  ${WHITE}No.  Password           Expiry${NC}"
    echo -e "${LIGHT_BLUE}══════════════════════════════════════════════════${NC}"
    
    local count=0
    while IFS=':' read -r password expiry_date; do
        if [ -n "$password" ]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - $(date +%s)))
            local remaining_days=$((remaining_seconds / 86400))
            if [ $remaining_days -gt 0 ]; then
                local expire_date=$(date -d "@$expiry_date" +"%d-%m-%Y")
                printf "${LIGHT_BLUE}  ${WHITE}%2d. %-18s %s${NC}\n" "$count" "$password" "$expire_date"
            else
                printf "${LIGHT_BLUE}  ${WHITE}%2d. %-18s ${RED}Expired${NC}\n" "$count" "$password"
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
    local current=0
    while IFS=':' read -r password expiry_date; do
        if [ -n "$password" ]; then
            current=$((current + 1))
            if [ $current -eq $account_number ]; then
                selected_password=$password
                current_expiry_date=$expiry_date
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
            
            sed -i "s/^${selected_password}:.*/${selected_password}:${new_expiry_date}/" "$USER_DB"
            
            sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
            echo -e "${LIGHT_GREEN}Device tracking reset!${NC}"
            
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
            
            sed -i "s/^${selected_password}:.*/${new_password}:${current_expiry_date}/" "$USER_DB"
            
            sed -i "s/^${selected_password}:/${new_password}:/" "$DEVICE_DB" 2>/dev/null
            
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
    echo -e "${LIGHT_BLUE}  ${WHITE}No.  Password           Expiry${NC}"
    echo -e "${LIGHT_BLUE}══════════════════════════════════════════════════${NC}"
    
    local count=0
    while IFS=':' read -r password expiry_date; do
        if [ -n "$password" ]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - $(date +%s)))
            local remaining_days=$((remaining_seconds / 86400))
            if [ $remaining_days -gt 0 ]; then
                local expire_date=$(date -d "@$expiry_date" +"%d-%m-%Y")
                printf "${LIGHT_BLUE}  ${WHITE}%2d. %-18s %s${NC}\n" "$count" "$password" "$expire_date"
            else
                printf "${LIGHT_BLUE}  ${WHITE}%2d. %-18s ${RED}Expired${NC}\n" "$count" "$password"
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
    local current=0
    while IFS=':' read -r password expiry_date; do
        if [ -n "$password" ]; then
            current=$((current + 1))
            if [ $current -eq $account_number ]; then
                selected_password=$password
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
    echo -e "${WHITE}Password: ${selected_password}${NC}"
    read -p "Confirm (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Deletion cancelled.${NC}"
        sleep 1
        return
    fi
    
    sed -i "/^${selected_password}:/d" "$USER_DB"
    sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
    
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
    
    read -p "Enter Bot Token Telegram: " bot_token
    read -p "Enter Chat ID Telegram: " chat_id
    
    if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
        echo -e "${RED}Token and Chat ID cannot be empty!${NC}"
        sleep 2
        return
    fi
    
    mkdir -p /etc/zivpn
    echo "TELEGRAM_BOT_TOKEN=${bot_token}" > /etc/zivpn/telegram.conf
    echo "TELEGRAM_CHAT_ID=${chat_id}" >> /etc/zivpn/telegram.conf
    echo "TELEGRAM_ENABLED=true" >> /etc/zivpn/telegram.conf
    
    echo -e "${GREEN}Bot Telegram configured successfully!${NC}"
    echo -e "${LIGHT_BLUE}Token: ${WHITE}${bot_token:0:15}...${NC}"
    echo -e "${LIGHT_BLUE}Chat ID: ${WHITE}${chat_id}${NC}"
    
    if command -v curl &> /dev/null; then
        response=$(curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
            -d "chat_id=${chat_id}" \
            -d "text=✅ ZIVPN Bot Telegram successfully configured!")
        
        if [[ $response == *"ok\":true"* ]]; then
            echo -e "${GREEN}Test message sent successfully!${NC}"
        else
            echo -e "${YELLOW}Failed to send test message${NC}"
        fi
    fi
    
    sleep 3
}

# --- Restart Service ---
function restart_service() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${WHITE}RESTART SERVICE${BLUE}                ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    delete_expired_accounts
    restart_zivpn
    echo -e "${GREEN}Service restarted successfully!${NC}"
    
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
    
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=PONDOK VPN/OU=VPN Service/CN=${domain}" \
        -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SSL certificate created successfully for ${domain}${NC}"
        restart_zivpn
        
        echo ""
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║        ${WHITE}✅ DOMAIN CHANGED SUCCESSFULLY${BLUE}      ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
        echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Old Domain: ${WHITE}${current_domain:-"None"}${BLUE}  ║${NC}"
        echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 New Domain: ${WHITE}${domain}${BLUE}               ║${NC}"
        echo -e "${BLUE}║  ${LIGHT_CYAN}🔹 Status: ${WHITE}Active${BLUE}                       ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
        echo -e "${BLUE}║   ${YELLOW}ZIVPN Service has been restarted${BLUE}     ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    else
        echo -e "${RED}Failed to create SSL certificate!${NC}"
    fi
    
    echo ""
    read -p "Press Enter to return to menu..."
}

# --- Info Panel Function ---
function display_info_panel() {
    local os_info=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"' 2>/dev/null | cut -d' ' -f1-3 || echo "Unknown OS")
    local isp_info=$(curl -s ipinfo.io/org 2>/dev/null | head -1 | awk '{print $1}' || echo "Unknown ISP")
    local ip_info=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown IP")
    local host_info=""
    
    if [ -f "/etc/zivpn/zivpn.crt" ]; then
        host_info=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    fi
    
    if [ -z "$host_info" ] || [ "$host_info" == "zivpn" ]; then
        host_info=$ip_info
    fi
    
    isp_info=$(echo "$isp_info" | awk '{print $1}')
    os_info=$(echo "$os_info" | cut -d' ' -f1-2)
    
    if [ ${#ip_info} -gt 15 ]; then
        ip_info="${ip_info:0:15}..."
    fi
    
    if [ ${#host_info} -gt 15 ]; then
        host_info="${host_info:0:15}..."
    fi
    
    echo -e "${BLUE}╔═════════════════ ${GOLD}✦ UDP ZIVPN ✦ ${BLUE}══════════════════╗${NC}"
    printf "  ${RED}%-5s${GOLD}%-20s ${RED}%-5s${GOLD}%-23s\n" "OS:" "$os_info" "ISP:" "$isp_info"
    printf "  ${RED}%-5s${GOLD}%-20s ${RED}%-5s${GOLD}%-23s\n" "IP:" "$ip_info" "Host:" "$host_info"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
}

# --- Display Banner ---
function display_banner() {
    if command -v figlet &> /dev/null && command -v lolcat &> /dev/null; then
        clear
        figlet "PONDOK VPN" | lolcat
        echo ""
    else
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
        display_info_panel
        echo ""
        
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║             ${GOLD} ZIVPN MANAGER MENU ${BLUE}           ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
        echo -e "${BLUE}║                                          ║${NC}"
        echo -e "${BLUE}║   ${WHITE}1) ${CYAN}CREATE ACCOUNT${BLUE}     ${WHITE}5) ${CYAN}ADD BOT TOKEN${BLUE}  ║${NC}"
        echo -e "${BLUE}║   ${WHITE}2) ${CYAN}TRIAL ACCOUNT${BLUE}      ${WHITE}6) ${CYAN}BACKUP/RESTART${BLUE} ║${NC}"
        echo -e "${BLUE}║   ${WHITE}3) ${CYAN}RENEW ACCOUNT${BLUE}      ${WHITE}7) ${CYAN}RESTART SERVICE${BLUE} ║${NC}"
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
            6) 
                # Backup sederhana
                echo "Creating backup..."
                mkdir -p /backup/zivpn
                cp -r /etc/zivpn /backup/zivpn/
                echo -e "${GREEN}Backup created at /backup/zivpn${NC}"
                sleep 2
                ;;
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

# --- Main Execution ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    mkdir -p /etc/zivpn
    [ ! -f "$USER_DB" ] && touch "$USER_DB"
    [ ! -f "$DEVICE_DB" ] && touch "$DEVICE_DB"
    [ ! -f "$LOCKED_DB" ] && touch "$LOCKED_DB"
    
    delete_expired_accounts
    show_menu
fi
