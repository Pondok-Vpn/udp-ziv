#!/bin/bash
# ════════════════════════════════════════════════════════
# UDP ZIVPN MODULE MANAGER SHELL - PONDOK VPN EDITION
# BY : PONDOK VPN (C) 2026-01-04
# TELEGRAM : @bendakerep
# EMAIL : redzall55@gmail.com
# ════════════════════════════════════════════════════════

# ════ VALIDASI WARNA ════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
LIGHT_GREEN='\033[1;32m'
NC='\033[0m'
WHITE='\033[1;97m'
LIGHT_BLUE='\033[1;94m'
LIGHT_CYAN='\033[1;96m'
PURPLE='\033[1;95m'
BOLD_WHITE='\033[1;37m'
ORANGE='\033[0;33m'

# ════ KONFIGURASI ════
CONFIG_DIR="/etc/zivpn"
CONFIG_FILE="${CONFIG_DIR}/config.json"
DB_FILE="${CONFIG_DIR}/users.db"  # Format: nama_akun:password:expiry
TELEGRAM_CONF="${CONFIG_DIR}/telegram.conf"
LICENSE_URL="https://raw.githubusercontent.com/Pondok-Vpn/pondokvip/main/DAFTAR"
LICENSE_INFO_FILE="${CONFIG_DIR}/.license_info"
HELPER_SCRIPT="/usr/local/bin/ziv-helper.sh"

# ════ FUNGSI DASAR ════
function show_banner() {
    clear
    echo -e "${PURPLE}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║     ${LIGHT_CYAN}一═⌊✦⌉ 𝗨𝗗𝗣 𝗭𝗜𝗩𝗣𝗡 𝗣𝗥𝗘𝗠𝗜𝗨𝗠 ⌊✦⌉═一${PURPLE}      ║"
    echo "╚════════════════════════════════════════════════════╝${NC}"
    echo ""
}

function validate_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}This script must be run as root. Please use sudo or run as root user.${NC}" >&2
        exit 1
    fi
}

function check_database() {
    if [ ! -f "$DB_FILE" ]; then
        echo -e "${YELLOW}Creating database file...${NC}"
        touch "$DB_FILE"
        chmod 600 "$DB_FILE"
        echo -e "${GREEN}✓ Database file created${NC}"
    fi
}

function get_host() {
    if [ -f "${CONFIG_DIR}/zivpn.crt" ]; then
        local CERT_CN
        CERT_CN=$(openssl x509 -in "${CONFIG_DIR}/zivpn.crt" -noout -subject 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p' || echo "zivpn")
        if [ "$CERT_CN" == "zivpn" ] || [ -z "$CERT_CN" ]; then
            curl -s ifconfig.me
        else
            echo "$CERT_CN"
        fi
    else
        curl -s ifconfig.me
    fi
}

function update_config_json() {
    # Update config.json dengan semua password dari DB_FILE
    local temp_file="${CONFIG_FILE}.tmp"
    
    # Dapatkan semua password yang aktif
    local current_ts=$(date +%s)
    local passwords=()
    
    while IFS=':' read -r name password expiry; do
        if [ -n "$name" ] && [ -n "$password" ] && ([ "$expiry" -eq 0 ] || [ "$expiry" -gt "$current_ts" ]); then
            passwords+=("$password")
        fi
    done < "$DB_FILE"
    
    # Update config.json
    if [ ${#passwords[@]} -eq 0 ]; then
        jq '.auth.config = []' "$CONFIG_FILE" > "$temp_file"
    else
        # Convert array to JSON format
        local json_array="[]"
        for pass in "${passwords[@]}"; do
            json_array=$(echo "$json_array" | jq --arg pass "$pass" '. += [$pass]')
        done
        
        # Backup config asli dulu
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%s)"
        
        # Update hanya bagian auth.config
        jq --argjson new_config "$json_array" '.auth.config = $new_config' "$CONFIG_FILE" > "$temp_file"
    fi
    
    if [ -f "$temp_file" ]; then
        mv "$temp_file" "$CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

function restart_zivpn() {
    echo -e "${YELLOW}Restarting ZiVPN service...${NC}"
    systemctl restart zivpn.service 2>/dev/null
    echo -e "${GREEN}✓ Service restarted${NC}"
}

# ════ FUNGSI SETTING ════
function show_settings_menu() {
    while true; do
        show_banner
        echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                 ${WHITE}SETTINGS MENU${CYAN}                      ║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║                                                    ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}1)${NC} ${WHITE}Setup Telegram Notification${CYAN}              ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}2)${NC} ${WHITE}Change Telegram Configuration${CYAN}            ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}3)${NC} ${WHITE}Change Domain Name${CYAN}                       ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}4)${NC} ${WHITE}Cleanup Expired Users${CYAN}                    ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}5)${NC} ${WHITE}Backup / Restore Configuration${CYAN}           ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}6)${NC} ${WHITE}Restart ZiVPN Service${CYAN}                    ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}0)${NC} ${WHITE}Back to Main Menu${CYAN}                        ║${NC}"
        echo -e "${CYAN}║                                                    ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -p "$(echo -e ${YELLOW}Pilih option [0-6]: ${NC})" choice
        
        case $choice in
            1) setup_telegram ;;
            2) change_telegram_config ;;
            3) change_domain ;;
            4) cleanup_expired_users ;;
            5) backup_restore_menu ;;
            6) 
                restart_zivpn
                echo ""
                read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
                ;;
            0) return ;;
            *)
                echo -e "${RED}Invalid option. Silahkan pilih ulang.${NC}"
                sleep 2
                ;;
        esac
    done
}

function backup_restore_menu() {
    show_banner
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           ${WHITE}BACKUP & RESTORE${CYAN}                      ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║                                                    ║${NC}"
    echo -e "${CYAN}║  ${YELLOW}1)${NC} ${WHITE}Backup Configuration${CYAN}            ║${NC}"
    echo -e "${CYAN}║  ${YELLOW}2)${NC} ${WHITE}Restore Configuration${CYAN}         ║${NC}"
    echo -e "${CYAN}║  ${YELLOW}0)${NC} ${WHITE}Back to Settings Menu${CYAN}                       ║${NC}"
    echo -e "${CYAN}║                                                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}Pilih option [0-2]: ${NC})" choice
    
    case $choice in
        1)
            if [ -x "$HELPER_SCRIPT" ]; then
                "$HELPER_SCRIPT" backup
            else
                echo -e "${RED}Helper script not found!${NC}"
            fi
            echo ""
            read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
            ;;
        2)
            if [ -x "$HELPER_SCRIPT" ]; then
                "$HELPER_SCRIPT" restore
            else
                echo -e "${RED}Helper script not found!${NC}"
            fi
            echo ""
            read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
            ;;
        0) return ;;
        *)
            echo -e "${RED}Invalid option.${NC}"
            echo ""
            read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
            ;;
    esac
}

function setup_telegram() {
    show_banner
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              ${WHITE}TELEGRAM SETUP${CYAN}                      ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${YELLOW}Get Bot Token from @BotFather${NC}"
    echo -e "${YELLOW}Get Chat ID from @userinfobot${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}Enter Bot Token: ${NC})" bot_token
    read -p "$(echo -e ${YELLOW}Enter Chat ID: ${NC})" chat_id
    
    if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
        echo -e "${RED}Bot Token and Chat ID cannot be empty.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Press Enter to continue...${NC})" dummy
        return 1
    fi
    
    # Test the configuration
    echo -e "${YELLOW}Testing Telegram configuration...${NC}"
    
    local test_url="https://api.telegram.org/bot${bot_token}/getMe"
    local response=$(curl -s "$test_url")
    
    if echo "$response" | grep -q '"ok":true'; then
        echo -e "${GREEN}✓ Bot Token is valid${NC}"
    else
        echo -e "${RED}✗ Invalid Bot Token${NC}"
        echo -e "${YELLOW}Response: $response${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Press Enter to continue...${NC})" dummy
        return 1
    fi
    
    # Save configuration
    mkdir -p "$CONFIG_DIR"
    echo "TELEGRAM_BOT_TOKEN=$bot_token" > "$TELEGRAM_CONF"
    echo "TELEGRAM_CHAT_ID=$chat_id" >> "$TELEGRAM_CONF"
    chmod 600 "$TELEGRAM_CONF"
    
    echo -e "${GREEN}✓ Telegram configuration saved${NC}"
    
    # Send test message
    local test_msg="✅ *PONDOK VPN NOTIFICATION* ✅
    
🔔 Test notification successful!
📅 Date: $(date)
🖥️ Server: $(get_host)
📡 IP: $(curl -s ifconfig.me)

ZiVPN Manager is ready!"
    
    local test_url="https://api.telegram.org/bot${bot_token}/sendMessage"
    curl -s -X POST "$test_url" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${test_msg}" \
        -d "parse_mode=Markdown" > /dev/null
    
    echo -e "${GREEN}✓ Test notification sent to Telegram${NC}"
    echo ""
    read -p "$(echo -e ${YELLOW}Press Enter to continue...${NC})" dummy
    return 0
}

function change_telegram_config() {
    show_banner
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           ${WHITE}CHANGE TELEGRAM CONFIG${CYAN}                ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo -e "${RED}Telegram configuration not found.${NC}"
        echo -e "${YELLOW}Please setup Telegram first.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Press Enter to continue...${NC})" dummy
        return 1
    fi
    
    source "$TELEGRAM_CONF" 2>/dev/null
    
    echo -e "${GREEN}Current configuration:${NC}"
    echo -e "  Bot Token: ${CYAN}${TELEGRAM_BOT_TOKEN:0:10}...${NC}"
    echo -e "  Chat ID: ${CYAN}$TELEGRAM_CHAT_ID${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}Enter new Bot Token (press Enter to keep current): ${NC})" new_token
    read -p "$(echo -e ${YELLOW}Enter new Chat ID (press Enter to keep current): ${NC})" new_chatid
    
    if [ -z "$new_token" ]; then
        new_token="$TELEGRAM_BOT_TOKEN"
    fi
    
    if [ -z "$new_chatid" ]; then
        new_chatid="$TELEGRAM_CHAT_ID"
    fi
    
    # Test new configuration
    echo -e "${YELLOW}Testing new configuration...${NC}"
    
    local test_url="https://api.telegram.org/bot${new_token}/getMe"
    local response=$(curl -s "$test_url")
    
    if echo "$response" | grep -q '"ok":true'; then
        echo -e "${GREEN}✓ New Bot Token is valid${NC}"
    else
        echo -e "${RED}✗ Invalid Bot Token${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Press Enter to continue...${NC})" dummy
        return 1
    fi
    
    # Save new configuration
    echo "TELEGRAM_BOT_TOKEN=$new_token" > "$TELEGRAM_CONF"
    echo "TELEGRAM_CHAT_ID=$new_chatid" >> "$TELEGRAM_CONF"
    
    echo -e "${GREEN}✓ Telegram configuration updated${NC}"
    
    # Send test message with new config
    local test_msg="🔄 *PONDOK VPN CONFIG UPDATED* 🔄
    
✅ Telegram configuration has been changed!
📅 Date: $(date)
🖥️ Server: $(get_host)

New configuration is active."
    
    local test_url="https://api.telegram.org/bot${new_token}/sendMessage"
    curl -s -X POST "$test_url" \
        -d "chat_id=${new_chatid}" \
        --data-urlencode "text=${test_msg}" \
        -d "parse_mode=Markdown" > /dev/null
    
    echo -e "${GREEN}✓ Test notification sent with new configuration${NC}"
    echo ""
    read -p "$(echo -e ${YELLOW}Press Enter to continue...${NC})" dummy
    return 0
}

function change_domain() {
    show_banner
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              ${WHITE}CHANGE DOMAIN${CYAN}                        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local current_cert="${CONFIG_DIR}/zivpn.crt"
    local current_key="${CONFIG_DIR}/zivpn.key"
    
    if [ -f "$current_cert" ]; then
        local current_cn
        current_cn=$(openssl x509 -in "$current_cert" -noout -subject 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p' || echo "unknown")
        echo -e "${YELLOW}Current domain: ${CYAN}$current_cn${NC}"
    else
        echo -e "${YELLOW}No certificate found.${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Enter new domain name (e.g., vpn.pondokvpn.com)${NC}"
    echo -e "${YELLOW}Leave empty to use server IP${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}New domain: ${NC})" new_domain
    
    if [ -z "$new_domain" ]; then
        # Gunakan IP sebagai domain
        new_domain=$(curl -s ifconfig.me)
        echo -e "${YELLOW}Using server IP as domain: $new_domain${NC}"
    fi
    
    # Backup certificate lama
    if [ -f "$current_cert" ]; then
        cp "$current_cert" "${current_cert}.backup.$(date +%s)"
        cp "$current_key" "${current_key}.backup.$(date +%s)"
        echo -e "${GREEN}✓ Old certificates backed up${NC}"
    fi
    
    # Generate new certificate
    echo -e "${YELLOW}Generating new SSL certificate for '$new_domain'...${NC}"
    
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$current_key" \
        -out "$current_cert" \
        -subj "/C=ID/ST=Java/L=Jakarta/O=PondokVPN/CN=$new_domain" 2>/dev/null
    
    if [ $? -eq 0 ] && [ -f "$current_cert" ] && [ -f "$current_key" ]; then
        echo -e "${GREEN}✓ New SSL certificate generated${NC}"
        
        # Update config.json dengan path certificate yang baru
        if [ -f "$CONFIG_FILE" ]; then
            jq --arg cert "$current_cert" --arg key "$current_key" \
                '.cert = $cert | .key = $key' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && \
                mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            echo -e "${GREEN}✓ Configuration updated${NC}"
        fi
        
        # Restart service
        restart_zivpn
        
        echo ""
        echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
        echo -e "${LIGHT_GREEN}║     ${WHITE}✅ DOMAIN BERHASIL DIGANTI${LIGHT_GREEN}      ║${NC}"
        echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
        echo -e "${LIGHT_GREEN}║                                          ║${NC}"
        echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Domain Baru: ${WHITE}$new_domain${LIGHT_GREEN}          ║${NC}"
        echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Certificate: ${WHITE}Regenerated${LIGHT_GREEN}          ║${NC}"
        echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Status: ${WHITE}Service Restarted${LIGHT_GREEN}         ║${NC}"
        echo -e "${LIGHT_GREEN}║                                          ║${NC}"
        echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
        echo -e "${LIGHT_GREEN}║   ${LIGHT_CYAN}Domain changed successfully!${LIGHT_GREEN}           ║${NC}"
        echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
    else
        echo -e "${RED}✗ Failed to generate SSL certificate${NC}"
        
        # Restore backup if exists
        if ls "${current_cert}.backup."* 1>/dev/null 2>&1; then
            local latest_backup=$(ls -t "${current_cert}.backup."* | head -1)
            local key_backup="${latest_backup//.crt./.key.}"
            
            if [ -f "$latest_backup" ] && [ -f "$key_backup" ]; then
                cp "$latest_backup" "$current_cert"
                cp "$key_backup" "$current_key"
                echo -e "${YELLOW}✓ Restored previous certificate${NC}"
            fi
        fi
    fi
    
    echo ""
    read -p "$(echo -e ${YELLOW}Press Enter to continue...${NC})" dummy
}

function cleanup_expired_users() {
    show_banner
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           ${WHITE}CLEANUP EXPIRED USERS${CYAN}                 ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${YELLOW}Cleaning up expired users...${NC}"
    
    local current_ts=$(date +%s)
    local temp_file="${DB_FILE}.tmp"
    local removed_count=0
    
    if [ ! -f "$DB_FILE" ] || [ ! -s "$DB_FILE" ]; then
        echo -e "${YELLOW}No users found in database.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Press Enter to continue...${NC})" dummy
        return
    fi
    
    # Buat file temporary
    touch "$temp_file"
    
    # Filter hanya user yang belum expired
    while IFS=':' read -r name password expiry; do
        if [ -n "$name" ] && [ -n "$password" ] && [ -n "$expiry" ]; then
            if [ "$expiry" -eq 0 ] || [ "$expiry" -gt "$current_ts" ]; then
                # Masih aktif, simpan
                echo "$name:$password:$expiry" >> "$temp_file"
            else
                # Expired, hapus
                echo -e "${RED}Removing expired account: $name${NC}"
                removed_count=$((removed_count + 1))
                
                # Kirim notifikasi expiry ke Telegram
                if [ -f "$TELEGRAM_CONF" ] && [ -x "$HELPER_SCRIPT" ]; then
                    local host=$(get_host)
                    local ip=$(curl -s ifconfig.me)
                    local exp_date=$(date -d "@$expiry" +"%Y-%m-%d")
                    "$HELPER_SCRIPT" expiry-notification "$host" "$ip" "$name" "PondokVPN" "$exp_date" > /dev/null 2>&1
                fi
            fi
        fi
    done < "$DB_FILE"
    
    # Ganti file database dengan yang baru
    mv "$temp_file" "$DB_FILE"
    
    if [ "$removed_count" -gt 0 ]; then
        # Update config.json dan restart service
        update_config_json
        restart_zivpn
        echo -e "${GREEN}✓ Removed $removed_count expired accounts${NC}"
    else
        echo -e "${GREEN}✓ No expired accounts found${NC}"
    fi
    
    echo ""
    read -p "$(echo -e ${YELLOW}Press Enter to continue...${NC})" dummy
}

# ════ FUNGSI MANAJEMEN USER ════
function add_user() {
    local name="$1"
    local password="$2"
    local days="$3"
    
    if [ -z "$name" ] || [ -z "$password" ] || [ -z "$days" ]; then
        echo -e "${RED}Error: Name, password and days are required.${NC}"
        return 1
    fi
    
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid number of days.${NC}"
        return 1
    fi
    
    # Validasi nama (no special characters, no spaces)
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Error: Name can only contain letters, numbers, dash and underscore.${NC}"
        return 1
    fi
    
    # Cek jika nama sudah ada
    if grep -q "^${name}:" "$DB_FILE"; then
        echo -e "${YELLOW}Account name already exists. Updating...${NC}"
        # Hapus entry lama
        sed -i "/^${name}:/d" "$DB_FILE"
    fi
    
    # Cek jika password sudah ada (dengan nama yang berbeda)
    local existing_name
    existing_name=$(grep ":${password}:" "$DB_FILE" | cut -d: -f1)
    if [ -n "$existing_name" ]; then
        echo -e "${YELLOW}Warning: Password already used by '$existing_name'${NC}"
    fi
    
    # Hitung expiry timestamp (0 = lifetime)
    local expiry_ts=0
    if [ "$days" -gt 0 ]; then
        expiry_ts=$(date -d "+${days} days" +%s)
    fi
    
    # Tambah ke database file
    echo "${name}:${password}:${expiry_ts}" >> "$DB_FILE"
    
    # Update config.json
    if update_config_json; then
        restart_zivpn
        
        # Backup otomatis setelah tambah user
        if [ -x "$HELPER_SCRIPT" ]; then
            echo -e "${YELLOW}Creating backup...${NC}"
            "$HELPER_SCRIPT" backup > /dev/null 2>&1
        fi
        
        echo -e "${GREEN}Success: Account '$name' created, expires in ${days} days.${NC}"
        return 0
    else
        # Rollback: hapus dari DB_FILE jika gagal update config
        sed -i "/^${name}:/d" "$DB_FILE"
        echo -e "${RED}Error: Failed to update configuration.${NC}"
        return 1
    fi
}

function delete_user() {
    local name="$1"
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Account name is required.${NC}"
        return 1
    fi
    
    # Hapus dari DB_FILE
    if ! grep -q "^${name}:" "$DB_FILE"; then
        echo -e "${RED}Error: Account '$name' not found.${NC}"
        return 1
    fi
    
    sed -i "/^${name}:/d" "$DB_FILE"
    
    # Update config.json
    if update_config_json; then
        restart_zivpn
        
        # Backup setelah hapus user
        if [ -x "$HELPER_SCRIPT" ]; then
            "$HELPER_SCRIPT" backup > /dev/null 2>&1
        fi
        
        echo -e "${GREEN}Success: Account '$name' deleted.${NC}"
        return 0
    else
        echo -e "${RED}Error: Failed to update configuration.${NC}"
        return 1
    fi
}

function renew_user() {
    local name="$1"
    local days="$2"
    
    if [ -z "$name" ] || [ -z "$days" ]; then
        echo -e "${RED}Error: Account name and days are required.${NC}"
        return 1
    fi
    
    if ! [[ "$days" =~ ^[1-9][0-9]*$ ]; then
        echo -e "${RED}Error: Invalid number of days.${NC}"
        return 1
    fi
    
    # Cek user exists
    if ! grep -q "^${name}:" "$DB_FILE"; then
        echo -e "${RED}Error: Account '$name' not found.${NC}"
        return 1
    fi
    
    # Get current expiry
    local current_expiry
    current_expiry=$(grep "^${name}:" "$DB_FILE" | cut -d: -f3)
    
    # Calculate new expiry
    local new_expiry
    if [ "$current_expiry" -eq 0 ]; then
        # Jika lifetime, ubah ke expiry based
        new_expiry=$(date -d "+${days} days" +%s)
    else
        # Tambah hari ke expiry yang ada
        local seconds_to_add=$((days * 86400))
        new_expiry=$((current_expiry + seconds_to_add))
    fi
    
    # Update DB_FILE
    local password
    password=$(grep "^${name}:" "$DB_FILE" | cut -d: -f2)
    sed -i "s/^${name}:.*/${name}:${password}:${new_expiry}/" "$DB_FILE"
    
    # Update config.json
    if update_config_json; then
        restart_zivpn
        
        # Kirim notifikasi renewal ke Telegram
        if [ -x "$HELPER_SCRIPT" ] && [ -f "$TELEGRAM_CONF" ]; then
            local host=$(get_host)
            local ip=$(curl -s ifconfig.me)
            "$HELPER_SCRIPT" renewed-notification "$host" "$ip" "$name" "PondokVPN" "$new_expiry" > /dev/null 2>&1
        fi
        
        echo -e "${GREEN}Success: Account '$name' renewed for ${days} days.${NC}"
        return 0
    else
        echo -e "${RED}Error: Failed to renew account.${NC}"
        return 1
    fi
}

# ════ FUNGSI TAMPILAN AKUN ════
function show_account_success() {
    local name="$1"
    local password="$2"
    local days="$3"
    local is_trial="$4"
    
    local HOST=$(get_host)
    local expiry_date
    
    if [ "$days" -eq 0 ]; then
        expiry_date="Lifetime"
    else
        if [ "$is_trial" = "true" ]; then
            expiry_date=$(date -d "+${days} hours" +"%d %B %Y %H:%M:%S")
        else
            expiry_date=$(date -d "+${days} days" +"%d %B %Y")
        fi
    fi
    
    clear
    echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
    
    if [ "$is_trial" = "true" ]; then
        echo -e "${LIGHT_GREEN}║   ${WHITE}✅ AKUN TRIAL BERHASIL DIBUAT${LIGHT_GREEN}    ║${NC}"
    else
        echo -e "${LIGHT_GREEN}║     ${WHITE}✅ AKUN BERHASIL DIBUAT${LIGHT_GREEN}      ║${NC}"
    fi
    
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Account: ${WHITE}$name${LIGHT_GREEN}                     ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Host: ${WHITE}$HOST${LIGHT_GREEN}                   ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Password: ${WHITE}$password${LIGHT_GREEN}           ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Expire: ${WHITE}$expiry_date${LIGHT_GREEN}          ║${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║   ${LIGHT_CYAN}Terima kasih sudah order!${LIGHT_GREEN}            ║${NC}"
    echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
}

function show_renew_success() {
    local name="$1"
    local days="$2"
    local new_expiry="$3"
    
    local expiry_date
    if [ "$new_expiry" -eq 0 ]; then
        expiry_date="Lifetime"
    else
        expiry_date=$(date -d "@$new_expiry" +"%d %B %Y")
    fi
    
    echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_GREEN}║     ${WHITE}✅ AKUN BERHASIL DIPERPANJANG${LIGHT_GREEN}    ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Account: ${WHITE}$name${LIGHT_GREEN}                     ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Ditambahkan: ${WHITE}$days hari${LIGHT_GREEN}           ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Expire Baru: ${WHITE}$expiry_date${LIGHT_GREEN}         ║${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║   ${LIGHT_CYAN}Terima kasih sudah order!${LIGHT_GREEN}            ║${NC}"
    echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
}

function create_manual_account() {
    show_banner
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║     ${LIGHT_CYAN}一═⌊✦⌉ 𝗕𝗨𝗔𝗧 𝗔𝗞𝗨𝗡 𝗭𝗜𝗩𝗣𝗡 ⌊✦⌉═一${PURPLE}       ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}Masukkan nama akun: ${NC})" name
    if [ -z "$name" ]; then
        echo -e "${RED}Nama akun tidak boleh kosong.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
        return
    fi
    
    # Validasi nama
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Nama hanya boleh mengandung huruf, angka, dash dan underscore.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
        return
    fi
    
    read -p "$(echo -e ${YELLOW}Masukkan password: ${NC})" password
    if [ -z "$password" ]; then
        echo -e "${RED}Password tidak boleh kosong.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
        return
    fi
    
    if [ ${#password} -lt 4 ]; then
        echo -e "${RED}Password minimal 4 karakter.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
        return
    fi
    
    read -p "$(echo -e ${YELLOW}Masukkan masa aktif (dalam hari, 0 untuk lifetime): ${NC})" days
    
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Jumlah hari tidak valid.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
        return
    fi
    
    # Panggil fungsi add_user
    if add_user "$name" "$password" "$days"; then
        show_account_success "$name" "$password" "$days" "false"
        
        # Kirim notifikasi ke Telegram jika ada
        if [ -x "$HELPER_SCRIPT" ] && [ -f "$TELEGRAM_CONF" ]; then
            local ip=$(curl -s ifconfig.me)
            local host=$(get_host)
            "$HELPER_SCRIPT" api-key-notification "$name" "$ip" "$host" > /dev/null 2>&1
        fi
    else
        echo -e "${RED}Gagal membuat akun.${NC}"
    fi
    
    echo ""
    read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali ke menu...${NC})" dummy
}

function create_trial_account() {
    show_banner
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║   ${LIGHT_CYAN}一═⌊✦⌉ 𝗕𝗨𝗔𝗧 𝗧𝗥𝗜𝗔𝗟 𝗔𝗞𝗨𝗡 ⌊✦⌉═一${PURPLE}       ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Generate nama trial acak
    local name="trial$(shuf -i 1000-9999 -n 1)"
    echo -e "${YELLOW}Generated trial account name: ${CYAN}$name${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}Masukkan masa aktif (dalam jam): ${NC})" hours
    
    if ! [[ "$hours" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RED}Jumlah jam tidak valid.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
        return
    fi
    
    # Generate password acak
    local password=$(openssl rand -base64 6 | tr -d '=' | tr '/+' '_-')
    local days=$((hours / 24))
    
    if [ "$days" -eq 0 ]; then
        days=1  # Minimal 1 hari
    fi
    
    # Hitung expiry dalam jam
    local expiry_ts=$(date -d "+${hours} hours" +%s)
    
    if add_user "$name" "$password" "$days"; then
        # Update dengan expiry dalam jam
        sed -i "s/^${name}:.*/${name}:${password}:${expiry_ts}/" "$DB_FILE"
        update_config_json
        restart_zivpn
        
        show_account_success "$name" "$password" "$hours" "true"
    else
        echo -e "${RED}Gagal membuat akun trial.${NC}"
    fi
    
    echo ""
    read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali ke menu...${NC})" dummy
}

function list_accounts() {
    show_banner
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║   ${LIGHT_CYAN}一═⌊✦⌉ 𝗗𝗔𝗙𝗧𝗔𝗥 𝗔𝗞𝗨𝗡 𝗔𝗞𝗧𝗜𝗙 ⌊✦⌉═一${PURPLE}     ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_database
    
    local current_ts=$(date +%s)
    local count=0
    local active_count=0
    local expired_count=0
    
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║ ${WHITE}No.  Account        Password                     Expired${LIGHT_BLUE}            ║${NC}"
    echo -e "${LIGHT_BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    # Baca dari DB_FILE
    while IFS=':' read -r name password expiry; do
        if [ -n "$name" ] && [ -n "$password" ] && [ -n "$expiry" ]; then
            count=$((count + 1))
            
            if [ "$expiry" -eq 0 ]; then
                # Lifetime account
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-10s %-20s LIFETIME${LIGHT_BLUE}                  ║${NC}\n" "$count" "$name" "$password"
                active_count=$((active_count + 1))
            elif [ "$expiry" -gt "$current_ts" ]; then
                # Masih aktif
                local remaining_days=$(( (expiry - current_ts) / 86400 ))
                local expired_str=$(date -d "@$expiry" +"%d-%m-%Y")
                
                if [ "$remaining_days" -lt 1 ]; then
                    expired_str="<1 hari"
                fi
                
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-10s %-20s %-15s${LIGHT_BLUE}         ║${NC}\n" "$count" "$name" "$password" "$expired_str"
                active_count=$((active_count + 1))
            else
                # Expired
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-10s %-20s ${RED}EXPIRED${WHITE}         ${LIGHT_BLUE}         ║${NC}\n" "$count" "$name" "$password"
                expired_count=$((expired_count + 1))
            fi
        fi
    done < "$DB_FILE"
    
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${LIGHT_GREEN}Total akun: $count${NC}"
    echo -e "${GREEN}Aktif: $active_count${NC} | ${RED}Expired: $expired_count${NC}"
    echo ""
    read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali ke menu...${NC})" dummy
}

function renew_account() {
    show_banner
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║   ${LIGHT_CYAN}一═⌊✦⌉ 𝗥𝗘𝗡𝗘𝗪 𝗔𝗖𝗖𝗢𝗨𝗡𝗧 ⌊✦⌉═一${PURPLE}      ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Tampilkan daftar akun dulu
    echo -e "${YELLOW}Daftar Akun Aktif:${NC}"
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║ ${WHITE}No.  Account        Password                     Expired${LIGHT_BLUE}            ║${NC}"
    echo -e "${LIGHT_BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    local current_ts=$(date +%s)
    local count=0
    declare -a account_list
    
    # Baca dari DB_FILE
    while IFS=':' read -r name password expiry; do
        if [ -n "$name" ] && [ -n "$password" ] && [ -n "$expiry" ] && ([ "$expiry" -eq 0 ] || [ "$expiry" -gt "$current_ts" ]); then
            count=$((count + 1))
            account_list[$count]=$name
            
            if [ "$expiry" -eq 0 ]; then
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-10s %-20s LIFETIME${LIGHT_BLUE}                  ║${NC}\n" "$count" "$name" "$password"
            else
                local expired_str=$(date -d "@$expiry" +"%d-%m-%Y")
                printf "${LIGHT_BLUE}║ ${WHITE}%2d. %-10s %-20s %-15s${LIGHT_BLUE}         ║${NC}\n" "$count" "$name" "$password" "$expired_str"
            fi
        fi
    done < "$DB_FILE"
    
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}Tidak ada akun aktif ditemukan.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
        return
    fi
    
    read -p "$(echo -e ${YELLOW}Masukkan nomor akun yang akan diperpanjang (0 untuk batal): ${NC})" account_number
    
    if [ -z "$account_number" ] || [ "$account_number" -eq 0 ]; then
        echo -e "${YELLOW}Batal memperpanjang akun.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
        return
    fi
    
    if ! [[ "$account_number" =~ ^[0-9]+$ ]] || [ "$account_number" -lt 1 ] || [ "$account_number" -gt "$count" ]; then
        echo -e "${RED}Nomor akun tidak valid.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
        return
    fi
    
    local name="${account_list[$account_number]}"
    
    echo -e "${CYAN}Akun terpilih: ${WHITE}$name${NC}"
    read -p "$(echo -e ${YELLOW}Masukkan jumlah hari untuk memperpanjang: ${NC})" days
    
    if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RED}Jumlah hari tidak valid. Harus angka positif.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
        return
    fi
    
    if renew_user "$name" "$days"; then
        # Get new expiry for display
        local new_expiry
        new_expiry=$(grep "^${name}:" "$DB_FILE" | cut -d: -f3)
        
        echo ""
        show_renew_success "$name" "$days" "$new_expiry"
    else
        echo -e "${RED}Gagal memperpanjang akun.${NC}"
    fi
    
    echo ""
    read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali ke menu...${NC})" dummy
}

function delete_account() {
    show_banner
    echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║   ${LIGHT_CYAN}一═⌊✦⌉ 𝗛𝗔𝗣𝗨𝗦 𝗔𝗞𝗨𝗡 𝗭𝗜𝗩𝗣𝗡 ⌊✦⌉═一${PURPLE}      ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Tampilkan daftar akun
    list_accounts
    
    read -p "$(echo -e ${YELLOW}Masukkan nama akun yang akan dihapus: ${NC})" name
    
    if [ -z "$name" ]; then
        echo -e "${RED}Nama akun tidak boleh kosong.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
        return
    fi
    
    # Konfirmasi
    read -p "$(echo -e ${RED}Yakin hapus akun '$name'? (y/n): ${NC})" confirm
    
    if [ "$confirm" != "y" ]; then
        echo -e "${YELLOW}Penghapusan dibatalkan.${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali...${NC})" dummy
        return
    fi
    
    if delete_user "$name"; then
        echo ""
        echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
        echo -e "${LIGHT_GREEN}║     ${WHITE}✅ AKUN BERHASIL DIHAPUS${LIGHT_GREEN}        ║${NC}"
        echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
        echo -e "${LIGHT_GREEN}║                                          ║${NC}"
        echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Account: ${WHITE}$name${LIGHT_GREEN}                     ║${NC}"
        echo -e "${LIGHT_GREEN}║                                          ║${NC}"
        echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
        echo -e "${LIGHT_GREEN}║   ${LIGHT_CYAN}Akun telah dihapus permanen${LIGHT_GREEN}          ║${NC}"
        echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
    else
        echo -e "${RED}Gagal menghapus akun.${NC}"
    fi
    
    echo ""
    read -p "$(echo -e ${YELLOW}Tekan Enter untuk kembali ke menu...${NC})" dummy
}

# ════ FUNGSI UTAMA (MENU) ════
function show_main_menu() {
    while true; do
        show_banner
        
        # Tampilkan info server
        local HOST=$(get_host)
        local IP=$(curl -s ifconfig.me)
        local SERVICE_STATUS=$(systemctl is-active zivpn.service 2>/dev/null || echo "inactive")
        
        echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                 ${WHITE}SERVER INFO${CYAN}                     ║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║                                                    ║${NC}"
        echo -e "${CYAN}║  ${WHITE}📍 Host:${NC} ${LIGHT_GREEN}$HOST${CYAN}                         ║${NC}"
        echo -e "${CYAN}║  ${WHITE}🌐 IP:${NC} ${LIGHT_GREEN}$IP${CYAN}                            ║${NC}"
        
        if [ "$SERVICE_STATUS" = "active" ]; then
            echo -e "${CYAN}║  ${WHITE}⚡ Status:${NC} ${LIGHT_GREEN}Aktif${CYAN}                         ║${NC}"
        else
            echo -e "${CYAN}║  ${WHITE}⚡ Status:${NC} ${RED}Nonaktif${CYAN}                       ║${NC}"
        fi
        
        # Hitung jumlah akun
        local total_accounts=0
        local active_accounts=0
        if [ -f "$DB_FILE" ]; then
            total_accounts=$(wc -l < "$DB_FILE" 2>/dev/null || echo 0)
            local current_ts=$(date +%s)
            while IFS=':' read -r _ _ expiry; do
                if [ "$expiry" -eq 0 ] || [ "$expiry" -gt "$current_ts" ]; then
                    active_accounts=$((active_accounts + 1))
                fi
            done < "$DB_FILE"
        fi
        
        echo -e "${CYAN}║  ${WHITE}👥 Accounts:${NC} ${LIGHT_GREEN}$active_accounts/${total_accounts}${CYAN}                   ║${NC}"
        echo -e "${CYAN}║                                                    ║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║                 ${WHITE}MAIN MENU${CYAN}                      ║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║                                                    ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}1)${NC} ${WHITE}Buat Akun ZIVPN${CYAN}                         ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}2)${NC} ${WHITE}Buat Akun Trial${CYAN}                         ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}3)${NC} ${WHITE}Renew Akun${CYAN}                             ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}4)${NC} ${WHITE}Hapus Akun${CYAN}                             ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}5)${NC} ${WHITE}List Akun${CYAN}                              ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}6)${NC} ${WHITE}Settings${CYAN}                               ║${NC}"
        echo -e "${CYAN}║  ${YELLOW}0)${NC} ${WHITE}Exit${CYAN}                                  ║${NC}"
        echo -e "${CYAN}║                                                    ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -p "$(echo -e ${YELLOW}Pilih option [0-6]: ${NC})" choice
        
        case $choice in
            1) create_manual_account ;;
            2) create_trial_account ;;
            3) renew_account ;;
            4) delete_account ;;
            5) list_accounts ;;
            6) show_settings_menu ;;
            0)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Silahkan pilih ulang.${NC}"
                sleep 2
                ;;
        esac
    done
}

# ════ MAIN EXECUTION ════
validate_root
check_database
show_main_menu