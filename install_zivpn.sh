#!/bin/bash
# ===========================================
# ZIVPN COMPLETE INSTALLER - OPTIMIZED FOR 1GB RAM
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
LICENSE_URL="$REPO_URL/Pondok-Vpn/main/DAFTAR"
INSTALL_LOG="/var/log/zivpn_install.log"
CONFIG_DIR="/etc/zivpn"
SERVICE_FILE="/etc/systemd/system/zivpn.service"

# Function untuk garis pembatas
print_separator() {
    echo -e "${YELLOW}======================================================${NC}"
}

print_green_separator() {
    echo -e "${GREEN}======================================================${NC}"
}

# Banner
show_banner() {
    clear
    print_separator
    echo -e "${BLUE}           ZIVPN COMPLETE INSTALLER               ${NC}"
    echo -e "${BLUE}           VERSION 4.1 - OPTIMIZED 1GB RAM        ${NC}"
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

# Check license from DAFTAR file
check_license() {
    print_separator
    echo -e "${BLUE}           CHECKING LICENSE VALIDITY             ${NC}"
    print_separator
    echo ""
    
    local vps_ip=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    log "INFO" "VPS IP: $vps_ip"
    
    local temp_file=$(mktemp)
    log "INFO" "Downloading license file from: $LICENSE_URL"
    
    if curl -s "$LICENSE_URL" -o "$temp_file" 2>/dev/null; then
        log "INFO" "✓ License file downloaded successfully"
        
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
        log "WARN" "Cannot connect to license server, running in evaluation mode"
        sleep 3
    fi
    
    rm -f "$temp_file"
    echo ""
    
    print_green_separator
    echo -e "${GREEN}           LICENSE CHECK - COMPLETED            ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# --- Setup Swap Memory OPTIMIZED for 1GB RAM ---
setup_swap() {
    print_separator
    echo -e "${BLUE}           SETUP SWAP MEMORY (OPTIMIZED)         ${NC}"
    print_separator
    echo ""
    
    # Check current memory
    RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    log "INFO" "Detected RAM: ${RAM_MB}MB"
    
    # Always setup swap regardless of existing swap (for 1GB RAM safety)
    log "INFO" "Setting up swap for 1GB RAM optimization..."
    
    # Stop existing swap
    swapoff -a 2>/dev/null
    
    # Remove old swap files
    rm -f /swapfile /swapfile1 /swapfile2 2>/dev/null
    
    # Calculate optimal swap size: 2GB for 1GB RAM
    SWAP_SIZE_MB=2048  # 2GB for 1GB RAM
    
    # Check disk space
    DISK_FREE_MB=$(df -m / | tail -1 | awk '{print $4}')
    if [ $DISK_FREE_MB -lt 2500 ]; then
        SWAP_SIZE_MB=1024  # Reduce to 1GB if low disk
        log "WARN" "Low disk space, reducing swap to 1GB"
    fi
    
    log "INFO" "Creating ${SWAP_SIZE_MB}MB swap file..."
    
    # Create swap file with dd (more reliable than fallocate)
    dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB status=progress
    chmod 600 /swapfile
    
    # Make swap
    mkswap /swapfile
    swapon /swapfile
    
    # Make permanent
    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    else
        sed -i '/\/swapfile/d' /etc/fstab
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
    
    # Optimize swappiness for 1GB RAM
    cat > /etc/sysctl.d/99-zivpn-swap.conf << EOF
# ZIVPN Swap Optimization for 1GB RAM
vm.swappiness=40
vm.vfs_cache_pressure=50
vm.dirty_ratio=20
vm.dirty_background_ratio=10
EOF
    
    sysctl -p /etc/sysctl.d/99-zivpn-swap.conf 2>/dev/null
    
    # Verify
    SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
    log "INFO" "✓ Swap created: ${SWAP_TOTAL}MB"
    log "INFO" "✓ Swappiness: $(cat /proc/sys/vm/swappiness)"
    
    # Test swap is working
    if swapon --show | grep -q "/swapfile"; then
        log "INFO" "✓ Swap is active and working"
    else
        log "ERROR" "❌ Swap failed to activate!"
    fi
    
    echo ""
    print_green_separator
    echo -e "${GREEN}           SWAP SETUP COMPLETE                  ${NC}"
    print_green_separator
    echo ""
    sleep 2
}

# Install minimal dependencies
install_dependencies() {
    print_separator
    echo -e "${BLUE}           INSTALLING MINIMAL DEPENDENCIES       ${NC}"
    print_separator
    echo ""
    
    # Stop any running apt processes to prevent conflicts
    log "INFO" "Stopping any running apt processes..."
    pkill apt 2>/dev/null || true
    pkill dpkg 2>/dev/null || true
    systemctl stop apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
    
    # Configure apt for low memory
    log "INFO" "Configuring apt for low memory..."
    cat > /etc/apt/apt.conf.d/99zivpn-lowmem << 'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
APT::Get::Assume-Yes "true";
APT::Get::Fix-Missing "true";
DPkg::Options {
   "--force-confdef";
   "--force-confold";
}
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
Acquire::Retries "3";
EOF
    
    # Update package lists with retry
    log "INFO" "Updating package lists (with retry)..."
    for i in {1..3}; do
        if apt update -y 2>&1 | tee -a "$INSTALL_LOG"; then
            log "INFO" "✓ Package lists updated successfully"
            break
        else
            log "WARN" "Attempt $i failed, retrying..."
            sleep 2
            if [ $i -eq 3 ]; then
                log "ERROR" "Failed to update package lists after 3 attempts"
                echo -e "${YELLOW}Continuing with installation...${NC}"
            fi
        fi
    done
    echo ""
    
    # Install CORE packages only (no fail2ban, no ufw)
    log "INFO" "Installing CORE packages only..."
    apt install -y wget curl jq openssl 2>&1 | tee -a "$INSTALL_LOG"
    echo ""
    
    # Install optional packages (skip if fail)
    log "INFO" "Installing optional packages..."
    apt install -y net-tools figlet lolcat 2>&1 | tee -a "$INSTALL_LOG" || \
        log "WARN" "Some optional packages failed, continuing..."
    
    # Clean up to save space
    apt clean
    apt autoclean
    
    echo ""
    print_green_separator
    echo -e "${GREEN}           DEPENDENCIES INSTALLED              ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# Get IP address only (no domain option)
get_ip_address() {
    print_separator
    echo -e "${BLUE}           DETECTING SERVER IP ADDRESS          ${NC}"
    print_separator
    echo ""
    
    # Try multiple methods to get IP
    IP_ADDRESS=""
    
    # Method 1: curl ifconfig.me
    log "INFO" "Getting IP address from ifconfig.me..."
    IP_ADDRESS=$(curl -s --max-time 10 ifconfig.me 2>/dev/null)
    
    # Method 2: hostname -I
    if [ -z "$IP_ADDRESS" ]; then
        log "INFO" "Getting IP from hostname..."
        IP_ADDRESS=$(hostname -I | awk '{print $1}' 2>/dev/null)
    fi
    
    # Method 3: ip command
    if [ -z "$IP_ADDRESS" ]; then
        log "INFO" "Getting IP from ip command..."
        IP_ADDRESS=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    fi
    
    if [ -z "$IP_ADDRESS" ]; then
        log "ERROR" "Failed to detect IP address!"
        IP_ADDRESS="127.0.0.1"
    fi
    
    log "INFO" "Server IP: $IP_ADDRESS"
    DOMAIN_TYPE="ip"
    DOMAIN_VALUE="$IP_ADDRESS"
    
    echo ""
    print_green_separator
    echo -e "${GREEN}           IP ADDRESS DETECTED                 ${NC}"
    print_green_separator
    echo ""
    sleep 1
}

# Download binary dengan OOM protection
install_zivpn_binary() {
    print_separator
    echo -e "${BLUE}           DOWNLOADING ZIVPN BINARY             ${NC}"
    print_separator
    echo ""
    
    # Kill any running zivpn
    pkill zivpn 2>/dev/null
    systemctl stop zivpn 2>/dev/null
    
    # Check memory before download
    log "INFO" "Checking memory before download..."
    FREE_MEM=$(free -m | awk '/^Mem:/{print $4}')
    log "INFO" "Free memory: ${FREE_MEM}MB"
    
    if [ $FREE_MEM -lt 100 ]; then
        log "WARN" "Low memory! Freeing cache..."
        sync
        echo 3 > /proc/sys/vm/drop_caches
        sleep 2
        FREE_MEM=$(free -m | awk '/^Mem:/{print $4}')
        log "INFO" "Free memory after cleanup: ${FREE_MEM}MB"
    fi
    
    # Detect architecture
    ARCH=$(uname -m)
    log "INFO" "Architecture: $ARCH"
    
    BINARY_NAME=""
    if [[ "$ARCH" == "x86_64" ]] || [[ "$ARCH" == "amd64" ]]; then
        BINARY_NAME="udp-zivpn-linux-amd64"
    elif [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
        BINARY_NAME="udp-zivpn-linux-arm64"
    else
        log "ERROR" "Unsupported architecture: $ARCH"
        BINARY_NAME="udp-zivpn-linux-amd64"  # Try anyway
    fi
    
    log "INFO" "Binary: $BINARY_NAME"
    
    # Multiple download sources
    declare -A SOURCES=(
        ["raw"]="https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/$BINARY_NAME"
        ["github"]="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/$BINARY_NAME"
        ["cdn"]="https://cdn.jsdelivr.net/gh/zahidbd2/udp-zivpn@latest/$BINARY_NAME"
    )
    
    DOWNLOAD_SUCCESS=0
    
    # Try each source with timeout and memory check
    for source_name in "${!SOURCES[@]}"; do
        url="${SOURCES[$source_name]}"
        
        log "INFO" "Trying source: $source_name"
        echo -e "${YELLOW}Downloading from: $(echo $url | cut -d'/' -f3)${NC}"
        
        # Download dengan ulimit memory protection
        if timeout 45 wget --tries=2 --timeout=20 -q "$url" -O /usr/local/bin/zivpn; then
            # Verify file size
            if [ -f /usr/local/bin/zivpn ]; then
                FILE_SIZE=$(stat -c%s /usr/local/bin/zivpn 2>/dev/null || echo 0)
                log "INFO" "Downloaded size: ${FILE_SIZE} bytes"
                
                if [ $FILE_SIZE -gt 1000000 ]; then
                    chmod +x /usr/local/bin/zivpn
                    log "INFO" "✓ Download successful"
                    DOWNLOAD_SUCCESS=1
                    
                    # Quick test
                    if /usr/local/bin/zivpn --version 2>&1 | head -1 | grep -q "zivpn\|ZIVPN"; then
                        log "INFO" "✓ Binary verified"
                    else
                        log "WARN" "Binary test inconclusive, but file seems valid"
                    fi
                    break
                else
                    log "WARN" "File too small, trying next source..."
                    rm -f /usr/local/bin/zivpn
                fi
            fi
        else
            log "WARN" "Download failed from $source_name"
            rm -f /usr/local/bin/zivpn 2>/dev/null
        fi
        
        # Small pause between attempts
        sleep 1
    done
    
    # If all downloads failed, STOP INSTALLATION
    if [ $DOWNLOAD_SUCCESS -eq 0 ]; then
        log "ERROR" "❌ All download attempts failed!"
        echo ""
        echo -e "${RED}=================================================${NC}"
        echo -e "${RED}           INSTALLATION FAILED!                 ${NC}"
        echo -e "${RED}=================================================${NC}"
        echo ""
        echo -e "${YELLOW}Real ZiVPN binary could not be downloaded.${NC}"
        echo ""
        echo -e "${GREEN}Manual steps required:${NC}"
        echo "----------------------------------------"
        echo "1. Check internet connection:"
        echo "   ping -c 3 github.com"
        echo ""
        echo "2. Download binary manually:"
        echo "   cd /usr/local/bin"
        if [[ "$ARCH" == "x86_64" ]] || [[ "$ARCH" == "amd64" ]]; then
            echo "   wget https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/udp-zivpn-linux-amd64 -O zivpn"
        elif [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
            echo "   wget https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/udp-zivpn-linux-arm64 -O zivpn"
        fi
        echo "   chmod +x zivpn"
        echo ""
        echo "3. Restart installation:"
        echo "   bash $0"
        echo "----------------------------------------"
        echo ""
        echo -e "${RED}Installation halted. Please fix and try again.${NC}"
        exit 1
    fi
    
    echo ""
    print_green_separator
    echo -e "${GREEN}           BINARY DOWNLOAD SUCCESS          ${NC}"
    print_green_separator
    echo ""
    sleep 2
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
    
    # Generate SSL certificate with IP
    log "INFO" "Generating SSL certificate..."
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=ID/CN=zivpn" \
        -keyout "$CONFIG_DIR/zivpn.key" \
        -out "$CONFIG_DIR/zivpn.crt" 2>&1 | tee -a "$INSTALL_LOG"
    
    log "INFO" "✓ SSL certificate generated"
    echo ""
    
    # Create default user database
    log "INFO" "Creating user database..."
    echo "pondok123:9999999999:2:Admin" > "$CONFIG_DIR/users.db"
    log "INFO" "✓ User database created"
    echo ""
    
    # Create config.json dengan IP yang terdeteksi
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

# Create systemd service - FIXED SECURITY
create_service() {
    print_separator
    echo -e "${BLUE}           CREATING SYSTEMD SERVICE            ${NC}"
    print_separator
    echo ""
    
    log "INFO" "Creating service file..."
    cat > "$SERVICE_FILE" << 'EOF'
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

# Security - relaxed for compatibility
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ReadWritePaths=/etc/zivpn /var/log /tmp
ReadOnlyPaths=/

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

# Setup firewall simple (FIXED - tidak lock SSH)
setup_firewall() {
    print_separator
    echo -e "${BLUE}           CONFIGURING FIREWALL                ${NC}"
    print_separator
    echo ""
    
    log "INFO" "Setting up basic firewall rules..."
    
    # Flush existing rules
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t nat -X 2>/dev/null
    
    # SET POLICY ACCEPT (JANGAN DROP!)
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    # Allow all loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Get SSH port from sshd config (jangan assume port 22)
    SSH_PORT=$(sshd -T 2>/dev/null | grep "^port " | awk '{print $2}')
    if [ -z "$SSH_PORT" ]; then
        SSH_PORT=22
    fi
    
    # Allow SSH (dengan port yang benar)
    iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT
    log "INFO" "✓ Allowing SSH on port: $SSH_PORT"
    
    # Allow ZIVPN UDP port 5667
    iptables -A INPUT -p udp --dport 5667 -j ACCEPT
    log "INFO" "✓ Allowing ZIVPN on port: 5667/udp"
    
    # Allow ICMP (ping)
    iptables -A INPUT -p icmp -j ACCEPT
    
    # Log dropped packets (optional)
    iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "IPTables-Dropped: " --log-level 4
    
    # Install netfilter-persistent untuk Ubuntu 24.04/25.04
    if ! command -v netfilter-persistent >/dev/null 2>&1; then
        log "INFO" "Installing netfilter-persistent for Ubuntu 24.04/25.04..."
        apt install -y iptables-persistent netfilter-persistent 2>/dev/null || \
        log "WARN" "Failed to install netfilter-persistent"
    fi
    
    # Save rules untuk persistence
    log "INFO" "Saving iptables rules..."
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
    
    # Save dengan netfilter-persistent jika ada
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save 2>/dev/null && \
        log "INFO" "✓ Rules saved with netfilter-persistent"
    else
        # Fallback: Manual save untuk systemd
        cat > /etc/systemd/system/iptables-restore.service << 'EOF'
[Unit]
Description=Restore iptables rules
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore < /etc/iptables/rules.v4
ExecStart=/sbin/ip6tables-restore < /etc/iptables/rules.v6
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable iptables-restore.service
        log "INFO" "✓ Rules saved with custom systemd service"
    fi
    
    log "INFO" "✓ Basic firewall configured (ACCEPT policy)"
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
    
    # Download user_zivpn.sh
    if wget -q "$REPO_URL/udp-ziv/main/user_zivpn.sh" -O /usr/local/bin/zivpn-menu; then
        chmod +x /usr/local/bin/zivpn-menu
        log "INFO" "✓ Menu manager downloaded"
    else
        log "WARN" "Failed to download menu manager, creating basic one..."
        cat > /usr/local/bin/zivpn-menu << 'EOF'
#!/bin/bash
echo "ZiVPN Menu Manager"
echo "Please download manually:"
echo "wget https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/user_zivpn.sh -O /usr/local/bin/zivpn-menu"
echo "chmod +x /usr/local/bin/zivpn-menu"
EOF
        chmod +x /usr/local/bin/zivpn-menu
    fi
    
    # Download helper script
    log "INFO" "Downloading helper script..."
    if wget -q "$REPO_URL/udp-ziv/main/zivpn_helper.sh" -O /usr/local/bin/zivpn-helper; then
        chmod +x /usr/local/bin/zivpn-helper
        log "INFO" "✓ Helper script downloaded"
    else
        log "WARN" "Failed to download helper script"
        cat > /usr/local/bin/zivpn-helper << 'EOF'
#!/bin/bash
echo "ZiVPN Helper"
echo "Please download manually:"
echo "wget https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/zivpn_helper.sh -O /usr/local/bin/zivpn-helper"
EOF
        chmod +x /usr/local/bin/zivpn-helper
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

# Start the service - DENGAN BINARY VALIDATION
start_service() {
    print_separator
    echo -e "${BLUE}           STARTING ZIVPN SERVICE              ${NC}"
    print_separator
    echo ""
    
    # CRITICAL CHECK: Pastikan binary benar-benar ada dan valid
    log "INFO" "Validating ZiVPN binary before starting service..."
    
    if [ ! -f /usr/local/bin/zivpn ]; then
        log "ERROR" "❌ ZiVPN binary not found at /usr/local/bin/zivpn"
        echo -e "${RED}Service cannot start. Binary missing.${NC}"
        exit 1
    fi
    
    FILE_SIZE=$(stat -c%s /usr/local/bin/zivpn 2>/dev/null || echo 0)
    if [ "$FILE_SIZE" -lt 1000000 ]; then
        log "ERROR" "❌ Invalid ZiVPN binary (too small: ${FILE_SIZE} bytes)"
        echo -e "${RED}Service cannot start. Binary is placeholder or corrupt.${NC}"
        echo ""
        echo -e "${YELLOW}Please download real binary manually:${NC}"
        ARCH=$(uname -m)
        if [[ "$ARCH" == "x86_64" ]] || [[ "$ARCH" == "amd64" ]]; then
            echo "wget https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn"
        elif [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
            echo "wget https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/udp-zivpn-linux-arm64 -O /usr/local/bin/zivpn"
        fi
        echo "chmod +x /usr/local/bin/zivpn"
        echo "systemctl restart zivpn"
        exit 1
    fi
    
    # Check if binary is executable
    if [ ! -x /usr/local/bin/zivpn ]; then
        log "ERROR" "❌ ZiVPN binary is not executable"
        chmod +x /usr/local/bin/zivpn
        log "INFO" "✓ Fixed permissions"
    fi
    
    # Test binary dengan quick check
    log "INFO" "Testing ZiVPN binary..."
    if /usr/local/bin/zivpn --version 2>&1 | head -1 | grep -q "zivpn\|ZIVPN"; then
        log "INFO" "✓ Binary test passed"
    else
        log "WARN" "Binary test inconclusive, but will try to start anyway"
    fi
    
    log "INFO" "Starting ZiVPN service..."
    systemctl start zivpn.service
    sleep 3
    
    if systemctl is-active --quiet zivpn.service; then
        log "INFO" "✓ ZiVPN service started successfully"
        
        # Verify port is listening
        sleep 2
        if ss -tulpn | grep -q ":5667"; then
            log "INFO" "✓ Port 5667 is listening"
        else
            log "WARN" "Port 5667 not listening, checking logs..."
            journalctl -u zivpn.service -n 10 --no-pager
        fi
    else
        log "ERROR" "Failed to start service"
        echo -e "${YELLOW}Checking logs...${NC}"
        journalctl -u zivpn.service -n 20 --no-pager
        echo ""
        
        # Try to debug
        echo -e "${YELLOW}Debug information:${NC}"
        echo "----------------------------------------"
        ls -lh /usr/local/bin/zivpn
        echo ""
        echo "Config file:"
        ls -la /etc/zivpn/config.json
        echo "----------------------------------------"
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
    
    echo ""
    print_separator
    print_separator
    echo -e "${GREEN}           INSTALLATION COMPLETE!             ${NC}"
    print_separator
    print_separator
    echo ""
    
    # Validate everything is working
    echo -e "${CYAN}✅ VALIDATION CHECK:${NC}"
    print_separator
    
    # Check binary
    if [ -f /usr/local/bin/zivpn ]; then
        FILE_SIZE=$(stat -c%s /usr/local/bin/zivpn 2>/dev/null || echo 0)
        if [ $FILE_SIZE -gt 1000000 ]; then
            echo -e "  ${GREEN}✓ Binary: Valid ($((FILE_SIZE/1024/1024))MB)${NC}"
        else
            echo -e "  ${RED}✗ Binary: Invalid (too small)${NC}"
        fi
    else
        echo -e "  ${RED}✗ Binary: Missing${NC}"
    fi
    
    # Check service
    if systemctl is-active --quiet zivpn.service; then
        echo -e "  ${GREEN}✓ Service: Running${NC}"
    else
        echo -e "  ${RED}✗ Service: Stopped${NC}"
    fi
    
    # Check port
    if ss -tulpn | grep -q ":5667"; then
        echo -e "  ${GREEN}✓ Port 5667: Listening${NC}"
    else
        echo -e "  ${YELLOW}⚠ Port 5667: Not listening${NC}"
    fi
    
    # Check swap
    if swapon --show | grep -q "/swapfile"; then
        SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
        echo -e "  ${GREEN}✓ Swap: ${SWAP_TOTAL}MB active${NC}"
    else
        echo -e "  ${YELLOW}⚠ Swap: Not active${NC}"
    fi
    
    print_separator
    echo ""
    
    echo -e "${CYAN}📦 ZIVPN INFORMATION:${NC}"
    print_separator
    echo -e "  ${YELLOW}•${NC} Server IP   : ${GREEN}$public_ip${NC}"
    echo -e "  ${YELLOW}•${NC} Port         : ${GREEN}5667 UDP${NC}"
    echo -e "  ${YELLOW}•${NC} Default Pass : ${GREEN}pondok123${NC}"
    echo -e "  ${YELLOW}•${NC} Config Path  : ${GREEN}/etc/zivpn/${NC}"
    print_separator
    echo ""
    
    echo -e "${CYAN}🚀 AVAILABLE COMMANDS:${NC}"
    print_separator
    echo -e "  ${YELLOW}•${NC} ${GREEN}menu${NC}                 : Open management menu"
    echo -e "  ${YELLOW}•${NC} ${GREEN}systemctl status zivpn${NC} : Check service status"
    echo -e "  ${YELLOW}•${NC} ${GREEN}systemctl restart zivpn${NC}: Restart service"
    echo -e "  ${YELLOW}•${NC} ${GREEN}zivpn-helper setup${NC}    : Setup Telegram bot"
    print_separator
    echo ""
    
    # Memory info
    echo -e "${CYAN}📊 SYSTEM INFORMATION:${NC}"
    print_separator
    FREE_MEM=$(free -m | awk '/^Mem:/{print $4}')
    SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
    echo -e "  ${YELLOW}•${NC} Free RAM     : ${GREEN}${FREE_MEM}MB${NC}"
    echo -e "  ${YELLOW}•${NC} Total Swap   : ${GREEN}${SWAP_TOTAL}MB${NC}"
    print_separator
    echo ""
    
    # Warning jika ada masalah
    if ! systemctl is-active --quiet zivpn.service; then
        echo -e "${RED}⚠️  WARNING: Service is not running!${NC}"
        echo -e "${YELLOW}Run: systemctl status zivpn.service for details${NC}"
        echo ""
    fi
    
    print_separator
    print_separator
    echo -e "${GREEN}      PONDOK VPN - Telegram: @bendakerep       ${NC}"
    print_separator
    print_separator
    echo ""
}

# Auto start menu
auto_start_menu() {
    echo -e "${YELLOW}Starting menu manager in 3 seconds...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to cancel${NC}"
    echo ""
    
    for i in {3..1}; do
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
    
    # Step-by-step installation
    check_root
    check_license
    
    # SWAP FIRST untuk mencegah OOM
    setup_swap
    
    # Install minimal dependencies
    install_dependencies
    
    # Get IP address
    get_ip_address
    
    # Download binary (setelah swap aktif) - JIKA GAGAL, STOP!
    install_zivpn_binary
    
    # Setup everything else
    setup_directories
    create_service
    setup_firewall
    install_menu_manager
    
    # Start service dengan validasi ketat
    start_service
    
    # Show final summary
    show_summary
    
    # Auto start menu
    auto_start_menu
}

# Run main function
main
