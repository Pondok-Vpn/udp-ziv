#!/bin/bash
# ===========================================
# ZIVPN HYBRID INSTALLER - SIMPLE & RELIABLE
# Best of Both Worlds: Zahid's simplicity + Our features
# GitHub: https://github.com/Pondok-Vpn/udp-ziv
# Telegram: @bendakerep
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Variables
REPO_URL="https://raw.githubusercontent.com/Pondok-Vpn"
LICENSE_URL="$REPO_URL/Pondok-Vpn/main/DAFTAR"
MENU_SCRIPT="/usr/local/bin/zivpn-menu"

# Simple log function
log() {
    echo -e "[$(date '+%H:%M:%S')] $1"
}

# Show banner
show_banner() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}        ZIVPN HYBRID INSTALLER         ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# ===========================================
# LICENSE CHECK FUNCTION (TAMBAHKAN INI)
# ===========================================
check_license() {
    log "${YELLOW}Checking license...${NC}"
    
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    log "${CYAN}Server IP: $SERVER_IP${NC}"
    
    # Download license file
    LICENSE_FILE=$(mktemp)
    if curl -s "$LICENSE_URL" -o "$LICENSE_FILE" 2>/dev/null; then
        # Check if IP exists in license file
        if grep -q "^$SERVER_IP" "$LICENSE_FILE"; then
            LICENSE_INFO=$(grep "^$SERVER_IP" "$LICENSE_FILE")
            USER_NAME=$(echo "$LICENSE_INFO" | awk '{print $2}')
            EXPIRY_DATE=$(echo "$LICENSE_INFO" | awk '{print $3}')
            
            # Check expiry date
            CURRENT_DATE=$(date +%Y-%m-%d)
            if [[ "$CURRENT_DATE" > "$EXPIRY_DATE" ]]; then
                echo -e "${RED}========================================${NC}"
                echo -e "${RED}           LICENSE EXPIRED!            ${NC}"
                echo -e "${RED}========================================${NC}"
                echo ""
                echo -e "${YELLOW}IP: $SERVER_IP${NC}"
                echo -e "${YELLOW}Expired: $EXPIRY_DATE${NC}"
                echo ""
                echo -e "${CYAN}Contact @bendakerep for renewal${NC}"
                rm -f "$LICENSE_FILE"
                exit 1
            fi
            
            echo -e "${GREEN}✓ License valid for: $USER_NAME${NC}"
            echo -e "${CYAN}✓ Expiry date: $EXPIRY_DATE${NC}"
            
            # Save license info
            mkdir -p /etc/zivpn
            echo "$USER_NAME" > /etc/zivpn/.license_info
            echo "$EXPIRY_DATE" >> /etc/zivpn/.license_info
            
        else
            echo -e "${RED}========================================${NC}"
            echo -e "${RED}     UNAUTHORIZED INSTALLATION!        ${NC}"
            echo -e "${RED}========================================${NC}"
            echo ""
            echo -e "${YELLOW}Your IP ($SERVER_IP) is not registered${NC}"
            echo ""
            echo -e "${CYAN}Contact @bendakerep for license${NC}"
            rm -f "$LICENSE_FILE"
            exit 1
        fi
        
        rm -f "$LICENSE_FILE"
    else
        # Jika tidak bisa connect ke server license, tetap lanjut dengan warning
        echo -e "${YELLOW}⚠️  Cannot connect to license server${NC}"
        echo -e "${YELLOW}Running in evaluation mode...${NC}"
        sleep 3
    fi
    
    echo ""
}
# ===========================================

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Script must be run as root!${NC}"
        echo -e "${YELLOW}Use: sudo bash $0${NC}"
        exit 1
    fi
}

# Setup swap - OPTIMIZED for 1GB RAM
setup_swap() {
    log "${YELLOW}Setting up swap for 1GB RAM...${NC}"
    
    if ! swapon --show | grep -q "/swapfile"; then
        # Create 2GB swap
        fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        
        # Make permanent
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo "vm.swappiness=30" >> /etc/sysctl.conf
        sysctl -p
        
        echo -e "${GREEN}✓ 2GB swap created${NC}"
    else
        echo -e "${GREEN}✓ Swap already exists${NC}"
    fi
    echo ""
}

# Install minimal dependencies
install_deps() {
    log "${YELLOW}Installing minimal dependencies...${NC}"
    
    # Stop apt processes
    pkill apt 2>/dev/null || true
    pkill dpkg 2>/dev/null || true
    
    # Update
    apt-get update -y
    apt-get upgrade -y
    
    # Install only what we need
    apt-get install -y wget curl openssl net-tools iptables
    
    echo -e "${GREEN}✓ Dependencies installed${NC}"
    echo ""
}

# Download binary - SIMPLE & RELIABLE
download_binary() {
    log "${YELLOW}Detecting architecture...${NC}"
    
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]] || [[ "$ARCH" == "amd64" ]]; then
        BINARY_NAME="udp-zivpn-linux-amd64"
        log "${GREEN}Architecture: AMD64${NC}"
    elif [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
        BINARY_NAME="udp-zivpn-linux-arm64"
        log "${GREEN}Architecture: ARM64${NC}"
    else
        log "${RED}Unsupported architecture: $ARCH${NC}"
        exit 1
    fi
    
    log "${YELLOW}Downloading ZIVPN binary...${NC}"
    
    # Try multiple sources
    SOURCES=(
        "https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/$BINARY_NAME"
        "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/$BINARY_NAME"
        "https://cdn.jsdelivr.net/gh/zahidbd2/udp-zivpn@latest/$BINARY_NAME"
    )
    
    for url in "${SOURCES[@]}"; do
        log "${CYAN}Trying: $(echo $url | cut -d'/' -f3)...${NC}"
        
        if wget --timeout=30 -q "$url" -O /usr/local/bin/zivpn; then
            if [ -f /usr/local/bin/zivpn ]; then
                FILE_SIZE=$(stat -c%s /usr/local/bin/zivpn 2>/dev/null || echo 0)
                if [ $FILE_SIZE -gt 1000000 ]; then
                    chmod +x /usr/local/bin/zivpn
                    echo -e "${GREEN}✓ Binary downloaded ($((FILE_SIZE/1024/1024))MB)${NC}"
                    return 0
                fi
            fi
        fi
        rm -f /usr/local/bin/zivpn 2>/dev/null
    done
    
    # ALL FAILED - STOP INSTALLATION
    log "${RED}❌ FATAL: Cannot download binary!${NC}"
    echo ""
    echo -e "${YELLOW}Please download manually:${NC}"
    echo "----------------------------------------"
    echo "cd /usr/local/bin"
    if [[ "$ARCH" == "x86_64" ]] || [[ "$ARCH" == "amd64" ]]; then
        echo "wget https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/udp-zivpn-linux-amd64 -O zivpn"
    else
        echo "wget https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/udp-zivpn-linux-arm64 -O zivpn"
    fi
    echo "chmod +x zivpn"
    echo "systemctl restart zivpn"
    echo "----------------------------------------"
    exit 1
}

# Setup directories and config
setup_config() {
    log "${YELLOW}Creating configuration...${NC}"
    
    mkdir -p /etc/zivpn
    
    # Generate SSL
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
        -keyout "/etc/zivpn/zivpn.key" \
        -out "/etc/zivpn/zivpn.crt"
    
    # Create config.json
    cat > /etc/zivpn/config.json << 'EOF'
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
    
    # Create user database
    echo "pondok123:9999999999:2:Admin" > /etc/zivpn/users.db
    touch /etc/zivpn/devices.db
    touch /etc/zivpn/locked.db
    
    # Optimize network
    sysctl -w net.core.rmem_max=16777216
    sysctl -w net.core.wmem_max=16777216
    
    echo -e "${GREEN}✓ Configuration created${NC}"
    echo ""
}

# Create systemd service - SIMPLE like Zahid
create_service() {
    log "${YELLOW}Creating systemd service...${NC}"
    
    cat > /etc/systemd/system/zivpn.service << 'EOF'
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable zivpn.service
    
    echo -e "${GREEN}✓ Service created${NC}"
    echo ""
}

# Setup firewall - SAFE (won't lock SSH)
setup_firewall() {
    log "${YELLOW}Setting up firewall...${NC}"
    
    # Flush existing rules
    iptables -F 2>/dev/null
    
    # Get SSH port
    SSH_PORT=$(sshd -T 2>/dev/null | grep "^port " | awk '{print $2}' || echo "22")
    
    # Allow SSH
    iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
    
    # Allow ZIVPN
    iptables -A INPUT -p udp --dport 5667 -j ACCEPT
    
    # Allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Save rules
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    
    # Install netfilter-persistent if not exists
    if ! command -v netfilter-persistent >/dev/null 2>&1; then
        apt install -y iptables-persistent netfilter-persistent 2>/dev/null || true
    fi
    
    # Save with netfilter-persistent
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ Firewall configured (SSH port: $SSH_PORT)${NC}"
    echo ""
}

# Optional: Port forwarding
ask_port_forward() {
    echo ""
    read -p "Enable port forwarding 6000-19999? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "${YELLOW}Setting up port forwarding...${NC}"
        
        INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
        if [ -n "$INTERFACE" ]; then
            iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport 6000:19999 -j DNAT --to-destination :5667
            iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT
            iptables-save > /etc/iptables/rules.v4
            echo -e "${GREEN}✓ Port forwarding 6000-19999 enabled${NC}"
        fi
    fi
    echo ""
}

# Start service
start_service() {
    log "${YELLOW}Starting ZIVPN service...${NC}"
    
    systemctl start zivpn.service
    sleep 3
    
    if systemctl is-active --quiet zivpn.service; then
        echo -e "${GREEN}✅ Service: RUNNING${NC}"
    else
        echo -e "${RED}❌ Service: FAILED${NC}"
        echo -e "${YELLOW}Check: systemctl status zivpn.service${NC}"
        return 1
    fi
    
    if ss -tulpn | grep -q ":5667"; then
        echo -e "${GREEN}✅ Port 5667: LISTENING${NC}"
    else
        echo -e "${RED}❌ Port 5667: NOT LISTENING${NC}"
    fi
    
    echo ""
}

# Download menu manager
install_menu() {
    log "${YELLOW}Installing menu manager...${NC}"
    
    if wget -q "$REPO_URL/udp-ziv/main/user_zivpn.sh" -O "$MENU_SCRIPT"; then
        chmod +x "$MENU_SCRIPT"
        
        # Add alias
        if ! grep -q "alias menu=" /root/.bashrc; then
            echo "alias menu='zivpn-menu'" >> /root/.bashrc
        fi
        
        echo -e "${GREEN}✓ Menu manager installed${NC}"
        echo -e "${CYAN}Type 'menu' to open management menu${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Menu manager download failed${NC}"
        echo -e "${YELLOW}You can download it later manually${NC}"
        return 1
    fi
    echo ""
}

# Show final summary
show_summary() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}        ZIVPN INSTALLATION COMPLETE!  ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    echo -e "${YELLOW}📦 SERVER INFORMATION:${NC}"
    echo -e "  IP Address  : $SERVER_IP"
    echo -e "  Port        : 5667 UDP"
    echo -e "  Password    : pondok123"
    echo ""
    
    echo -e "${YELLOW}🚀 QUICK COMMANDS:${NC}"
    echo -e "  Check status : ${GREEN}systemctl status zivpn${NC}"
    echo -e "  Restart      : ${GREEN}systemctl restart zivpn${NC}"
    echo -e "  View logs    : ${GREEN}journalctl -u zivpn -f${NC}"
    
    if [ -f "$MENU_SCRIPT" ]; then
        echo -e "  Open menu    : ${GREEN}menu${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}🔧 CONFIGURATION:${NC}"
    echo -e "  Config dir   : /etc/zivpn/"
    echo -e "  Binary       : /usr/local/bin/zivpn"
    echo -e "  Service file : /etc/systemd/system/zivpn.service"
    echo ""
    
    # Show license info if exists
    if [ -f /etc/zivpn/.license_info ]; then
        LICENSE_USER=$(head -1 /etc/zivpn/.license_info 2>/dev/null)
        LICENSE_EXP=$(tail -1 /etc/zivpn/.license_info 2>/dev/null)
        echo -e "${CYAN}📝 LICENSE INFORMATION:${NC}"
        echo -e "  User        : $LICENSE_USER"
        echo -e "  Expiry      : $LICENSE_EXP"
        echo ""
    fi
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}        Telegram: @bendakerep        ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# Auto start menu
auto_start_menu() {
    if [ -f "$MENU_SCRIPT" ]; then
        echo -e "${YELLOW}Menu will open in 3 seconds...${NC}"
        echo -e "${YELLOW}Press Ctrl+C to cancel${NC}"
        echo ""
        
        for i in {3..1}; do
            echo -ne "${YELLOW}Starting in $i seconds...\033[0K\r${NC}"
            sleep 1
        done
        
        echo ""
        "$MENU_SCRIPT"
    else
        echo -e "${YELLOW}Type 'systemctl status zivpn' to check service${NC}"
        echo ""
    fi
}

# Main installation flow
main() {
    show_banner
    
    # Check root
    check_root
    
    # CHECK LICENSE (TAMBAHKAN DI SINI)
    check_license
    
    # Setup swap FIRST
    setup_swap
    
    # Install dependencies
    install_deps
    
    # Download binary (STOP if fails)
    download_binary
    
    # Setup config
    setup_config
    
    # Create service
    create_service
    
    # Setup firewall
    setup_firewall
    
    # Optional port forward
    ask_port_forward
    
    # Start service
    if ! start_service; then
        echo -e "${RED}Service failed to start! Check logs above.${NC}"
        echo ""
    fi
    
    # Install menu
    install_menu
    
    # Show summary
    show_summary
    
    # Auto start menu
    auto_start_menu
}

# Run
main
