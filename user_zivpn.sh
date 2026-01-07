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
ZIVPN_SERVICE="/etc/systemd/system/zivpn.service"

# ================================================
# --- Utility Functions ---
function restart_zivpn() {
    echo "Restarting ZIVPN service..."
    
    # Cari service ZIVPN dengan berbagai nama
    local service_found=false
    local service_name=""
    
    # Coba nama-nama service yang mungkin
    local possible_services=("zivpn" "udp-zivpn" "zivpn-udp" "udp-custom" "udp-vpn" "vpn-udp")
    
    for svc in "${possible_services[@]}"; do
        if systemctl list-unit-files | grep -q "${svc}.service"; then
            service_name="${svc}.service"
            service_found=true
            break
        fi
    done
    
    if [ "$service_found" = true ] && [ -n "$service_name" ]; then
        systemctl restart "$service_name"
        echo "Service $service_name restarted."
    elif [ -f "/etc/init.d/zivpn" ]; then
        /etc/init.d/zivpn restart
        echo "Service restarted via init.d."
    elif [ -f "/etc/init.d/udp-custom" ]; then
        /etc/init.d/udp-custom restart
        echo "Service udp-custom restarted via init.d."
    else
        echo -e "${YELLOW}Warning: ZIVPN service not found.${NC}"
        echo -e "${YELLOW}Trying to find and restart ZIVPN process...${NC}"
        
        # Coba cari process ZIVPN dan restart
        local zivpn_pid=$(ps aux | grep -E "(zivpn|udp-custom)" | grep -v grep | head -1 | awk '{print $2}')
        if [ -n "$zivpn_pid" ]; then
            echo "Found ZIVPN process with PID: $zivpn_pid"
            kill -9 "$zivpn_pid" 2>/dev/null
            echo "Killed old ZIVPN process"
        fi
        
        # Coba start service manual
        if [ -f "/usr/bin/zivpn" ]; then
            nohup /usr/bin/zivpn > /dev/null 2>&1 &
            echo "Started ZIVPN manually from /usr/bin/zivpn"
        elif [ -f "/usr/local/bin/zivpn" ]; then
            nohup /usr/local/bin/zivpn > /dev/null 2>&1 &
            echo "Started ZIVPN manually from /usr/local/bin/zivpn"
        else
            echo -e "${RED}Error: ZIVPN binary not found!${NC}"
            echo -e "${YELLOW}Please install ZIVPN service first.${NC}"
            echo -e "${YELLOW}Or run: systemctl start zivpn${NC}"
        fi
    fi
}

# --- Install ZIVPN Service ---
function install_zivpn_service() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       ${WHITE}INSTALL ZIVPN SERVICE${BLUE}              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${YELLOW}This will install ZIVPN as a systemd service.${NC}"
    echo ""
    
    # Cek apakah ZIVPN binary ada
    local zivpn_binary=""
    if [ -f "/usr/bin/zivpn" ]; then
        zivpn_binary="/usr/bin/zivpn"
    elif [ -f "/usr/local/bin/zivpn" ]; then
        zivpn_binary="/usr/local/bin/zivpn"
    else
        echo -e "${RED}Error: ZIVPN binary not found!${NC}"
        echo -e "${YELLOW}Please install ZIVPN first.${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "${GREEN}Found ZIVPN binary at: $zivpn_binary${NC}"
    echo ""
    
    # Buat service file
    cat > "$ZIVPN_SERVICE" << EOF
[Unit]
Description=ZIVPN UDP Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$zivpn_binary
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd dan enable service
    systemctl daemon-reload
    systemctl enable zivpn.service
    systemctl start zivpn.service
    
    # Cek status
    sleep 2
    if systemctl is-active --quiet zivpn.service; then
        echo -e "${GREEN}✅ ZIVPN service installed and started successfully!${NC}"
        echo ""
        echo -e "${LIGHT_BLUE}Service Info:${NC}"
        echo -e "${WHITE}Status: $(systemctl is-active zivpn.service)${NC}"
        echo -e "${WHITE}Enabled: $(systemctl is-enabled zivpn.service)${NC}"
    else
        echo -e "${YELLOW}⚠️  Service created but may not be running.${NC}"
        echo -e "${YELLOW}Check with: systemctl status zivpn${NC}"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# --- Check ZIVPN Status ---
function check_zivpn_status() {
    echo -e "${YELLOW}Checking ZIVPN status...${NC}"
    
    local service_running=false
    local possible_services=("zivpn" "udp-zivpn" "zivpn-udp" "udp-custom" "udp-vpn" "vpn-udp")
    
    for svc in "${possible_services[@]}"; do
        if systemctl list-unit-files | grep -q "${svc}.service"; then
            if systemctl is-active --quiet "${svc}.service"; then
                echo -e "${GREEN}✅ Service $svc is running${NC}"
                service_running=true
                break
            fi
        fi
    done
    
    if [ "$service_running" = false ]; then
        # Cek process manual
        local zivpn_pid=$(ps aux | grep -E "(zivpn|udp-custom)" | grep -v grep | head -1 | awk '{print $2}')
        if [ -n "$zivpn_pid" ]; then
            echo -e "${YELLOW}⚠️  ZIVPN process found (PID: $zivpn_pid) but no systemd service${NC}"
            service_running=true
        else
            echo -e "${RED}❌ ZIVPN is not running${NC}"
        fi
    fi
    
    return $([ "$service_running" = true ] && echo 0 || echo 1)
}

# --- Fail2Ban Functions ---
function install_fail2ban() {
    echo -e "${YELLOW}Installing fail2ban for protection...${NC}"
    
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
            echo -e "${RED}⚠️  Account ${username} exceeded device limit (max: $max_devices)${NC}"
            lock_account "$username" "Exceeded IP/device limit (max: $max_devices)"
            
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
    
    echo -e "${RED}🔒 Locking account: $username - Reason: $reason${NC}"
    
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
        echo -e "${GREEN}🔓 Unlocking account: $username${NC}"
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
        if [ -n "$password" ]; then
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
                
                # Hapus dari device DB
                sed -i "/^${password}:/d" "$DEVICE_DB" 2>/dev/null
            fi
        fi
    done < "$USER_DB"
    
    # Ganti file database dengan yang baru
    mv "$temp_file" "$USER_DB"
    
    if [ $deleted_count -gt 0 ]; then
        echo -e "${GREEN}Deleted $deleted_count expired accounts${NC}"
        # Restart service hanya jika ada perubahan
        restart_zivpn
    fi
}

# --- Create Account (dengan limit 2 IP/device) ---
function create_account() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       ${WHITE}CREATE ACCOUNT - PREMIUM${BLUE}            ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Cek status ZIVPN dulu
    if ! check_zivpn_status; then
        echo -e "${RED}❌ ZIVPN service is not running!${NC}"
        echo -e "${YELLOW}Please start ZIVPN service first.${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Hapus akun expired sebelum membuat akun baru
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
    
    # Cek status ZIVPN dulu
    if ! check_zivpn_status; then
        echo -e "${RED}❌ ZIVPN service is not running!${NC}"
        echo -e "${YELLOW}Please start ZIVPN service first.${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Hapus akun expired sebelum membuat trial baru
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

# --- Backup/Restart Menu (tambah opsi install service) ---
function backup_restart() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           ${WHITE}BACKUP / RESTART${BLUE}               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Cek status ZIVPN
    check_zivpn_status
    echo ""
    
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}1) ${CYAN}Backup Data${LIGHT_BLUE}                         ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}2) ${CYAN}Restore Data${LIGHT_BLUE}                        ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}3) ${CYAN}Install Fail2Ban${LIGHT_BLUE}                    ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}4) ${CYAN}Install ZIVPN Service${LIGHT_BLUE}               ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}5) ${CYAN}Check ZIVPN Status${LIGHT_BLUE}                  ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}0) ${CYAN}Back to Menu${LIGHT_BLUE}                        ║${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Select menu [0-5]: " choice
    
    case $choice in
        1)
            echo "Creating backup..."
            mkdir -p /backup/zivpn
            cp -r /etc/zivpn /backup/zivpn/
            tar -czf /backup/zivpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz /backup/zivpn
            
            # Kirim notifikasi ke Telegram jika ada
            if [ -f "/etc/zivpn/telegram.conf" ]; then
                source /etc/zivpn/telegram.conf 2>/dev/null
                if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                        -d "chat_id=${TELEGRAM_CHAT_ID}" \
                        -d "text=✅ Backup created successfully! 
📁 File: zivpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz
📅 Date: $(date '+%d %B %Y %H:%M:%S')
📱 PONDOK VPN" \
                        -d "parse_mode=Markdown" > /dev/null 2>&1
                fi
            fi
            
            echo -e "${GREEN}Backup created successfully!${NC}"
            sleep 2
            ;;
        2)
            echo "Restore data..."
            echo -e "${YELLOW}Restore feature under development${NC}"
            sleep 2
            ;;
        3)
            install_fail2ban
            sleep 2
            ;;
        4)
            install_zivpn_service
            ;;
        5)
            check_zivpn_status
            read -p "Press Enter to continue..."
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
    echo -e "${BLUE}║           ${WHITE}RESTART SERVICE${BLUE}                 ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Cek status ZIVPN dulu
    check_zivpn_status
    echo ""
    
    # Hapus akun expired terlebih dahulu
    delete_expired_accounts
    
    echo -e "${YELLOW}Restarting ZIVPN service...${NC}"
    restart_zivpn
    echo -e "${GREEN}Service restarted!${NC}"
    
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

# --- Main Menu (tampilkan status ZIVPN) ---
function show_menu() {
    while true; do
        # Display banner
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
        
        # Display info panel
        display_info_panel
        
        # Tampilkan status ZIVPN
        echo ""
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║          ${WHITE}ZIVPN SERVICE STATUS${BLUE}             ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════╣${NC}"
        check_zivpn_status
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        
        # Main Menu sesuai permintaan
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

# [Fungsi-fungsi lain tetap sama...]
# (renew_account, delete_account, add_bot_token, change_domain, dll tetap sama seperti sebelumnya)
# ...

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
