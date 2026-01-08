#!/bin/bash
# ===========================================
# ZIVPN COMPLETE INSTALLER
# All-in-one: zi.sh + setup_zivpn.sh + features
# GitHub: https://github.com/Pondok-Vpn/udp-ziv
# Telegram: @bendakerep
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
CYAN='\033[0;96m'
PURPLE='\033[0;95m'
NC='\033[0m'

# Variables
REPO_URL="https://raw.githubusercontent.com/Pondok-Vpn"
# PERBAIKAN: DAFTAR ada di repo Pondok-Vpn, bukan di udp-ziv
LICENSE_URL="$REPO_URL/Pondok-Vpn/main/DAFTAR"
INSTALL_LOG="/var/log/zivpn_install.log"
CONFIG_DIR="/etc/zivpn"
SERVICE_FILE="/etc/systemd/system/zivpn.service"

# Function untuk garis pembatas
print_separator() {
    echo -e "${BLUE}======================================================${NC}"
}

print_green_separator() {
    echo -e "${GREEN}======================================================${NC}"
}

# Banner
show_banner() {
    clear
    print_separator
    echo -e "${BLUE}           ZIVPN COMPLETE INSTALLER               ${NC}"
    echo -e "${BLUE}           VERSION 3.0 - ALL IN ONE               ${NC}"
    echo -e "${BLUE}           Telegram: @bendakerep                  ${NC}"
    print_separator
    echo ""
}

# Logging
log() {
    local type="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "[$timestamp] [$type] $message" >> "$INSTALL_LOG"
    
    case $type in
        "INFO") echo -e "${GREEN}[✓]${NC} $message" ;;
        "STEP") echo -e "${BLUE}[→]${NC} $message" ;;
        "WARN") echo -e "${YELLOW}[!]${NC} $message" ;;
        "ERROR") echo -e "${RED}[✗]${NC} $message" ;;
        *) echo -e "[$type] $message" ;;
    esac
}

# Check root
check_root() {
    print_separator
    echo -e "${BLUE}           CHECKING ROOT PRIVILEGES              ${NC}"
    print_separator
    echo ""
    
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "Script must be run as root!"
        echo -e "${YELLOW}Use: sudo bash $0${NC}"
        exit 1
    fi
    log "INFO" "Root check passed"
    echo ""
    
    print_green_separator
    echo -e "${GREEN}           ROOT CHECK - COMPLETED               ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# Check license from DAFTAR file (di repo Pondok-Vpn)
check_license() {
    print_separator
    echo -e "${BLUE}           CHECKING LICENSE VALIDITY             ${NC}"
    print_separator
    echo ""
    
    local vps_ip=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    log "INFO" "VPS IP: $vps_ip"
    
    # PERBAIKAN: Download DAFTAR dari repo Pondok-Vpn
    local temp_file=$(mktemp)
    log "INFO" "Downloading license file from: $LICENSE_URL"
    
    if curl -s "$LICENSE_URL" -o "$temp_file" 2>/dev/null; then
        log "INFO" "✓ License file downloaded successfully"
        
        # Format DAFTAR: IP_VPS NAMA_USER EXPIRED
        if grep -q "^$vps_ip" "$temp_file"; then
            local license_info=$(grep "^$vps_ip" "$temp_file")
            local user_name=$(echo "$license_info" | awk '{print $2}')
            local expired_date=$(echo "$license_info" | awk '{print $3}')
            
            log "INFO" "✓ License VALID for: $user_name"
            log "INFO" "✓ Expiry date: $expired_date"
            
            # Check if expired
            local current_date=$(date +%Y-%m-%d)
            if [[ "$current_date" > "$expired_date" ]]; then
                print_separator
                echo -e "${RED}           LICENSE EXPIRED                  ${NC}"
                echo -e "${RED}     Contact: @bendakerep for renewal       ${NC}"
                print_separator
                rm -f "$temp_file"
                exit 1
            fi
            
            # Save user info
            mkdir -p /etc/zivpn
            echo "$user_name" > /etc/zivpn/.license_info
            echo "$expired_date" >> /etc/zivpn/.license_info
            chmod 600 /etc/zivpn/.license_info
            
            log "INFO" "✓ License information saved"
            
        else
            print_separator
            echo -e "${RED}       UNAUTHORIZED INSTALLATION           ${NC}"
            echo -e "${RED}       Your IP is not registered           ${NC}"
            echo -e "${RED}       Contact: @bendakerep                ${NC}"
            print_separator
            rm -f "$temp_file"
            exit 1
        fi
    else
        # Fallback: Coba dari repo udp-ziv (jika ada backup)
        log "WARN" "Cannot connect to main license server"
        log "INFO" "Trying backup location..."
        
        local backup_url="$REPO_URL/udp-ziv/main/DAFTAR"
        if curl -s "$backup_url" -o "$temp_file" 2>/dev/null; then
            log "INFO" "✓ Using backup license file"
            
            if grep -q "^$vps_ip" "$temp_file"; then
                local license_info=$(grep "^$vps_ip" "$temp_file")
                local user_name=$(echo "$license_info" | awk '{print $2}')
                local expired_date=$(echo "$license_info" | awk '{print $3}')
                
                log "INFO" "✓ License VALID for: $user_name"
                log "INFO" "✓ Expiry date: $expired_date"
                
                # Save user info
                mkdir -p /etc/zivpn
                echo "$user_name" > /etc/zivpn/.license_info
                echo "$expired_date" >> /etc/zivpn/.license_info
                chmod 600 /etc/zivpn/.license_info
                
            else
                print_separator
                echo -e "${YELLOW}       LICENSE CHECK SKIPPED              ${NC}"
                echo -e "${YELLOW}   Running in evaluation mode            ${NC}"
                print_separator
                sleep 3
            fi
        else
            print_separator
            echo -e "${YELLOW}       LICENSE CHECK SKIPPED              ${NC}"
            echo -e "${YELLOW}   Running in evaluation mode            ${NC}"
            print_separator
            sleep 3
        fi
    fi
    
    rm -f "$temp_file"
    echo ""
    
    print_green_separator
    echo -e "${GREEN}           LICENSE CHECK - COMPLETED            ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# Install dependencies
install_dependencies() {
    print_separator
    echo -e "${BLUE}           INSTALLING DEPENDENCIES              ${NC}"
    print_separator
    echo ""
    
    log "INFO" "Updating package lists..."
    apt update -y 2>&1 | tee -a "$INSTALL_LOG"
    echo ""
    
    log "INFO" "Upgrading packages..."
    apt upgrade -y 2>&1 | tee -a "$INSTALL_LOG"
    echo ""
    
    log "INFO" "Installing essential packages..."
    apt install -y wget curl jq openssl zip unzip net-tools ufw \
                   iptables iptables-persistent 2>&1 | tee -a "$INSTALL_LOG"
    echo ""
    
    log "INFO" "Installing figlet & lolcat..."
    apt install -y figlet lolcat 2>&1 | tee -a "$INSTALL_LOG"
    echo ""
    
    print_green_separator
    echo -e "${GREEN}           DEPENDENCIES INSTALLED              ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# Install fail2ban
install_fail2ban() {
    print_separator
    echo -e "${BLUE}           INSTALLING FAIL2BAN                  ${NC}"
    print_separator
    echo ""
    
    log "INFO" "Installing fail2ban package..."
    apt install -y fail2ban 2>&1 | tee -a "$INSTALL_LOG"
    echo ""
    
    log "INFO" "Configuring fail2ban for ZiVPN..."
    
    # Create fail2ban config for ZiVPN
    cat > /etc/fail2ban/jail.local << EOF
[zivpn]
enabled = true
port = 5667
protocol = udp
filter = zivpn
logpath = /var/log/zivpn_auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF
    
    # Create filter for ZiVPN
    cat > /etc/fail2ban/filter.d/zivpn.conf << EOF
[Definition]
failregex = ^.*FAILED.*from <HOST>
ignoreregex =
EOF
    
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    log "INFO" "✓ Fail2ban service started and enabled"
    echo ""
    
    print_green_separator
    echo -e "${GREEN}           FAIL2BAN INSTALLED                  ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# Domain or IP selection
get_domain_or_ip() {
    print_separator
    echo -e "${BLUE}           DOMAIN CONFIGURATION                 ${NC}"
    print_separator
    echo ""
    
    echo -e "${CYAN}Select SSL certificate type:${NC}"
    echo "1) Use Domain (example: vpn.pondok.com)"
    echo "2) Use IP Address only"
    echo ""
    
    read -p "Choose option [1/2]: " domain_choice
    
    case $domain_choice in
        1)
            read -p "Enter your domain (without http://): " domain_name
            
            if [[ -z "$domain_name" ]]; then
                log "WARN" "Domain empty, using IP instead"
                DOMAIN_TYPE="ip"
                DOMAIN_VALUE=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
            else
                DOMAIN_TYPE="domain"
                DOMAIN_VALUE="$domain_name"
                
                # Update /etc/hosts if needed
                local vps_ip=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
                if ! grep -q "$domain_name" /etc/hosts; then
                    echo "$vps_ip $domain_name" >> /etc/hosts
                    log "INFO" "✓ Added $domain_name to /etc/hosts"
                fi
            fi
            ;;
        2)
            DOMAIN_TYPE="ip"
            DOMAIN_VALUE=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
            log "INFO" "Using IP address: $DOMAIN_VALUE"
            ;;
        *)
            log "WARN" "Invalid choice, using IP address"
            DOMAIN_TYPE="ip"
            DOMAIN_VALUE=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
            ;;
    esac
    
    log "INFO" "SSL will be created for: $DOMAIN_VALUE ($DOMAIN_TYPE)"
    echo ""
    
    print_green_separator
    echo -e "${GREEN}           DOMAIN CONFIGURED                   ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# Download and install ZiVPN binary
install_zivpn_binary() {
    print_separator
    echo -e "${BLUE}           DOWNLOADING ZIVPN BINARY             ${NC}"
    print_separator
    echo ""
    
    # Kill any running zivpn
    pkill zivpn 2>/dev/null
    systemctl stop zivpn 2>/dev/null
    
    # Download binary
    log "INFO" "Downloading from official repository..."
    if wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
        -O /usr/local/bin/zivpn; then
        chmod +x /usr/local/bin/zivpn
        log "INFO" "✓ ZiVPN binary downloaded successfully"
    else
        log "ERROR" "Failed to download ZiVPN binary"
        exit 1
    fi
    
    echo ""
    print_green_separator
    echo -e "${GREEN}           ZIVPN BINARY INSTALLED              ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# Setup directories and files
setup_directories() {
    print_separator
    echo -e "${BLUE}           CREATING DIRECTORIES & FILES         ${NC}"
    print_separator
    echo ""
    
    log "INFO" "Creating directories..."
    mkdir -p "$CONFIG_DIR" /var/log/zivpn /var/backups/zivpn
    log "INFO" "✓ Directories created"
    echo ""
    
    # Generate SSL certificate based on domain/ip choice
    log "INFO" "Generating SSL certificate for: $DOMAIN_VALUE"
    echo ""
    
    if [[ "$DOMAIN_TYPE" == "domain" ]]; then
        openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
            -subj "/C=ID/CN=$DOMAIN_VALUE" \
            -keyout "$CONFIG_DIR/zivpn.key" \
            -out "$CONFIG_DIR/zivpn.crt" 2>&1 | tee -a "$INSTALL_LOG"
    else
        openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
            -subj "/C=ID/CN=zivpn" \
            -keyout "$CONFIG_DIR/zivpn.key" \
            -out "$CONFIG_DIR/zivpn.crt" 2>&1 | tee -a "$INSTALL_LOG"
    fi
    
    log "INFO" "✓ SSL certificate generated"
    echo ""
    
    # Create default user database
    log "INFO" "Creating user database..."
    echo "pondok123:9999999999:2:Admin" > "$CONFIG_DIR/users.db"
    log "INFO" "✓ User database created"
    echo ""
    
    # Create default config.json
    log "INFO" "Creating config.json..."
    cat > "$CONFIG_DIR/config.json" << EOF
{
  "listen": ":5667",
  "cert": "$CONFIG_DIR/zivpn.crt",
  "key": "$CONFIG_DIR/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["pondok123"]
  }
}
EOF
    log "INFO" "✓ Config file created"
    echo ""
    
    # Create other necessary files
    log "INFO" "Creating other required files..."
    touch "$CONFIG_DIR/devices.db"
    touch "$CONFIG_DIR/locked.db"
    touch "$CONFIG_DIR/banlist.db"
    touch /var/log/zivpn_auth.log
    log "INFO" "✓ All files created"
    echo ""
    
    # Set permissions
    chmod 600 "$CONFIG_DIR"/*.key "$CONFIG_DIR"/*.db
    log "INFO" "✓ Permissions set"
    echo ""
    
    print_green_separator
    echo -e "${GREEN}           DIRECTORIES & FILES CREATED         ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# Create systemd service
create_service() {
    print_separator
    echo -e "${BLUE}           CREATING SYSTEMD SERVICE            ${NC}"
    print_separator
    echo ""
    
    log "INFO" "Creating service file..."
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=ZiVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
ExecStart=/usr/local/bin/zivpn server -c $CONFIG_DIR/config.json
Restart=always
RestartSec=3
StandardOutput=append:/var/log/zivpn.log
StandardError=append:/var/log/zivpn-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    log "INFO" "✓ Service file created"
    echo ""
    
    log "INFO" "Reloading systemd daemon..."
    systemctl daemon-reload
    log "INFO" "Enabling service..."
    systemctl enable zivpn.service
    
    print_green_separator
    echo -e "${GREEN}           SYSTEMD SERVICE CREATED            ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# Setup firewall with port forwarding option
setup_firewall() {
    print_separator
    echo -e "${BLUE}           CONFIGURING FIREWALL                ${NC}"
    print_separator
    echo ""
    
    echo -e "${CYAN}Select firewall configuration:${NC}"
    echo "1) Simple setup (Port 5667 only)"
    echo "2) Advanced with port forwarding (5667 + 6000-19999)"
    echo ""
    
    read -p "Choose option [1/2]: " fw_choice
    
    log "INFO" "Setting up firewall rules..."
    
    case $fw_choice in
        2)
            # Advanced: dengan port forwarding
            log "INFO" "Setting up port forwarding 6000-19999 -> 5667"
            
            # Allow main port
            iptables -A INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null
            
            # Allow port range
            iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null
            
            # Port forwarding
            INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
            if [ -n "$INTERFACE" ]; then
                iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport 6000:19999 -j DNAT --to-destination :5667
                log "INFO" "✓ Port forwarding set on interface: $INTERFACE"
            fi
            
            # UFW jika aktif
            if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
                ufw allow 5667/udp comment "ZiVPN Main Port"
                ufw allow 6000:19999/udp comment "ZiVPN Port Range"
                log "INFO" "✓ UFW rules added for port range"
            fi
            
            log "INFO" "✓ Advanced firewall with port forwarding configured"
            ;;
        *)
            # Simple: hanya port 5667
            iptables -A INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null
            
            if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
                ufw allow 5667/udp comment "ZiVPN UDP Port"
                log "INFO" "✓ UFW rule added: 5667/udp"
            fi
            
            log "INFO" "✓ Simple firewall configured"
            ;;
    esac
    
    # Save iptables rules
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    echo ""
    
    print_green_separator
    echo -e "${GREEN}           FIREWALL CONFIGURED                ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# Install menu manager
install_menu_manager() {
    print_separator
    echo -e "${BLUE}           INSTALLING MENU MANAGER             ${NC}"
    print_separator
    echo ""
    
    log "INFO" "Downloading menu manager..."
    
    # Download user_zivpn.sh dari repo udp-ziv
    wget -q "$REPO_URL/udp-ziv/main/user_zivpn.sh" \
        -O /usr/local/bin/zivpn-menu
    
    if [ $? -eq 0 ]; then
        chmod +x /usr/local/bin/zivpn-menu
        log "INFO" "✓ Menu manager downloaded"
    else
        log "WARN" "Failed to download menu manager, creating basic one..."
        # Create basic menu as fallback
        cat > /usr/local/bin/zivpn-menu << EOF
#!/bin/bash
echo "ZiVPN Menu Manager"
echo "Please download manually:"
echo "wget $REPO_URL/udp-ziv/main/user_zivpn.sh -O /usr/local/bin/zivpn-menu"
echo "chmod +x /usr/local/bin/zivpn-menu"
EOF
        chmod +x /usr/local/bin/zivpn-menu
    fi
    
    # Create alias
    if ! grep -q "alias menu=" /root/.bashrc; then
        echo "alias menu='zivpn-menu'" >> /root/.bashrc
        log "INFO" "✓ Alias added to .bashrc"
    fi
    
    echo ""
    print_green_separator
    echo -e "${GREEN}           MENU MANAGER INSTALLED             ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# Start the service
start_service() {
    print_separator
    echo -e "${BLUE}           STARTING ZIVPN SERVICE              ${NC}"
    print_separator
    echo ""
    
    log "INFO" "Starting ZiVPN service..."
    systemctl start zivpn.service
    sleep 3
    
    if systemctl is-active --quiet zivpn.service; then
        log "INFO" "✓ ZiVPN service started successfully"
    else
        log "ERROR" "Failed to start service"
        echo -e "${YELLOW}Check: systemctl status zivpn.service${NC}"
    fi
    
    echo ""
    print_green_separator
    echo -e "${GREEN}           ZIVPN SERVICE STARTED              ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# Show installation summary
show_summary() {
    local public_ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
    local domain_info=""
    
    if [[ "$DOMAIN_TYPE" == "domain" ]]; then
        domain_info="Domain: $DOMAIN_VALUE"
    else
        domain_info="IP: $public_ip"
    fi
    
    echo ""
    print_separator
    print_separator
    echo -e "${GREEN}           INSTALLATION COMPLETE!             ${NC}"
    print_separator
    print_separator
    echo ""
    
    echo -e "${CYAN}📦 ZIVPN INFORMATION:${NC}"
    print_separator
    echo -e "  ${YELLOW}•${NC} Server       : ${GREEN}$domain_info${NC}"
    echo -e "  ${YELLOW}•${NC} Port         : ${GREEN}5667 UDP${NC}"
    echo -e "  ${YELLOW}•${NC} Default Pass : ${GREEN}pondok123${NC}"
    print_separator
    echo ""
    
    echo -e "${CYAN}🚀 AVAILABLE COMMANDS:${NC}"
    print_separator
    echo -e "  ${YELLOW}•${NC} ${GREEN}menu${NC}                 : Open management menu"
    echo -e "  ${YELLOW}•${NC} ${GREEN}systemctl status zivpn${NC} : Check service status"
    echo -e "  ${YELLOW}•${NC} ${GREEN}systemctl restart zivpn${NC}: Restart service"
    print_separator
    echo ""
    
    echo -e "${CYAN}📝 QUICK START:${NC}"
    print_separator
    echo -e "  1. Type ${GREEN}menu${NC} to manage users"
    echo -e "  2. Change default password"
    echo -e "  3. Add your users"
    print_separator
    echo ""
    
    echo -e "${YELLOW}⚠️  AUTO-BAN SYSTEM ACTIVE${NC}"
    print_separator
    echo -e "  Users exceeding device limit = AUTO BAN"
    echo -e "  Use 'menu' to manage bans"
    print_separator
    echo ""
    
    print_separator
    print_separator
    echo -e "${GREEN}      PONDOK VPN - Telegram: @bendakerep       ${NC}"
    print_separator
    print_separator
    echo ""
}

# Auto start menu
auto_start_menu() {
    echo -e "${YELLOW}Starting menu manager in 5 seconds...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to cancel${NC}"
    echo ""
    
    for i in {5..1}; do
        echo -ne "${YELLOW}Starting in $i seconds...\033[0K\r${NC}"
        sleep 1
    done
    
    echo ""
    /usr/local/bin/zivpn-menu
}

# Main installation
main() {
    # Create log file
    > "$INSTALL_LOG"
    
    show_banner
    
    # Step-by-step installation with separators
    check_root
    check_license
    install_dependencies
    install_fail2ban
    get_domain_or_ip
    install_zivpn_binary
    setup_directories
    create_service
    setup_firewall
    install_menu_manager
    start_service
    
    # Show final summary
    show_summary
    
    # Auto start menu
    auto_start_menu
}

# Run main function
main
