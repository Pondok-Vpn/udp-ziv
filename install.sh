#!/bin/bash
# ===========================================
# ZIVPN COMPLETE INSTALLER
# GitHub: https://github.com/Pondok-Vpn/udp-ziv
# Telegram: @bendakerep
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
CYAN='\033[0;96m'
NC='\033[0m'

# Banner
show_banner() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║               ZIVPN COMPLETE INSTALLER           ║"
    echo "║                 PONDOK VPN                       ║"
    echo "║           Telegram: @bendakerep                  ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}ERROR: This script must be run as root!${NC}"
        echo -e "${YELLOW}Use: sudo bash $0${NC}"
        exit 1
    fi
}

# Install dependencies
install_deps() {
    echo -e "${YELLOW}[*] Installing dependencies...${NC}"
    
    apt update -y
    apt upgrade -y
    
    # Essential packages
    apt install -y wget curl jq openssl zip unzip net-tools
    
    # For banners and colors
    apt install -y figlet lolcat
    
    echo -e "${GREEN}[✓] Dependencies installed${NC}"
}

# Download and install ZiVPN
install_zivpn() {
    echo -e "${YELLOW}[*] Downloading ZiVPN binary...${NC}"
    
    # Download binary from official repo
    wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 \
        -O /usr/local/bin/zivpn
    
    chmod +x /usr/local/bin/zivpn
    
    echo -e "${GREEN}[✓] ZiVPN binary installed${NC}"
}

# Setup directories and configs
setup_configs() {
    echo -e "${YELLOW}[*] Setting up configurations...${NC}"
    
    # Create directories
    mkdir -p /etc/zivpn /var/log/zivpn /var/backups/zivpn
    
    # Generate SSL certificate if not exists
    if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
        openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
            -subj "/C=ID/CN=zivpn" \
            -keyout "/etc/zivpn/zivpn.key" \
            -out "/etc/zivpn/zivpn.crt" 2>/dev/null
    fi
    
    # Create default user database
    if [ ! -f /etc/zivpn/users.db ]; then
        echo "pondok123:9999999999:2:Admin" > /etc/zivpn/users.db
    fi
    
    # Create default config.json
    if [ ! -f /etc/zivpn/config.json ]; then
        cat > /etc/zivpn/config.json << EOF
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
    fi
    
    # Create other necessary files
    touch /etc/zivpn/devices.db
    touch /etc/zivpn/locked.db
    touch /etc/zivpn/banlist.db
    touch /var/log/zivpn_auth.log
    
    # Set permissions
    chmod 600 /etc/zivpn/*.key /etc/zivpn/*.db
    
    echo -e "${GREEN}[✓] Configurations created${NC}"
}

# Create systemd service
create_service() {
    echo -e "${YELLOW}[*] Creating systemd service...${NC}"
    
    cat > /etc/systemd/system/zivpn.service << EOF
[Unit]
Description=ZiVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
StandardOutput=append:/var/log/zivpn.log
StandardError=append:/var/log/zivpn-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable zivpn.service
    
    echo -e "${GREEN}[✓] Systemd service created${NC}"
}

# Setup firewall
setup_firewall() {
    echo -e "${YELLOW}[*] Configuring firewall...${NC}"
    
    # Allow ZiVPN port
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw allow 5667/udp comment "ZiVPN UDP Port"
        echo -e "${GREEN}[✓] UFW rule added${NC}"
    fi
    
    # Add iptables rule
    iptables -A INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null
    
    echo -e "${GREEN}[✓] Firewall configured${NC}"
}

# Download menu manager
install_menu() {
    echo -e "${YELLOW}[*] Installing menu manager...${NC}"
    
    # Download user_zivpn.sh (FINAL VERSION)
    wget -q https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/user_zivpn.sh \
        -O /usr/local/bin/zivpn-menu
    
    chmod +x /usr/local/bin/zivpn-menu
    
    # Create alias
    if ! grep -q "alias menu=" /root/.bashrc; then
        echo "alias menu='zivpn-menu'" >> /root/.bashrc
    fi
    
    # Also create for all users
    echo "alias menu='zivpn-menu'" > /etc/profile.d/zivpn.sh
    chmod +x /etc/profile.d/zivpn.sh
    
    echo -e "${GREEN}[✓] Menu manager installed${NC}"
}

# Download helper scripts
install_helpers() {
    echo -e "${YELLOW}[*] Installing helper scripts...${NC}"
    
    # Download zivpn_helper.sh
    wget -q https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/zivpn_helper.sh \
        -O /usr/local/bin/zivpn-helper
    chmod +x /usr/local/bin/zivpn-helper
    
    # Download setup_zivpn.sh (simple installer)
    wget -q https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/setup_zivpn.sh \
        -O /usr/local/bin/zivpn-setup
    chmod +x /usr/local/bin/zivpn-setup
    
    # Download zi.sh (port forwarding installer)
    wget -q https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/zi.sh \
        -O /usr/local/bin/zivpn-portforward
    chmod +x /usr/local/bin/zivpn-portforward
    
    echo -e "${GREEN}[✓] Helper scripts installed${NC}"
}

# Start the service
start_service() {
    echo -e "${YELLOW}[*] Starting ZiVPN service...${NC}"
    
    systemctl start zivpn.service
    sleep 3
    
    if systemctl is-active --quiet zivpn.service; then
        echo -e "${GREEN}[✓] ZiVPN service started successfully${NC}"
    else
        echo -e "${RED}[!] Failed to start service${NC}"
        echo -e "${YELLOW}Check: systemctl status zivpn.service${NC}"
    fi
}

# Show installation summary
show_summary() {
    local public_ip=$(curl -s ifconfig.me 2>/dev/null || echo "Unknown")
    
    echo -e "\n${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}           INSTALLATION COMPLETE!           ${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}📦 ZiVPN Information:${NC}"
    echo -e "  ${YELLOW}•${NC} Server IP   : ${GREEN}$public_ip${NC}"
    echo -e "  ${YELLOW}•${NC} Port        : ${GREEN}5667 UDP${NC}"
    echo -e "  ${YELLOW}•${NC} Password    : ${GREEN}pondok123${NC} (default)"
    echo ""
    echo -e "${CYAN}🚀 Available Commands:${NC}"
    echo -e "  ${YELLOW}•${NC} ${GREEN}menu${NC}              : Open management menu"
    echo -e "  ${YELLOW}•${NC} ${GREEN}systemctl status zivpn${NC} : Check service status"
    echo -e "  ${YELLOW}•${NC} ${GREEN}zivpn-helper backup${NC}    : Backup configuration"
    echo -e "  ${YELLOW}•${NC} ${GREEN}zivpn-setup${NC}        : Re-run simple setup"
    echo ""
    echo -e "${CYAN}📝 Quick Start:${NC}"
    echo -e "  1. Type ${GREEN}menu${NC} to manage users"
    echo -e "  2. Change default password immediately"
    echo -e "  3. Configure Telegram for notifications"
    echo ""
    echo -e "${YELLOW}⚠️  Note: Auto-ban system is ACTIVE${NC}"
    echo -e "  Users exceeding device limit will be auto-banned"
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}      PONDOK VPN - Telegram: @bendakerep       ${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
}

# Main installation
main() {
    show_banner
    check_root
    
    echo -e "${YELLOW}Starting ZiVPN installation...${NC}"
    echo ""
    
    # Step-by-step installation
    install_deps
    install_zivpn
    setup_configs
    create_service
    setup_firewall
    install_menu
    install_helpers
    start_service
    
    # Show summary
    show_summary
    
    # Auto start menu after 5 seconds
    echo -e "\n${YELLOW}Starting menu in 5 seconds...${NC}"
    sleep 5
    
    # Start the menu
    /usr/local/bin/zivpn-menu
}

# Run main function
main
