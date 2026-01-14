#!/bin/bash
# ===========================================
# Install  : ZIVPN HYBRID INSTALLER
# Github   : https://github.com/Pondok-Vpn/
# Created  : PONDOK VPN (C) 2026-01-06
# Telegram : @bendakerep
# Email    : redzall55@gmail.com
# ===========================================

# == VALIDASI WARNA ===
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

log() {
    echo -e "[$(date '+%H:%M:%S')] $1"
}

show_banner() {
    clear
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}        ZIVPN HYBRID INSTALLER         ${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
}

# ===========================================
#          LICENSE CHECK FUNCTION
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
#            一═⌊✦⌉ 𝗣𝗢𝗡𝗗𝗢𝗞 𝗩𝗣𝗡 ⌊✦⌉═一
# ===========================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Script must be run as root!${NC}"
        echo -e "${YELLOW}Use: sudo bash $0${NC}"
        exit 1
    fi
}

# Setup swap 2GB - for 1GB RAM
setup_swap() {
    log "${YELLOW}Setting up swap for 1GB RAM...${NC}"
    
    if ! swapon --show | grep -q "/swapfile"; then
        fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo "vm.swappiness=30" >> /etc/sysctl.conf
        sysctl -p
        
        echo -e "${GREEN}✓ 2GB swap created${NC}"
    else
        echo -e "${GREEN}✓ Swap already exists${NC}"
    fi
    echo ""
}

# Install dependencies
install_deps() {
    log "${YELLOW}Installing minimal dependencies...${NC}"
    pkill apt 2>/dev/null || true
    pkill dpkg 2>/dev/null || true
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y wget curl openssl net-tools iptables jq  # TAMBAH jq untuk validasi JSON
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}   ✅ Dependencies installed${NC}"
        echo -e "${GREEN}========================================${NC}"
    echo ""
}

# Download binary
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
        "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/$BINARY_NAME"
        "https://cdn.jsdelivr.net/gh/zahidbd2/udp-zivpn@latest/$BINARY_NAME"
        "https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/$BINARY_NAME"
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

# ===========================================
# PERUBAHAN 1: setup_config() dengan VALIDASI
# ===========================================
setup_config() {
    log "${YELLOW}Creating configuration...${NC}"
    
    mkdir -p /etc/zivpn
    
    # Pastikan direktori dibuat
    if [ ! -d "/etc/zivpn" ]; then
        log "${RED}Failed to create /etc/zivpn directory${NC}"
        exit 1
    fi
    
    # Buat SSL certificate
    log "${CYAN}Creating SSL certificates...${NC}"
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
        -keyout "/etc/zivpn/zivpn.key" \
        -out "/etc/zivpn/zivpn.crt" 2>/dev/null
    
    # Buat config.json dengan format yang PASTI BENAR
    log "${CYAN}Creating config.json...${NC}"
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
    
    # VALIDASI: Cek file berhasil dibuat
    if [ ! -f "/etc/zivpn/config.json" ]; then
        log "${RED}ERROR: config.json not created!${NC}"
        exit 1
    fi
    
    # VALIDASI: Cek file tidak kosong
    FILE_SIZE=$(stat -c%s "/etc/zivpn/config.json" 2>/dev/null || echo 0)
    if [ $FILE_SIZE -lt 10 ]; then
        log "${RED}ERROR: config.json is empty!${NC}"
        # Buat ulang dengan cara sederhana
        echo '{"listen":":5667","cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn","auth":{"mode":"passwords","config":["pondok123"]}}' > /etc/zivpn/config.json
    fi
    
    # VALIDASI: Cek format JSON dengan jq
    if command -v jq >/dev/null 2>&1; then
        if ! jq empty /etc/zivpn/config.json 2>/dev/null; then
            log "${YELLOW}Warning: JSON validation failed, fixing...${NC}"
            # Buat ulang dengan format minimal
            echo '{"listen":":5667","cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn","auth":{"mode":"passwords","config":["pondok123"]}}' > /etc/zivpn/config.json
        else
            log "${GREEN}✓ Config.json JSON format is valid${NC}"
        fi
    fi
    
    # Create user database
    echo "pondok123:9999999999:2:Admin" > /etc/zivpn/users.db
    touch /etc/zivpn/devices.db
    touch /etc/zivpn/locked.db
    
    # Set permissions
    chmod 600 /etc/zivpn/*
    chown root:root /etc/zivpn/*
    
    # Optimize network
    sysctl -w net.core.rmem_max=16777216 2>/dev/null || true
    sysctl -w net.core.wmem_max=16777216 2>/dev/null || true
    
    echo -e "${GREEN}✓ Configuration created and validated${NC}"
    echo ""
}

# ===========================================
# PERUBAHAN 2: test_config() function BARU
# ===========================================
test_config() {
    log "${YELLOW}Testing configuration...${NC}"
    
    # Cek apakah config file ada dan valid
    if [ ! -f "/etc/zivpn/config.json" ]; then
        log "${RED}ERROR: config.json not found!${NC}"
        return 1
    fi
    
    # Cek file size
    CONFIG_SIZE=$(stat -c%s "/etc/zivpn/config.json" 2>/dev/null || echo 0)
    if [ $CONFIG_SIZE -lt 50 ]; then
        log "${YELLOW}Warning: config.json seems too small ($CONFIG_SIZE bytes)${NC}"
    fi
    
    # Cek SSL certificates
    if [ ! -f "/etc/zivpn/zivpn.crt" ] || [ ! -f "/etc/zivpn/zivpn.key" ]; then
        log "${YELLOW}Warning: SSL certificates missing${NC}"
    fi
    
    # Cek port tidak digunakan
    if ss -tulpn | grep -q ":5667 "; then
        log "${YELLOW}Warning: Port 5667 already in use${NC}"
        # Kill proses yang menggunakan port 5667
        OLD_PID=$(lsof -ti:5667 2>/dev/null || echo "")
        if [ -n "$OLD_PID" ]; then
            log "${CYAN}Killing old process on port 5667 (PID: $OLD_PID)${NC}"
            kill -9 $OLD_PID 2>/dev/null || true
            sleep 2
        fi
    fi
    
    echo -e "${GREEN}✓ Configuration test passed${NC}"
    echo ""
    return 0
}

# Create systemd service
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

# Setup firewall
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

# ===========================================
# PERUBAHAN 3: start_service() yang DIPERBAIKI
# ===========================================
start_service() {
    log "${YELLOW}Starting ZIVPN service...${NC}"
    
    # Stop service dulu jika sedang running
    systemctl stop zivpn.service 2>/dev/null || true
    sleep 2
    
    # Kill any remaining zivpn processes
    pkill -f "zivpn server" 2>/dev/null || true
    
    # Start service
    systemctl start zivpn.service
    sleep 5  # Beri waktu lebih untuk startup
    
    # Cek status service
    if systemctl is-active --quiet zivpn.service; then
        echo -e "${GREEN}✅ Service: RUNNING${NC}"
        
        # Tunggu sebentar lalu cek port listening
        sleep 3
        if ss -tulpn | grep -q ":5667"; then
            echo -e "${GREEN}✅ Port 5667: LISTENING${NC}"
            
            # Test koneksi lokal
            if command -v timeout >/dev/null 2>&1 && command -v nc >/dev/null 2>&1; then
                if timeout 2 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/5667" 2>/dev/null; then
                    echo -e "${GREEN}✅ Port 5667: ACCEPTING CONNECTIONS${NC}"
                else
                    echo -e "${YELLOW}⚠️  Port 5667: NOT ACCEPTING TCP CONNECTIONS (UDP only)${NC}"
                fi
            fi
        else
            echo -e "${RED}❌ Port 5667: NOT LISTENING${NC}"
            echo -e "${YELLOW}Checking service logs...${NC}"
            journalctl -u zivpn -n 10 --no-pager
            return 1
        fi
    else
        echo -e "${RED}❌ Service: FAILED TO START${NC}"
        echo -e "${YELLOW}Last 10 lines of log:${NC}"
        journalctl -u zivpn -n 10 --no-pager
        
        # Coba repair config
        echo ""
        echo -e "${YELLOW}Attempting to repair configuration...${NC}"
        repair_config
        systemctl start zivpn.service
        sleep 3
        
        if systemctl is-active --quiet zivpn.service; then
            echo -e "${GREEN}✅ Service started after repair${NC}"
        else
            echo -e "${RED}❌ Still failing after repair${NC}"
            return 1
        fi
    fi
    
    echo ""
    return 0
}

# ===========================================
# PERUBAHAN 4: verify_installation() BARU
# ===========================================
verify_installation() {
    log "${YELLOW}Verifying installation...${NC}"
    
    local errors=0
    local warnings=0
    
    echo "Checking components:"
    
    # 1. Cek binary
    if [ -f "/usr/local/bin/zivpn" ]; then
        echo -e "  ${GREEN}✓ Binary: Found at /usr/local/bin/zivpn${NC}"
        if [ -x "/usr/local/bin/zivpn" ]; then
            echo -e "  ${GREEN}✓ Binary: Executable${NC}"
        else
            echo -e "  ${YELLOW}⚠ Binary: Not executable, fixing...${NC}"
            chmod +x /usr/local/bin/zivpn
            warnings=$((warnings+1))
        fi
    else
        echo -e "  ${RED}✗ Binary: Not found${NC}"
        errors=$((errors+1))
    fi
    
    # 2. Cek config
    if [ -f "/etc/zivpn/config.json" ]; then
        echo -e "  ${GREEN}✓ Config: Found at /etc/zivpn/config.json${NC}"
        CONFIG_SIZE=$(stat -c%s "/etc/zivpn/config.json" 2>/dev/null || echo 0)
        if [ $CONFIG_SIZE -gt 50 ]; then
            echo -e "  ${GREEN}✓ Config: Size OK ($CONFIG_SIZE bytes)${NC}"
        else
            echo -e "  ${YELLOW}⚠ Config: Size suspicious ($CONFIG_SIZE bytes)${NC}"
            warnings=$((warnings+1))
        fi
    else
        echo -e "  ${RED}✗ Config: Not found${NC}"
        errors=$((errors+1))
    fi
    
    # 3. Cek SSL certs
    if [ -f "/etc/zivpn/zivpn.crt" ] && [ -f "/etc/zivpn/zivpn.key" ]; then
        echo -e "  ${GREEN}✓ SSL Certs: Found${NC}"
    else
        echo -e "  ${YELLOW}⚠ SSL Certs: Missing or incomplete${NC}"
        warnings=$((warnings+1))
    fi
    
    # 4. Cek service file
    if [ -f "/etc/systemd/system/zivpn.service" ]; then
        echo -e "  ${GREEN}✓ Service: Found at /etc/systemd/system/zivpn.service${NC}"
    else
        echo -e "  ${RED}✗ Service: Not found${NC}"
        errors=$((errors+1))
    fi
    
    # 5. Cek user database
    if [ -f "/etc/zivpn/users.db" ]; then
        echo -e "  ${GREEN}✓ User DB: Found${NC}"
    else
        echo -e "  ${YELLOW}⚠ User DB: Not found, creating...${NC}"
        echo "pondok123:9999999999:2:Admin" > /etc/zivpn/users.db
        warnings=$((warnings+1))
    fi
    
    # Summary
    echo ""
    if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
        echo -e "${GREEN}✅ All components verified successfully${NC}"
        return 0
    elif [ $errors -eq 0 ] && [ $warnings -gt 0 ]; then
        echo -e "${YELLOW}⚠ Installation completed with $warnings warning(s)${NC}"
        return 0
    else
        echo -e "${RED}❌ Installation has $errors error(s) and $warnings warning(s)${NC}"
        return 1
    fi
}

# ===========================================
# PERUBAHAN 5: repair_config() BARU
# ===========================================
repair_config() {
    log "${YELLOW}Repairing configuration...${NC}"
    
    # Backup config lama jika ada
    if [ -f "/etc/zivpn/config.json" ]; then
        BACKUP_FILE="/etc/zivpn/config.json.backup.$(date +%Y%m%d_%H%M%S)"
        cp "/etc/zivpn/config.json" "$BACKUP_FILE"
        log "${CYAN}Backed up old config to: $BACKUP_FILE${NC}"
    fi
    
    # Buat config baru yang PASTI benar
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
    
    # Pastikan SSL certs ada
    if [ ! -f "/etc/zivpn/zivpn.crt" ] || [ ! -f "/etc/zivpn/zivpn.key" ]; then
        log "${CYAN}Creating missing SSL certificates...${NC}"
        openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
            -subj "/CN=zivpn" \
            -keyout "/etc/zivpn/zivpn.key" \
            -out "/etc/zivpn/zivpn.crt" 2>/dev/null || true
    fi
    
    # Set permissions
    chmod 600 /etc/zivpn/*
    chown root:root /etc/zivpn/*
    
    echo -e "${GREEN}✓ Configuration repaired${NC}"
    echo ""
}

install_menu() {
    log "${YELLOW}Installing menu manager...${NC}"
    
    if wget -q "$REPO_URL/udp-ziv/main/user_zivpn.sh" -O "$MENU_SCRIPT"; then
        chmod +x "$MENU_SCRIPT"
        
        # Add alias
        if ! grep -q "alias menu=" /root/.bashrc; then
            echo "alias menu='zivpn-menu'" >> /root/.bashrc
        fi
        
        echo -e "${GREEN}✅ Menu manager installed${NC}"
        echo -e "${CYAN}Type 'menu' to open management menu${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Menu manager download failed${NC}"
        echo -e "${YELLOW}You can download it later manually${NC}"
        return 1
    fi
    echo ""
}

show_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}    ✅  ZIVPN INSTALLATION COMPLETE!  ${NC}"
    echo -e "${GREEN}========================================${NC}"
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
    
    if [ -f /etc/zivpn/.license_info ]; then
        LICENSE_USER=$(head -1 /etc/zivpn/.license_info 2>/dev/null)
        LICENSE_EXP=$(tail -1 /etc/zivpn/.license_info 2>/dev/null)
        echo -e "${CYAN}📝 LICENSE INFORMATION:${NC}"
        echo -e "  User        : $LICENSE_USER"
        echo -e "  Expiry      : $LICENSE_EXP"
        echo ""
    fi
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}        Telegram: @bendakerep        ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

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

# ===========================================
# PERUBAHAN 6: main() dengan urutan yang DIPERBAIKI
# ===========================================
main() {
    show_banner
    check_root
    check_license
    setup_swap
    install_deps
    download_binary
    setup_config
    
    # VERIFIKASI dan TEST sebelum create service
    verify_installation
    test_config
    
    create_service
    setup_firewall
    ask_port_forward
    
    # Start service dengan error handling
    if ! start_service; then
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}     SERVICE FAILED TO START!           ${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo -e "${YELLOW}Trying manual repair...${NC}"
        
        repair_config
        
        # Coba start lagi
        systemctl daemon-reload
        if start_service; then
            echo -e "${GREEN}✅ Service started successfully after repair${NC}"
        else
            echo -e "${RED}❌ Service still failing after repair${NC}"
            echo -e "${YELLOW}Please check:${NC}"
            echo "1. journalctl -u zivpn -n 30"
            echo "2. /usr/local/bin/zivpn server -c /etc/zivpn/config.json"
            echo "3. Check if port 5667 is already in use"
        fi
    fi
    
    install_menu
    show_summary
    auto_start_menu
}

# Run
main
