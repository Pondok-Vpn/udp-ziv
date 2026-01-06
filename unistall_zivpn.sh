cat > uninstall_zivpn.sh << 'EOF'
#!/bin/bash
# ZIVPN UNINSTALLER

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== ZIVPN UNINSTALLER ===${NC}"
echo ""

read -p "Are you sure? This will remove all ZiVPN files! (y/n): " confirm
[ "$confirm" != "y" ] && echo "Cancelled" && exit 0

echo -e "${YELLOW}[1] Stopping service...${NC}"
systemctl stop zivpn 2>/dev/null
systemctl disable zivpn 2>/dev/null

echo -e "${YELLOW}[2] Removing service...${NC}"
rm -f /etc/systemd/system/zivpn.service
systemctl daemon-reload

echo -e "${YELLOW}[3] Removing binaries...${NC}"
rm -f /usr/local/bin/zivpn
rm -f /usr/local/bin/ziv-helper.sh
rm -f /usr/local/bin/zivpn-user.sh
rm -f /usr/local/bin/setup-zivpn.sh

echo -e "${YELLOW}[4] Removing config files...${NC}"
rm -rf /etc/zivpn

echo -e "${YELLOW}[5] Cleaning up...${NC}"
rm -rf /tmp/udp-custom 2>/dev/null

echo -e "${GREEN}✅ Uninstall complete!${NC}"
echo -e "${YELLOW}Note: Firewall rules may still exist.${NC}"
EOF

chmod +x uninstall-zivpn.sh
