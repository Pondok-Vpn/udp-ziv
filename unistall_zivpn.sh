#!/bin/bash
# ===========================================
# ZIVPN UNINSTALLER
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
NC='\033[0m'

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
    echo -e "${RED}           ZIVPN UNINSTALLER                   ${NC}"
    echo -e "${RED}           Telegram: @bendakerep              ${NC}"
    print_separator
    echo ""
}

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Script must be run as root!${NC}"
        echo -e "${YELLOW}Use: sudo bash $0${NC}"
        exit 1
    fi
}

# Main uninstall
main() {
    show_banner
    check_root
    
    print_separator
    echo -e "${RED}           WARNING: UNINSTALLING ZIVPN         ${NC}"
    print_separator
    echo ""
    
    read -p "Are you sure you want to uninstall ZiVPN? (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Uninstall cancelled.${NC}"
        exit 0
    fi
    
    echo ""
    
    # Stop service
    print_separator
    echo -e "${BLUE}           STOPPING SERVICES                  ${NC}"
    print_separator
    echo ""
    
    systemctl stop zivpn.service 2>/dev/null
    systemctl disable zivpn.service 2>/dev/null
    pkill zivpn 2>/dev/null
    echo -e "${GREEN}✓ Services stopped${NC}"
    echo ""
    
    # Remove systemd service
    print_separator
    echo -e "${BLUE}           REMOVING SYSTEMD SERVICE           ${NC}"
    print_separator
    echo ""
    
    rm -f /etc/systemd/system/zivpn.service
    systemctl daemon-reload
    echo -e "${GREEN}✓ Systemd service removed${NC}"
    echo ""
    
    # Remove binaries
    print_separator
    echo -e "${BLUE}           REMOVING BINARIES                  ${NC}"
    print_separator
    echo ""
    
    rm -f /usr/local/bin/zivpn
    rm -f /usr/local/bin/zivpn-menu
    rm -f /usr/local/bin/zivpn-helper
    echo -e "${GREEN}✓ Binaries removed${NC}"
    echo ""
    
    # Remove configs
    print_separator
    echo -e "${BLUE}           REMOVING CONFIGURATIONS            ${NC}"
    print_separator
    echo ""
    
    rm -rf /etc/zivpn
    rm -f /etc/profile.d/zivpn.sh
    sed -i '/alias menu=/d' /root/.bashrc 2>/dev/null
    sed -i '/alias zivpn-backup=/d' /root/.bashrc 2>/dev/null
    echo -e "${GREEN}✓ Configurations removed${NC}"
    echo ""
    
    # Remove logs
    print_separator
    echo -e "${BLUE}           CLEANING LOGS                      ${NC}"
    print_separator
    echo ""
    
    rm -f /var/log/zivpn*.log 2>/dev/null
    rm -rf /var/backups/zivpn 2>/dev/null
    echo -e "${GREEN}✓ Logs cleaned${NC}"
    echo ""
    
    # Remove fail2ban configs
    print_separator
    echo -e "${BLUE}           REMOVING FAIL2BAN CONFIGS          ${NC}"
    print_separator
    echo ""
    
    rm -f /etc/fail2ban/jail.local 2>/dev/null
    rm -f /etc/fail2ban/filter.d/zivpn.conf 2>/dev/null
    echo -e "${GREEN}✓ Fail2ban configs removed${NC}"
    echo ""
    
    print_green_separator
    print_green_separator
    echo -e "${GREEN}           UNINSTALLATION COMPLETE!          ${NC}"
    print_green_separator
    print_green_separator
    echo ""
    echo -e "${YELLOW}ZiVPN has been completely removed from your system.${NC}"
    echo ""
}

# Run main
main
