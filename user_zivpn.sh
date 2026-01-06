#!/bin/bash
# Zivpn UDP Module Manager - NO LICENSE VERSION
# Pondok VPN - udp-zi Edition

# --- UI Definitions ---
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD_WHITE='\033[1;37m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
LIGHT_GREEN='\033[1;32m'
NC='\033[0m' # No Color

# --- Utility Functions ---
function restart_zivpn() {
    echo "Restarting ZIVPN service..."
    systemctl restart zivpn.service
    echo "Service restarted."
}

# --- Internal Logic Functions (for API calls) ---
function _create_account_api_logic() {
    local password_base="$1"
    local days="$2"
    local db_file="/etc/zivpn/users.db"

    if [ -z "$password_base" ] || [ -z "$days" ]; then
        echo "Error: Password and days are required."
        return 1
    fi

    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid number of days."
        return 1
    fi

    # Generate random suffix and create the new password
    local random_suffix
    random_suffix=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 6)
    local password="${password_base}${random_suffix}"

    if grep -q "^${password}:" "$db_file"; then
        echo "Error: A user with the generated password '${password}' already exists. Please try again."
        return 1
    fi

    local expiry_date
    expiry_date=$(date -d "+$days days" +%s)
    echo "${password}:${expiry_date}" >> "$db_file"

    jq --arg pass "$password" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json

    if [ $? -eq 0 ]; then
        echo "Success: Account '${password_base}' created with password '${password}', expires in ${days} days."
        restart_zivpn
        return 0
    else
        sed -i "/^${password}:/d" "$db_file"
        echo "Error: Failed to update config.json."
        return 1
    fi
}

function _create_account_logic() {
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

# --- Core Logic Functions ---
function create_manual_account() {
    echo "--- Create New Zivpn Account ---"
    read -p "Enter new password: " password
    if [ -z "$password" ]; then
        echo "Password cannot be empty."
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
            EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y")
            
            clear
            echo "🔹Informasi Akun zivpn Anda🔹"
            echo "┌─────────────────────"
            echo "│ Host: $HOST"
            echo "│ Pass: $password"
            echo "│ Expire: $EXPIRE_FORMATTED"
            echo "└─────────────────────"
            echo "♨ᵗᵉʳⁱᵐᵃᵏᵃˢⁱʰ ᵗᵉˡᵃʰ ᵐᵉⁿᵍᵍᵘⁿᵃᵏᵃⁿ ˡᵃʸᵃⁿᵃⁿ ᵏᵃᵐⁱ♨"
        fi
    else
        echo "$result"
    fi
    
    read -p "Tekan Enter untuk kembali ke menu..."
}

function _generate_api_key() {
    clear
    echo "--- Generate API Authentication Key ---"
    
    local api_key
    api_key=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 6)
    
    local key_file="/etc/zivpn/api_auth.key"
    
    echo "$api_key" > "$key_file"
    chmod 600 "$key_file"
    
    echo "New API authentication key has been generated and saved."
    echo "Key: ${api_key}"
    
    echo "Sending API key to Telegram..."
    local server_ip
    server_ip=$(curl -s ifconfig.me)
    local cert_cn
    cert_cn=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p' 2>/dev/null || echo "")
    local domain
    if [ "$cert_cn" == "zivpn" ] || [ -z "$cert_cn" ]; then
        domain=$server_ip
    else
        domain=$cert_cn
    fi
    
    /usr/local/bin/zivpn_helper.sh api-key-notification "$api_key" "$server_ip" "$domain"
    
    read -p "Tekan Enter untuk kembali ke menu..."
}

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
    echo "--- Create Trial Zivpn Account ---"
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
            echo "🔹Informasi Akun zivpn Anda🔹"
            echo "┌─────────────────────"
            echo "│ Host: $HOST"
            echo "│ Pass: $password"
            echo "│ Expire: $EXPIRE_FORMATTED"
            echo "└─────────────────────"
            echo "♨ᵗᵉʳⁱᵐᵃᵏᵃˢⁱʰ ᵗᵉˡᵃʰ ᵐᵉⁿᵍᵍᵘⁿᵃᵏᵃⁿ ˡᵃʸᵃⁿᵃⁿ ᵏᵃᵐⁱ♨"
        fi
    else
        echo "$result"
    fi
    
    read -p "Tekan Enter untuk kembali ke menu..."
}

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

function renew_account() {
    clear
    echo "--- Renew Account ---"
    _display_accounts
    echo ""
    read -p "Enter password to renew: " password
    if [ -z "$password" ]; then
        echo "Password cannot be empty."
        return
    fi

    read -p "Enter number of days to extend: " days
    if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
        echo "Invalid number of days. Please enter a positive number."
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
        echo "Account '${password}' has been renewed. New expiry date: ${new_expiry_formatted}."
    else
        echo "$result"
    fi
    read -p "Tekan Enter untuk kembali ke menu..."
}

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
        echo "Error: Password '${password}' not found."
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
    echo "--- Delete Account ---"
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

function change_domain() {
    echo "--- Change Domain ---"
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

function _display_accounts() {
    local db_file="/etc/zivpn/users.db"

    if [ ! -f "$db_file" ] || [ ! -s "$db_file" ]; then
        echo "No accounts found."
        return
    fi

    local current_date
    current_date=$(date +%s)
    printf "%-20s | %s\n" "Password" "Expires in (days)"
    echo "------------------------------------------"
    while IFS=':' read -r password expiry_date; do
        if [[ -n "$password" ]]; then
            local remaining_seconds=$((expiry_date - current_date))
            if [ $remaining_seconds -gt 0 ]; then
                local remaining_days=$((remaining_seconds / 86400))
                printf "%-20s | %s days\n" "$password" "$remaining_days"
            else
                printf "%-20s | Expired\n" "$password"
            fi
        fi
    done < "$db_file"
    echo "------------------------------------------"
}

function list_accounts() {
    clear
    echo "--- Active Accounts ---"
    _display_accounts
    echo ""
    read -p "Press Enter to return to the menu..."
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

function _draw_info_panel() {
    local os_info isp_info ip_info host_info bw_today bw_month

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

    # --- NO LICENSE INFO ---
    local client_name="Pondok VPN"
    local license_exp="Lifetime"

    printf "  ${RED}%-7s${BOLD_WHITE}%-18s ${RED}%-6s${BOLD_WHITE}%-19s${NC}\n" "OS:" "${os_info}" "ISP:" "${isp_info}"
    printf "  ${RED}%-7s${BOLD_WHITE}%-18s ${RED}%-6s${BOLD_WHITE}%-19s${NC}\n" "IP:" "${ip_info}" "Host:" "${host_info}"
    printf "  ${RED}%-7s${BOLD_WHITE}%-18s ${RED}%-6s${BOLD_WHITE}%-19s${NC}\n" "Client:" "${client_name}" "EXP:" "${license_exp}"
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

function setup_auto_backup() {
    echo "--- Configure Auto Backup ---"
    if [ ! -f "/etc/zivpn/telegram.conf" ]; then
        echo "Telegram is not configured. Please run a manual backup once to set it up."
        return
    fi

    read -p "Enter backup interval in hours (e.g., 6, 12, 24). Enter 0 to disable: " interval
    if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
        echo "Invalid input. Please enter a number."
        return
    fi

    (crontab -l 2>/dev/null | grep -v "# zivpn-auto-backup") | crontab -

    if [ "$interval" -gt 0 ]; then
        local cron_schedule="0 */${interval} * * *"
        (crontab -l 2>/dev/null; echo "${cron_schedule} /usr/local/bin/zivpn_helper.sh backup >/dev/null 2>&1 # zivpn-auto-backup") | crontab -
        echo "Auto backup scheduled to run every ${interval} hour(s)."
    else
        echo "Auto backup has been disabled."
    fi
}

function create_account() {
    clear
    echo -e "${YELLOW}╔════════════════// ${RED}Create Account${YELLOW} //════════════════╗${NC}"
    echo -e "${YELLOW}║                                                    ║${NC}"
    echo -e "${YELLOW}║   ${RED}1)${NC} ${BOLD_WHITE}Create Zivpn                                  ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}2)${NC} ${BOLD_WHITE}Trial Zivpn                                   ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}0)${NC} ${BOLD_WHITE}Back to Main Menu                             ${YELLOW}║${NC}"
    echo -e "${YELLOW}║                                                    ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════╝${NC}"
    
    read -p "Enter your choice [0-2]: " choice

    case $choice in
        1) create_manual_account ;;
        2) create_trial_account ;;
        0) return ;;
        *) echo "Invalid option." ;;
    esac
}

function show_backup_menu() {
    clear
    echo -e "${YELLOW}╔═══════════════// ${RED}Backup/Restore${YELLOW} //═══════════════╗${NC}"
    echo -e "${YELLOW}║                                                  ║${NC}"
    echo -e "${YELLOW}║   ${RED}1)${NC} ${BOLD_WHITE}Backup Data                                 ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}2)${NC} ${BOLD_WHITE}Restore Data                                ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}3)${NC} ${BOLD_WHITE}Auto Backup                                 ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}4)${NC} ${BOLD_WHITE}Atur Ulang Notifikasi Telegram              ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}0)${NC} ${BOLD_WHITE}Back to Main Menu                           ${YELLOW}║${NC}"
    echo -e "${YELLOW}║                                                  ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
    
    read -p "Enter your choice [0-4]: " choice
    
    case $choice in
        1) /usr/local/bin/zivpn_helper.sh backup ;;
        2) /usr/local/bin/zivpn_helper.sh restore ;;
        3) setup_auto_backup ;;
        4) /usr/local/bin/zivpn_helper.sh setup-telegram ;;
        0) return ;;
        *) echo "Invalid option." ;;
    esac
}

function show_menu() {
    clear
    figlet "PONDOK VPN" | lolcat
    
    echo -e "${YELLOW}╔══════════════════// ${CYAN}PONDOK VPN${YELLOW} //═══════════════════╗${NC}"
    _draw_info_panel
    _draw_service_status
    echo -e "${YELLOW}║                                                    ║${NC}"
    echo -e "${YELLOW}║   ${RED}1)${NC} ${BOLD_WHITE}Create Account                                ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}2)${NC} ${BOLD_WHITE}Renew Account                                 ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}3)${NC} ${BOLD_WHITE}Delete Account                                ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}4)${NC} ${BOLD_WHITE}Change Domain                                 ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}5)${NC} ${BOLD_WHITE}List Accounts                                 ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}6)${NC} ${BOLD_WHITE}Backup/Restore                                ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}7)${NC} ${BOLD_WHITE}Generate API Auth Key                         ${YELLOW}║${NC}"
    echo -e "${YELLOW}║   ${RED}0)${NC} ${BOLD_WHITE}Exit                                          ${YELLOW}║${NC}"
    echo -e "${YELLOW}║                                                    ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════╝${NC}"
    
    read -p "Enter your choice [0-7]: " choice

    case $choice in
        1) create_account ;;
        2) renew_account ;;
        3) delete_account ;;
        4) change_domain ;;
        5) list_accounts ;;
        6) show_backup_menu ;;
        7) _generate_api_key ;;
        0) exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
}

# --- Main Installation and Setup Logic ---
function run_setup() {
    echo "=== ZIVPN MANAGER SETUP - NO LICENSE REQUIRED ==="
    echo "--- Starting Base Installation ---"
    
    # Download base installer
    wget -O zi.sh https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/zi.sh
    if [ $? -ne 0 ]; then 
        echo "Failed to download base installer. Installing manually..."
        # Manual install fallback
        apt update && apt install -y curl wget sqlite3 openssl
        wget -O /usr/local/bin/zivpn https://github.com/zivpn/zivpn/releases/latest/download/zivpn-linux-amd64
        chmod +x /usr/local/bin/zivpn
        mkdir -p /etc/zivpn
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout /etc/zivpn/zivpn.key \
            -out /etc/zivpn/zivpn.crt \
            -subj "/C=ID/CN=zivpn"
        echo '{"listen":":5667","cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn","auth":{"mode":"db","config":"/etc/zivpn/users.db"}}' > /etc/zivpn/config.json
        sqlite3 /etc/zivpn/users.db "CREATE TABLE users (username TEXT, password TEXT);"
        cat > /etc/systemd/system/zivpn.service << EOF
[Unit]
Description=ZiVPN
After=network.target
[Service]
ExecStart=/usr/local/bin/zivpn -c /etc/zivpn/config.json
Restart=always
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable zivpn
        systemctl start zivpn
    else
        chmod +x zi.sh
        ./zi.sh
        rm zi.sh
    fi
    
    echo "--- Base Installation Complete ---"
    echo "--- Setting up Advanced Management ---"

    # Install dependencies
    if ! command -v jq &> /dev/null || ! command -v curl &> /dev/null || ! command -v zip &> /dev/null || ! command -v figlet &> /dev/null || ! command -v lolcat &> /dev/null || ! command -v vnstat &> /dev/null; then
        echo "Installing dependencies (jq, curl, zip, figlet, lolcat, vnstat)..."
        apt-get update && apt-get install -y jq curl zip figlet lolcat vnstat
    fi

    # vnstat setup
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
    
    # Download helper script
    echo "Downloading helper script..."
    wget -O /usr/local/bin/zivpn_helper.sh https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/zivpn_helper.sh 2>/dev/null || \
    wget -O /usr/local/bin/zivpn_helper.sh https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/zivpn_helper.sh 2>/dev/null || {
        echo "Failed to download helper script. Creating local version..."
        # Create basic helper if download fails
        cat > /usr/local/bin/zivpn_helper.sh << 'HELPER'
#!/bin/bash
echo "ZiVPN Helper - Install Telegram configuration first"
echo "Usage: $0 {setup-telegram|backup|restore}"
HELPER
    }
    chmod +x /usr/local/bin/zivpn_helper.sh

    # Clear initial passwords
    echo "Setting up fresh configuration..."
    jq '.auth.config = []' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json 2>/dev/null || true
    touch /etc/zivpn/users.db

    # Expiry check cron
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
    (crontab -l 2>/dev/null | grep -v "# zivpn-expiry-check"; echo "* * * * * /etc/zivpn/expire_check.sh # zivpn-expiry-check") | crontab -

    # Telegram setup prompt
    echo "--- Telegram Notification Setup ---"
    read -p "Setup Telegram notifications now? (y/n): " tg_setup
    if [[ "$tg_setup" == [yY] ]]; then
        /usr/local/bin/zivpn_helper.sh setup-telegram 2>/dev/null || echo "Run 'zivpn_helper.sh setup-telegram' later to configure Telegram"
    fi

    restart_zivpn

    # System integration
    echo "--- Integrating management script into the system ---"
    cp "$0" /usr/local/bin/zivpn-manager
    chmod +x /usr/local/bin/zivpn-manager

    # Add alias to profile
    PROFILE_FILE="/root/.bashrc"
    [ -f "/root/.bash_profile" ] && PROFILE_FILE="/root/.bash_profile"
    
    if ! grep -q "alias menu='/usr/local/bin/zivpn-manager'" "$PROFILE_FILE"; then
        echo "alias menu='/usr/local/bin/zivpn-manager'" >> "$PROFILE_FILE"
    fi

    echo "====================================================="
    echo "SETUP COMPLETE! Use 'menu' command to manage ZiVPN"
    echo "====================================================="
    read -p "Press Enter to continue to the management menu..."
}

# --- Main Script ---
function main() {
    # Non-interactive mode for API calls
    if [ "$#" -gt 0 ]; then
        local command="$1"
        shift
        case "$command" in
            create_account)
                _create_account_api_logic "$@"
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

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi