#!/bin/bash
# ZIVPN UDP Installer - Pondok VPN
# Main installer script

echo -e "\033[1;33m"
echo "╔════════════════════════════════════════════════════╗"
echo "║           ZIVPN UDP SERVER INSTALLER               ║"
echo "║               Pondok VPN Edition                   ║"
echo "╚════════════════════════════════════════════════════╝"
echo -e "\033[0m"

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Functions ---
function print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

function print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

function print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

function print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

function install_dependencies() {
    print_status "Updating system packages..."
    apt-get update
    apt-get upgrade -y
    
    print_status "Installing dependencies..."
    apt-get install -y curl wget openssl jq zip unzip figlet lolcat vnstat
    
    print_success "Dependencies installed"
}

function install_zivpn_binary() {
    print_status "Downloading ZIVPN binary..."
    
    # Stop existing service
    systemctl stop zivpn.service 2>/dev/null
    
    # Download binary
    if wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn; then
        chmod +x /usr/local/bin/zivpn
        print_success "Binary downloaded successfully"
    else
        print_error "Failed to download binary"
        print_warning "Trying alternative download source..."
        
        # Alternative source
        if wget -q https://github.com/zivpn/zivpn/releases/latest/download/zivpn-linux-amd64 -O /usr/local/bin/zivpn; then
            chmod +x /usr/local/bin/zivpn
            print_success "Binary downloaded from alternative source"
        else
            print_error "All download sources failed!"
            exit 1
        fi
    fi
}

function setup_configuration() {
    print_status "Setting up configuration directory..."
    mkdir -p /etc/zivpn
    
    print_status "Creating config.json..."
    cat > /etc/zivpn/config.json << EOF
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["zi"]
  }
}
EOF
    
    print_status "Generating SSL certificates..."
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=PondokVPN/OU=IT/CN=zivpn" \
        -keyout "/etc/zivpn/zivpn.key" \
        -out "/etc/zivpn/zivpn.crt"
    
    print_success "Configuration files created"
}

function setup_systemd_service() {
    print_status "Creating systemd service..."
    
    cat > /etc/systemd/system/zivpn.service << EOF
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info

[Install]
WantedBy=multi-user.target
EOF
    
    print_status "Enabling and starting service..."
    systemctl daemon-reload
    systemctl enable zivpn.service
    systemctl start zivpn.service
    
    # Check service status
    if systemctl is-active --quiet zivpn.service; then
        print_success "ZIVPN service is running"
    else
        print_error "Service failed to start. Check logs: journalctl -u zivpn.service"
    fi
}

function setup_firewall() {
    print_status "Configuring firewall rules..."
    
    # Get default interface
    DEFAULT_IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
    
    if [ -n "$DEFAULT_IFACE" ]; then
        # Setup iptables rules
        iptables -t nat -A PREROUTING -i $DEFAULT_IFACE -p udp --dport 6000:19999 -j DNAT --to-destination :5667
        
        # Save iptables rules
        if command -v iptables-persistent &> /dev/null; then
            iptables-save > /etc/iptables/rules.v4
        fi
        
        print_success "Firewall rules configured for interface: $DEFAULT_IFACE"
    else
        print_warning "Could not detect network interface. Manual firewall setup may be required."
    fi
    
    # Enable kernel parameters for UDP performance
    sysctl -w net.core.rmem_max=16777216
    sysctl -w net.core.wmem_max=16777216
    
    echo "net.core.rmem_max=16777216" >> /etc/sysctl.conf
    echo "net.core.wmem_max=16777216" >> /etc/sysctl.conf
}

function setup_user_manager() {
    print_status "Setting up user management system..."
    
    # Download user manager script
    if wget -q https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/user_zivpn.sh -O /usr/local/bin/zivpn-manager; then
        chmod +x /usr/local/bin/zivpn-manager
        
        # Download helper script
        wget -q https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/zivpn_helper.sh -O /usr/local/bin/zivpn_helper.sh
        chmod +x /usr/local/bin/zivpn_helper.sh
        
        # Create alias in bashrc
        if ! grep -q "alias menu=" /root/.bashrc; then
            echo "alias menu='/usr/local/bin/zivpn-manager'" >> /root/.bashrc
            source /root/.bashrc
        fi
        
        print_success "User management system installed"
        print_status "Use 'menu' command to manage users"
    else
        print_warning "Failed to download user manager. Manual setup required."
    fi
}

function setup_auto_expiry() {
    print_status "Setting up automatic expiry check..."
    
    cat > /etc/zivpn/expire_check.sh << 'EOF'
#!/bin/bash
DB_FILE="/etc/zivpn/users.db"
CONFIG_FILE="/etc/zivpn/config.json"
CURRENT_DATE=$(date +%s)

if [ ! -f "$DB_FILE" ]; then
    exit 0
fi

TMP_FILE="/tmp/zivpn_users.tmp"
> "$TMP_FILE"
CHANGED=false

while IFS=':' read -r password expiry_date; do
    if [ -z "$password" ]; then
        continue
    fi
    
    if [ "$expiry_date" -le "$CURRENT_DATE" ]; then
        echo "Removing expired user: $password"
        jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
        mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        CHANGED=true
    else
        echo "$password:$expiry_date" >> "$TMP_FILE"
    fi
done < "$DB_FILE"

if [ "$CHANGED" = true ]; then
    mv "$TMP_FILE" "$DB_FILE"
    systemctl restart zivpn.service
else
    rm -f "$TMP_FILE"
fi
EOF
    
    chmod +x /etc/zivpn/expire_check.sh
    
    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "expire_check.sh"; echo "* * * * * /etc/zivpn/expire_check.sh >/dev/null 2>&1") | crontab -
    
    print_success "Auto expiry check configured"
}

function set_passwords() {
    echo -e "\n${YELLOW}=== PASSWORD SETUP ===${NC}"
    print_status "Current default password is: zi"
    read -p "Do you want to change the default password? (y/n): " change_pass
    
    if [[ "$change_pass" =~ ^[Yy]$ ]]; then
        read -p "Enter new passwords (separate multiple with commas): " input_pass
        
        if [ -n "$input_pass" ]; then
            IFS=',' read -r -a passwords <<< "$input_pass"
            
            # Build JSON array
            json_passwords="["
            for pass in "${passwords[@]}"; do
                json_passwords+="\"$(echo $pass | xargs)\","
            done
            json_passwords="${json_passwords%,}]"
            
            # Update config.json
            jq --argjson passes "$json_passwords" '.auth.config = $passes' /etc/zivpn/config.json > /tmp/config.tmp
            mv /tmp/config.tmp /etc/zivpn/config.json
            
            # Create users.db with 30 days expiry
            > /etc/zivpn/users.db
            for pass in "${passwords[@]}"; do
                expiry=$(date -d "+30 days" +%s)
                echo "$(echo $pass | xargs):$expiry" >> /etc/zivpn/users.db
            done
            
            print_success "Passwords updated"
        fi
    fi
    
    # Restart service to apply changes
    systemctl restart zivpn.service
}

function show_instructions() {
    echo -e "\n${GREEN}=== INSTALLATION COMPLETE ===${NC}"
    echo -e "${BLUE}Server Information:${NC}"
    echo -e "  Port: ${YELLOW}5667 (UDP)${NC}"
    echo -e "  Additional Ports: ${YELLOW}6000-19999 UDP${NC}"
    echo -e "  Obfuscation: ${YELLOW}zivpn${NC}"
    
    echo -e "\n${BLUE}Management Commands:${NC}"
    echo -e "  Start/Stop: ${YELLOW}systemctl start|stop|restart zivpn.service${NC}"
    echo -e "  Status: ${YELLOW}systemctl status zivpn.service${NC}"
    echo -e "  User Management: ${YELLOW}menu${NC} (after logout/login or: source ~/.bashrc)"
    
    echo -e "\n${BLUE}Configuration Files:${NC}"
    echo -e "  Config: ${YELLOW}/etc/zivpn/config.json${NC}"
    echo -e "  Users DB: ${YELLOW}/etc/zivpn/users.db${NC}"
    echo -e "  SSL Cert: ${YELLOW}/etc/zivpn/zivpn.crt${NC}"
    echo -e "  SSL Key: ${YELLOW}/etc/zivpn/zivpn.key${NC}"
    
    echo -e "\n${GREEN}Next Steps:${NC}"
    echo "1. Type 'menu' to manage users"
    echo "2. Configure Telegram notifications in the menu"
    echo "3. Test connection with a VPN client"
    
    echo -e "\n${YELLOW}Note:${NC} Logout and login again if 'menu' command not found"
}

# --- Main Installation ---
function main_install() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    # Check if already installed
    if [ -f "/etc/systemd/system/zivpn.service" ]; then
        print_warning "ZIVPN seems to be already installed."
        read -p "Do you want to reinstall? (y/n): " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            echo "Installation cancelled."
            exit 0
        fi
    fi
    
    echo -e "\n${BLUE}Starting ZIVPN UDP Server Installation...${NC}\n"
    
    # Execute installation steps
    install_dependencies
    install_zivpn_binary
    setup_configuration
    setup_systemd_service
    setup_firewall
    setup_user_manager
    setup_auto_expiry
    set_passwords
    
    show_instructions
}

# --- Run Installation ---
main_install
