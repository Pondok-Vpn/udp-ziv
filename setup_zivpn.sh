#!/bin/bash
echo "=== ZIVPN UDP SIMPLE INSTALL ==="
# Install
apt update
apt install -y wget openssl

# Download
wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn

# Buat folder
mkdir -p /etc/zivpn

# Buat password file
echo "pondok123" > /etc/zivpn/passwords
echo "test456" >> /etc/zivpn/passwords

# Buat cert
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
  -subj "/C=ID/CN=zivpn" \
  -keyout "/etc/zivpn/key.pem" \
  -out "/etc/zivpn/cert.pem"

# Jalankan server
/usr/local/bin/zivpn server -listen ":5667" \
  -cert "/etc/zivpn/cert.pem" \
  -key "/etc/zivpn/key.pem" \
  -passwords "/etc/zivpn/passwords" &

echo ""
echo "=== SELESAI ==="
echo "Port: 5667 UDP"
echo "Password: pondok123, test456"
echo ""
echo "TAMBAH PASSWORD:"
echo "echo 'password_baru' >> /etc/zivpn/passwords"
echo "pkill zivpn"
echo "/usr/local/bin/zivpn server -listen ':5667' -cert '/etc/zivpn/cert.pem' -key '/etc/zivpn/key.pem' -passwords '/etc/zivpn/passwords' &"

echo ""
echo "=== MEMBUAT MENU MANAGER ==="

# Buat menu manager
cat > /usr/local/bin/zivpn-menu << 'EOF'
#!/bin/bash
echo "=== ZIVPN MANAGER ==="
echo "1. Buat User Biasa (Hari)"
echo "2. Buat User Trial (Menit)"
echo "3. Lihat User"
echo "4. Hapus User"
echo "5. Restart Server"
echo "6. Keluar"
read -p "Pilih [1-6]: " pilih

case $pilih in
  1)
    read -p "Password: " pass
    read -p "Berapa hari: " hari
    if [[ $hari =~ ^[0-9]+$ ]]; then
      expiry=$(date -d "+$hari days" +%s)
      echo "$pass:$expiry" >> /etc/zivpn/users.db
      echo "✓ User BIASA $pass dibuat ($hari hari)"
      read -p "Restart server sekarang? (y/n): " restart
      if [[ $restart == "y" ]]; then
        pkill zivpn
        /usr/local/bin/zivpn server -listen ":5667" -cert "/etc/zivpn/zivpn.crt" -key "/etc/zivpn/zivpn.key" -db "/etc/zivpn/users.db" &
        echo "✓ Server direstart"
      fi
    else
      echo "✗ Hari harus angka"
    fi
    ;;
  2)
    read -p "Password: " pass
    read -p "Berapa menit: " menit
    if [[ $menit =~ ^[0-9]+$ ]]; then
      expiry=$(date -d "+$menit minutes" +%s)
      echo "$pass:$expiry" >> /etc/zivpn/users.db
      echo "✓ User TRIAL $pass dibuat ($menit menit)"
      read -p "Restart server sekarang? (y/n): " restart
      if [[ $restart == "y" ]]; then
        pkill zivpn
        /usr/local/bin/zivpn server -listen ":5667" -cert "/etc/zivpn/zivpn.crt" -key "/etc/zivpn/zivpn.key" -db "/etc/zivpn/users.db" &
        echo "✓ Server direstart"
      fi
    else
      echo "✗ Menit harus angka"
    fi
    ;;
  3)
    echo "=== DAFTAR USER ==="
    if [ -f /etc/zivpn/users.db ]; then
      while IFS=: read -r pass expiry; do
        seconds=$((expiry - $(date +%s)))
        if [ $seconds -gt 0 ]; then
          if [ $seconds -lt 86400 ]; then
            minutes=$((seconds / 60))
            echo "TRIAL: $pass - $minutes menit lagi"
          else
            days=$((seconds / 86400))
            echo "BIASA: $pass - $days hari lagi"
          fi
        else
          echo "EXPIRED: $pass"
        fi
      done < /etc/zivpn/users.db
    else
      echo "Belum ada user"
    fi
    ;;
  4)
    read -p "Password yg dihapus: " pass
    if grep -q "^$pass:" /etc/zivpn/users.db; then
      grep -v "^$pass:" /etc/zivpn/users.db > /tmp/users.tmp
      mv /tmp/users.tmp /etc/zivpn/users.db
      echo "✓ User $pass dihapus"
      read -p "Restart server sekarang? (y/n): " restart
      if [[ $restart == "y" ]]; then
        pkill zivpn
        /usr/local/bin/zivpn server -listen ":5667" -cert "/etc/zivpn/zivpn.crt" -key "/etc/zivpn/zivpn.key" -db "/etc/zivpn/users.db" &
        echo "✓ Server direstart"
      fi
    else
      echo "✗ User tidak ditemukan"
    fi
    ;;
  5)
    echo "Restarting server..."
    pkill zivpn
    /usr/local/bin/zivpn server -listen ":5667" -cert "/etc/zivpn/zivpn.crt" -key "/etc/zivpn/zivpn.key" -db "/etc/zivpn/users.db" &
    echo "✓ Server direstart"
    ;;
  6)
    echo "Keluar..."
    exit 0
    ;;
  *)
    echo "Pilihan salah"
    ;;
esac

# Kembali ke menu setelah selesai
read -p "Tekan Enter untuk kembali ke menu..."
/usr/local/bin/zivpn-menu
EOF

chmod +x /usr/local/bin/zivpn-menu

# Buat alias di bashrc
echo "alias menu='zivpn-menu'" >> ~/.bashrc
source ~/.bashrc

# ===== LANGSUNG JALANKAN MENU SETELAH INSTALL =====
echo ""
echo "=== LANGSUNG KE MENU MANAGER ==="
sleep 2
zivpn-menu
