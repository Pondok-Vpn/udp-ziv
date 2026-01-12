#!/bin/bash
# Real-time multi login checker for ZIVPN

CONFIG_DIR="/etc/zivpn"
CONFIG_FILE="$CONFIG_DIR/config.json"
USER_DB="$CONFIG_DIR/users.db"
BLOCKED_LOG="$CONFIG_DIR/blocked.log"
PORT="5667"

# Cek apakah auto-block aktif
if [ ! -f "$CONFIG_DIR/.auto_block" ]; then
    exit 0
fi

mode=$(cat "$CONFIG_DIR/.auto_block" 2>/dev/null)
if [ "$mode" != "STRICT" ]; then
    exit 0
fi

# Ambil semua password dari config.json
users=$(jq -r '.auth.config[]?' "$CONFIG_FILE" 2>/dev/null 2>/dev/null || echo "")

for password in $users; do
    # Cari user di database
    user_info=$(grep "^$password:" "$USER_DB" 2>/dev/null)
    if [ -n "$user_info" ]; then
        IFS=':' read -r pass expiry client_name <<< "$user_info"
        
        # Cari IP aktif untuk port 5667
        active_ips=$(conntrack -L -p udp --dport "$PORT" 2>/dev/null \
            | awk '{for(i=1;i<=NF;i++) if ($i ~ /^src=/) print $i}' \
            | cut -d= -f2 | sort -u)
        
        ip_count=$(echo "$active_ips" | grep -c .)
        
        if [ "$ip_count" -gt 1 ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') CRON-MULTI: user=$client_name IPs=$ip_count" >> "$BLOCKED_LOG"
            
            # Blokir IP kelebihan
            counter=0
            echo "$active_ips" | while read ip; do
                counter=$((counter + 1))
                if [ $counter -gt 1 ]; then
                    iptables -C INPUT -s "$ip" -p udp --dport "$PORT" -j DROP 2>/dev/null || \
                    iptables -A INPUT -s "$ip" -p udp --dport "$PORT" -j DROP
                fi
            done
        fi
    fi
done
