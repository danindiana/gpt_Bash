---

# 🌿 Cacti Installation Script for Ubuntu 24.04

> **Fully automated setup** of Cacti with `nginx`, `PHP-FPM`, `MariaDB`, `RRDtool`, and `SNMP`  
> Uses the **"Track A" symlink method** to avoid Nginx `alias`/PHP pitfalls — proven to work.

After installation, access Cacti at:  
👉 **`http://<your-ip>/cacti/`**  
🔐 Default login: `admin` / `admin` *(you'll be forced to change it)*

---

## ✅ Features

- Installs **Cacti 1.2.x** from Ubuntu packages
- Web server: **nginx + PHP 8.3-FPM**
- Database: **MariaDB**
- Poller: **cacti-spine** (installed and ready)
- SNMP: **Localhost-only by default** (secure)
- Clean layout: `/var/www/html/cacti → /usr/share/cacti/site` (**symlink, no `alias`**)
- Automatic hardening of MariaDB and Apache conflict resolution
- Ready for production with optional HTTPS and SNMP LAN expansion

---

## 🚀 Quick Start

Save and run the installer as root:

```bash
# Save the script
curl -O https://raw.githubusercontent.com/your-repo/cacti/master/cacti_install.sh

# Make executable (optional)
chmod +x cacti_install.sh

# Run with sudo
sudo bash cacti_install.sh
```

---

## 📜 Installation Script

```bash
#!/usr/bin/env bash
# Cacti Install Script — Ubuntu 24.04
# Web: nginx + PHP-FPM | DB: MariaDB | Tools: RRDtool + SNMP + Spine
# Layout: /var/www/html/cacti -> /usr/share/cacti/site (symlink, no alias)
# After install: http://<IP>/cacti/ | Login: admin / admin

set -euo pipefail

log() { printf "\n[+] %s\n" "$*"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo bash $0"
    exit 1
  fi
}

require_root

# ---- Variables ----
PRIMARY_IP="$(hostname -I | awk '{print $1}')"
SERVER_NAMES="$PRIMARY_IP 127.0.0.1 localhost"

log "Updating apt and installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# Install core stack: web, php, db, snmp, rrdtool, cacti
apt-get install -y \
  nginx php8.3-fpm php8.3-cli php8.3-mysql php8.3-xml php8.3-gd php8.3-mbstring \
  php8.3-bcmath php8.3-zip php8.3-curl php8.3-intl php8.3-gmp \
  mariadb-server rrdtool snmp snmpd \
  cacti cacti-spine

log "Starting and enabling PHP-FPM and nginx..."
systemctl enable --now php8.3-fpm
systemctl enable --now nginx

# Disable Apache if present
if systemctl is-enabled --quiet apache2 2>/dev/null || systemctl is-active --quiet apache2 2>/dev/null; then
  log "Disabling Apache to avoid port conflicts..."
  systemctl disable --now apache2 || true
fi

# ---- Web Root & Symlink ----
log "Setting up web root and Cacti symlink..."
mkdir -p /var/www/html
ln -sfn /usr/share/cacti/site /var/www/html/cacti

# ---- Nginx Virtual Host ----
log "Configuring nginx for Cacti..."
cat > /etc/nginx/conf.d/cacti.conf <<EOF
server {
    listen 80;
    server_name ${SERVER_NAMES};

    root /var/www/html;
    index index.php index.html;

    location /cacti/ {
        try_files \$uri \$uri/ /cacti/index.php?\$args;
    }

    location ~ \\.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }

    access_log /var/log/nginx/cacti_access.log;
    error_log  /var/log/nginx/cacti_error.log;
}
EOF

nginx -t && systemctl reload nginx

# ---- MariaDB Security ----
log "Securing MariaDB (minimal hardening)..."
mysql --batch <<'SQL' || true
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.user WHERE User='' AND Host<>'localhost';
FLUSH PRIVILEGES;
SQL

# ---- Cacti Logs & Poller ----
log "Setting up Cacti log directory..."
mkdir -p /var/log/cacti
chown www-data:www-data /var/log/cacti || true

log "Ensuring poller cron is active..."
if [[ -f /etc/cron.d/cacti ]]; then
  grep -n . /etc/cron.d/cacti || true
else
  echo "WARN: /etc/cron.d/cacti not found (package usually provides it)."
fi
systemctl enable --now cron || true

# ---- SNMP Configuration ----
log "Configuring snmpd for localhost only (secure default)..."
cp -n /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.bak || true

if grep -q '^[[:space:]]*agentAddress' /etc/snmp/snmpd.conf; then
  sed -ri 's#^[[:space:]]*agentAddress.*#agentAddress udp:127.0.0.1:161,udp6:[::1]:161#' /etc/snmp/snmpd.conf
else
  echo 'agentAddress udp:127.0.0.1:161,udp6:[::1]:161' >> /etc/snmp/snmpd.conf
fi

grep -q '^rocommunity[[:space:]]\+public[[:space:]]\+127\.0\.0\.1' /etc/snmp/snmpd.conf || \
  echo 'rocommunity public 127.0.0.1' >> /etc/snmp/snmpd.conf

# Enable readable MIBs
if [[ -f /etc/snmp/snmp.conf ]]; then
  sed -i 's/^\s*mibs\s*:/# mibs :/' /etc/snmp/snmp.conf || true
fi

systemctl enable --now snmpd
systemctl restart snmpd

# ---- Final Checks ----
log "Installation Summary:"
echo " - Test access:"
echo "   curl -I http://${PRIMARY_IP}/cacti/"
echo
echo " - PHP-FPM status:"
systemctl --no-pager status php8.3-fpm | sed -n '1,6p'
echo
echo " - Poller cron job:"
sed -n '1,40p' /etc/cron.d/cacti || true
echo
echo " - SNMP test (localhost):"
snmpget -v2c -c public -On 127.0.0.1 1.3.6.1.2.1.1.5.0 || true

# ---- Post-Install Notes ----
cat <<'POST'

----------------------------------------------------------------------
🎉 Cacti is now installed and accessible!

🌐 Access Cacti:
   http://<THIS_MACHINE_IP>/cacti/

🔐 Default credentials:
   Username: admin
   Password: admin
   (You will be prompted to change the password on first login.)

🔧 Next Steps in the Web UI:
  1. Go to **Devices → Add**
     - Hostname: `127.0.0.1`
     - Template: `Linux Server`
     - SNMP Version: `2c`
     - Community: `public`
  2. Click **Create Graphs** for the new device (CPU, Memory, Interfaces)
  3. Wait 5–10 minutes (2 poll cycles) for data to appear

⚙️ Recommended Improvements:
  - **Switch to Spine**: Settings → Poller → Poller Type: `Spine`
  - **Enable LAN SNMP** (optional):
      - Edit `/etc/snmp/snmpd.conf`:  
        `agentAddress udp:161,udp6:[::1]:161`
      - (Optional) Allow LAN:  
        `ufw allow from 192.168.1.0/24 to any port 161 proto udp`
      - `systemctl restart snmpd`
  - **Add HTTPS** via Let's Encrypt or reverse proxy
  - **Add authentication** to `/cacti` in nginx for external access

----------------------------------------------------------------------
POST

log "Done! Open your browser: http://${PRIMARY_IP}/cacti/"
```

---

## 📝 Notes

- **Why symlinks?** Avoids `nginx` `alias` + `SCRIPT_FILENAME` issues. Clean, reliable, and standard.
- **Cacti source**: Uses the official Ubuntu package (`/usr/share/cacti/site`)
- **Security first**: SNMP listens only on `127.0.0.1` by default
- **No Apache conflicts**: Automatically disables Apache if detected
- **Poller ready**: `cacti-spine` is installed and can be enabled in Settings

---

## 🛡️ Optional Hardening

| Task | Command |
|------|--------|
| Enable HTTPS | Use `certbot` or reverse proxy with TLS |
| Restrict SNMP | Update community string and ACLs in `snmpd.conf` |
| Protect `/cacti` | Add `auth_basic` or IP allowlists in nginx |
| Tune MariaDB | Optimize `innodb_buffer_pool_size`, etc. |

---

> ✨ **You're all set! Monitor your network like a pro.** 🚀

--- 
