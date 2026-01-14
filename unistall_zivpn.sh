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

print_separator() {
    echo -e "${BLUE}======================================================${NC}"
}

print_green_separator() {
    echo -e "${GREEN}======================================================${NC}"
}

show_banner() {
    clear
    print_separator
    echo -e "${RED}           ZIVPN UNINSTALLER                   ${NC}"
    echo -e "${RED}           Telegram: @bendakerep              ${NC}"
    print_separator
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Script must be run as root!${NC}"
        echo -e "${YELLOW}Use: sudo bash $0${NC}"
        exit 1
    fi
}

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
    print_separator
    echo -e "${BLUE}           STOPPING SERVICES                  ${NC}"
    print_separator
    echo ""
    systemctl stop zivpn.service 2>/dev/null
    systemctl disable zivpn.service 2>/dev/null
    pkill -9 zivpn 2>/dev/null
    pkill -f "zivpn server" 2>/dev/null
    echo -e "${GREEN}✓ Services stopped${NC}"
    echo ""
    print_separator
    echo -e "${BLUE}           REMOVING SYSTEMD SERVICE           ${NC}"
    print_separator
    echo ""
    rm -f /etc/systemd/system/zivpn.service
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null
    echo -e "${GREEN}✓ Systemd service removed${NC}"
    echo ""
    print_separator
    echo -e "${BLUE}           REMOVING BINARIES                  ${NC}"
    print_separator
    echo ""
    rm -f /usr/local/bin/zivpn
    rm -f /usr/local/bin/zivpn-menu
    rm -f /usr/local/bin/zivpn_helper.sh 2>/dev/null
    rm -f /usr/local/bin/user_zivpn.sh 2>/dev/null
    echo -e "${GREEN}✓ Binaries removed${NC}"
    echo ""
    print_separator
    echo -e "${BLUE}           REMOVING CONFIGURATIONS            ${NC}"
    print_separator
    echo ""
    rm -rf /etc/zivpn
    rm -f /etc/profile.d/zivpn.sh 2>/dev/null
    if [ -f /root/.bashrc ]; then
        sed -i '/alias menu=/d' /root/.bashrc
        sed -i '/alias zivpn-backup=/d' /root/.bashrc
        sed -i '/alias zivpn_menu=/d' /root/.bashrc
    fi 
    sed -i '/alias menu=/d' /etc/profile 2>/dev/null
    echo -e "${GREEN}✓ Configurations removed${NC}"
    echo ""
    print_separator
    echo -e "${BLUE}           CLEANING LOGS                      ${NC}"
    print_separator
    echo ""
    rm -f /var/log/zivpn*.log 2>/dev/null
    rm -rf /var/backups/zivpn 2>/dev/null
    rm -f /var/log/zivpn_menu.log 2>/dev/null
    rm -f /tmp/zivpn_*.log 2>/dev/null
    journalctl --vacuum-time=1d 2>/dev/null
    echo -e "${GREEN}✓ Logs cleaned${NC}"
    echo ""
    print_separator
    echo -e "${BLUE}           REMOVING FIREWALL RULES            ${NC}"
    print_separator
    echo ""
    iptables -D INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null
    iptables -D INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null
    iptables -t nat -D PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    echo -e "${GREEN}✓ Firewall rules removed${NC}"
    echo ""
    print_separator
    echo -e "${BLUE}           REMOVING FAIL2BAN CONFIGS          ${NC}"
    print_separator
    echo ""
    rm -f /etc/fail2ban/jail.local 2>/dev/null
    rm -f /etc/fail2ban/filter.d/zivpn.conf 2>/dev/null
    if [ -f /etc/fail2ban/jail.conf ]; then
        sed -i '/\[zivpn\]/,/^$/d' /etc/fail2ban/jail.conf 2>/dev/null
    fi
    echo -e "${GREEN}✓ Fail2ban configs removed${NC}"
    echo ""
        print_separator
    echo -e "${BLUE}           CLEANING SWAP FILE                 ${NC}"
    print_separator
    echo ""
    read -p "Remove 2GB swap file created by ZIVPN? (y/n): " remove_swap
    if [[ "$remove_swap" == "y" || "$remove_swap" == "Y" ]]; then
        swapoff /swapfile 2>/dev/null
        rm -f /swapfile
        sed -i '/\/swapfile/d' /etc/fstab 2>/dev/null
        sed -i '/vm.swappiness/d' /etc/sysctl.conf 2>/dev/null
        sysctl -p 2>/dev/null
        echo -e "${GREEN}✓ Swap file removed${NC}"
    else
        echo -e "${YELLOW}✓ Swap file kept${NC}"
    fi
    echo ""
    print_separator
    echo -e "${BLUE}           FINAL CLEANUP                      ${NC}"
    print_separator
    echo ""
    crontab -l 2>/dev/null | grep -v "zivpn" | crontab - 2>/dev/null
    rm -f /etc/cron.d/zivpn* 2>/dev/null
    rm -f /root/zivpn_config_backup.json 2>/dev/null
    rm -f /root/zivpn_backup_*.tar.gz 2>/dev/null
    source /root/.bashrc 2>/dev/null
    echo -e "${GREEN}✓ Final cleanup completed${NC}"
    echo ""
    print_green_separator
    print_green_separator
    echo -e "${GREEN}           UNINSTALLATION COMPLETE!          ${NC}"
    print_green_separator
    print_green_separator
    echo ""
    echo -e "${YELLOW}ZiVPN has been completely removed from your system.${NC}"
    echo ""
    echo -e "${BLUE}Recommended actions:${NC}"
    echo "1. Reboot server: ${GREEN}reboot${NC}"
    echo "2. Check no leftover processes: ${GREEN}ps aux | grep zivpn${NC}"
    echo "3. Check port 5667: ${GREEN}ss -tulpn | grep 5667${NC}"
    echo ""
}

main
