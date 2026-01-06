#!/bin/bash
# ============================================
# ZIVPN UNINSTALLER - PONDOK VPN EDITION
# Telegram: @bendakerep
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════════╗"
echo "║        ZIVPN UNINSTALLER               ║"
echo "║      PONDOK VPN - udp-zi               ║"
echo "╚════════════════════════════════════════╝${NC}"
echo ""

[ "$EUID" -ne 0 ] && echo -e "${RED}Run as root: sudo bash $0${NC}" && exit 1

# CONFIRMATION
echo -e "${RED}╔════════════════════════════════════════╗${NC}"
echo -e "${RED}║        ⚠️  WARNING: UNINSTALL         ║${NC}"
echo -e "${RED}╠════════════════════════════════════════╣${NC}"
echo -e "${RED}║                                        ║${NC}"
echo -e "${RED}║  This will REMOVE:                     ║${NC}"
echo -e "${RED}║  • ZiVPN Service                       ║${NC}"
echo -e "${RED}║  • All user accounts                   ║${NC}"
echo -e "${RED}║  • Configuration files                 ║${NC}"
echo -e "${RED}║  • Backup files                        ║${NC}"
echo -e "${RED}║                                        ║${NC}"
echo -e "${RED}║  This action cannot be undone!         ║${NC}"
echo -e "${RED}║                                        ║${NC}"
echo -e "${RED}╚════════════════════════════════════════╝${NC}"
echo ""

read -p "$(echo -e ${YELLOW}Type 'YES' to confirm uninstall: ${NC})" confirm

if [ "$confirm" != "YES" ]; then
    echo -e "${YELLOW}Uninstall cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}[1] Stopping services...${NC}"

# Stop ZiVPN service
systemctl stop zivpn.service 2>/dev/null
systemctl disable zivpn.service 2>/dev/null
echo -e "  ${GREEN}✓ ZiVPN service stopped${NC}"

# Remove firewall rules
echo -e "${YELLOW}[2] Removing firewall rules...${NC}"
if command -v ufw > /dev/null 2>&1; then
    ufw delete allow 5667/udp 2>/dev/null
    echo -e "  ${GREEN}✓ UFW rule removed${NC}"
elif command -v iptables > /dev/null 2>&1; then
    iptables -D INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null
    echo -e "  ${GREEN}✓ iptables rule removed${NC}"
fi

echo -e "${YELLOW}[3] Removing files...${NC}"

# Remove binaries
rm -f /usr/local/bin/zivpn 2>/dev/null
rm -f /usr/local/bin/ziv-helper.sh 2>/dev/null
rm -f /usr/local/bin/zi.sh 2>/dev/null
rm -f /usr/local/bin/zivpn-menu 2>/dev/null
rm -f /usr/local/bin/menu-zivpn 2>/dev/null
echo -e "  ${GREEN}✓ Binaries removed${NC}"

# Remove systemd service
rm -f /etc/systemd/system/zivpn.service 2>/dev/null
systemctl daemon-reload 2>/dev/null
echo -e "  ${GREEN}✓ Service file removed${NC}"

# Backup data before removal (optional)
BACKUP_DIR="/tmp/zivpn-backup-$(date +%Y%m%d-%H%M%S)"
if [ -d "/etc/zivpn" ]; then
    echo -e "${YELLOW}[4] Creating backup of configuration...${NC}"
    mkdir -p "$BACKUP_DIR"
    cp -r /etc/zivpn/* "$BACKUP_DIR/" 2>/dev/null
    echo -e "  ${GREEN}✓ Backup created: $BACKUP_DIR${NC}"
    
    # Count users for info
    if [ -f "/etc/zivpn/users.db" ]; then
        USER_COUNT=$(wc -l < /etc/zivpn/users.db 2>/dev/null || echo 0)
        echo -e "  ${YELLOW}  Users backed up: $USER_COUNT${NC}"
    fi
fi

# Remove configuration directory
echo -e "${YELLOW}[5] Removing configuration directory...${NC}"
rm -rf /etc/zivpn 2>/dev/null
echo -e "  ${GREEN}✓ Configuration directory removed${NC}"

# Remove cron jobs
echo -e "${YELLOW}[6] Removing cron jobs...${NC}"
crontab -l 2>/dev/null | grep -v "zivpn" | crontab - 2>/dev/null
echo -e "  ${GREEN}✓ Cron jobs removed${NC}"

# Cleanup temporary files
echo -e "${YELLOW}[7] Cleaning up temporary files...${NC}"
rm -rf /tmp/udp-custom 2>/dev/null
rm -f /tmp/zivpn 2>/dev/null
echo -e "  ${GREEN}✓ Temporary files cleaned${NC}"

# FINAL MESSAGE
clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════════╗"
echo "║        UNINSTALLATION COMPLETE         ║"
echo "╠════════════════════════════════════════╣"
echo "║                                        ║"
echo -e "║  ${GREEN}✅${NC} Services stopped                          ║"
echo -e "║  ${GREEN}✅${NC} Binaries removed                          ║"
echo -e "║  ${GREEN}✅${NC} Configuration removed                     ║"
echo -e "║  ${GREEN}✅${NC} Firewall rules removed                    ║"
echo -e "║  ${GREEN}✅${NC} Cron jobs removed                         ║"
echo "║                                        ║"
echo "╠════════════════════════════════════════╣"
if [ -d "$BACKUP_DIR" ]; then
echo "║                                        ║"
echo -e "║  ${YELLOW}⚠️  Backup saved to:${NC}                         ║"
echo -e "║    ${CYAN}$BACKUP_DIR${NC}                      ║"
echo "║                                        ║"
fi
echo "╠════════════════════════════════════════╣"
echo "║  To reinstall:                         ║"
echo "║    curl -sL URL | bash                 ║"
echo "║                                        ║"
echo "╠════════════════════════════════════════╣"
echo "║  Support: @bendakerep                  ║"
echo "╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}ZiVPN has been completely removed from your system.${NC}"
echo ""

if [ -d "$BACKUP_DIR" ]; then
    echo -e "${YELLOW}Backup location:${NC} ${CYAN}$BACKUP_DIR${NC}"
    echo -e "${YELLOW}To restore manually, copy files back to /etc/zivpn/${NC}"
    echo ""
fi

# Optional: Remove backup after showing info
read -p "$(echo -e ${YELLOW}Delete backup files? (y/N): ${NC})" delete_backup
if [[ "$delete_backup" =~ ^[Yy]$ ]]; then
    rm -rf "$BACKUP_DIR" 2>/dev/null
    echo -e "${GREEN}✓ Backup files deleted${NC}"
fi

echo ""
echo -e "${GREEN}Uninstallation complete. Goodbye!${NC}"