#!/usr/bin/env bash
# Cacti install (Ubuntu 24.04) — nginx + PHP-FPM + MariaDB + RRDtool + SNMP
# Layout: /var/www/html/cacti -> /usr/share/cacti/site (symlink, no alias)
# After install, browse: http://<IP>/cacti/  (login: admin / admin)

set -euo pipefail

log() { printf "\n[+] %s\n" "$*"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo bash $0"
    exit 1
  fi
}

require_root

# ---- Vars ----
PRIMARY_IP="$(hostname -I | awk '{print $1}')"
# Change if you prefer a fixed name; we’ll bind vhost to IP + localhost
SERVER_NAMES="$PRIMARY_IP 127.0.0.1 localhost"

log "Updating apt and installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# Web + PHP + DB + SNMP + RRDtool + cacti (packaged)
apt-get install -y \
  nginx php8.3-fpm php8.3-cli php8.3-mysql php8.3-xml php8.3-gd php8.3-mbstring \
  php8.3-bcmath php8.3-zip php8.3-curl php8.3-intl php8.3-gmp \
  mariadb-server rrdtool snmp snmpd \
  cacti cacti-spine

log "Ensuring PHP-FPM and nginx are enabled/running..."
systemctl enable --now php8.3-fpm
systemctl enable --now nginx

# Optional: if Apache is present, stop/disable it to avoid port 80 conflicts
if systemctl is-enabled --quiet apache2 2>/dev/null || systemctl is-active --quiet apache2 2>/dev/null; then
  log "Disabling Apache (using nginx for Cacti)..."
  systemctl disable --now apache2 || true
fi

# ---- Web root & symlink ----
log "Preparing web root and Cacti symlink..."
mkdir -p /var/www/html
# Symlink /var/www/html/cacti -> /usr/share/cacti/site (packaged app lives there)
ln -sfn /usr/share/cacti/site /var/www/html/cacti

# ---- Nginx vhost (root-based, no alias) ----
log "Writing nginx vhost for Cacti..."
cat > /etc/nginx/conf.d/cacti.conf <<EOF
server {
    listen 80;
    server_name ${SERVER_NAMES};

    root /var/www/html;
    index index.php index.html;

    # Route /cacti to its front controller when needed
    location /cacti/ {
        try_files \$uri \$uri/ /cacti/index.php?\$args;
    }

    # Standard PHP handling for the whole server
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }

    access_log /var/log/nginx/cacti_access.log;
    error_log  /var/log/nginx/cacti_error.log;
}
EOF

nginx -t
systemctl reload nginx

# ---- MariaDB sanity (dbconfig-common usually did the work already) ----
log "Securing MariaDB minimally (skip if you've already hardened it)..."
# Non-interactive equivalent of a tiny subset of mysql_secure_installation hardening
# (Leave root via unix_socket, remove test DB if present)
mysql --batch <<'SQL' || true
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.user WHERE User='' AND Host<>'localhost';
FLUSH PRIVILEGES;
SQL

# ---- Cacti logs & poller ----
log "Ensuring Cacti log dir exists and is writable..."
mkdir -p /var/log/cacti
chown www-data:www-data /var/log/cacti || true

log "Verifying poller cron is present (every 5 minutes)..."
if [[ -f /etc/cron.d/cacti ]]; then
  grep -n . /etc/cron.d/cacti || true
else
  echo "WARN: /etc/cron.d/cacti not found (package usually provides it)."
fi
systemctl enable --now cron || true

# ---- SNMP agent (local-only by default for safety) ----
log "Configuring snmpd for LOCALHOST only (safe default)."
cp -n /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.bak || true
# Keep the default 'systemonly' view and ensure localhost listen:
if grep -q '^[[:space:]]*agentAddress' /etc/snmp/snmpd.conf; then
  sed -ri 's#^[[:space:]]*agentAddress.*#agentAddress udp:127.0.0.1:161,udp6:[::1]:161#' /etc/snmp/snmpd.conf
else
  echo 'agentAddress udp:127.0.0.1:161,udp6:[::1]:161' >> /etc/snmp/snmpd.conf
fi
# Ensure we at least allow a localhost RO community for quick tests
grep -q '^rocommunity[[:space:]]\+public[[:space:]]\+127\.0\.0\.1' /etc/snmp/snmpd.conf || \
  echo 'rocommunity public 127.0.0.1' >> /etc/snmp/snmpd.conf

# Enable readable MIB names for client tools (optional quality-of-life)
if [[ -f /etc/snmp/snmp.conf ]]; then
  sed -i 's/^\s*mibs\s*:/# mibs :/' /etc/snmp/snmp.conf || true
fi

systemctl enable --now snmpd
systemctl restart snmpd

# ---- Final checks ----
log "Quick checks:"
echo " - nginx vhost:"
echo "   curl -I http://${PRIMARY_IP}/cacti/ || true"
echo " - PHP-FPM status:"
systemctl --no-pager status php8.3-fpm | sed -n '1,6p'
echo " - Cacti poller cron (/etc/cron.d/cacti):"
sed -n '1,40p' /etc/cron.d/cacti || true
echo " - SNMP localhost test (numeric OID for sysName.0):"
snmpget -v2c -c public -On 127.0.0.1 1.3.6.1.2.1.1.5.0 || true

cat <<'POST'
----------------------------------------------------------------------
Cacti should now be reachable at:

  http://<THIS_MACHINE_IP>/cacti/

Default credentials:
  username: admin
  password: admin
(You will be forced to change the password.)

Next steps in the Cacti UI:
  1) Devices -> Add -> Hostname: 127.0.0.1, Template: Linux Server,
     SNMP version: 2c, Community: public.
  2) "Create Graphs" for that device (CPU/Memory/Interfaces).
  3) Wait ~5–10 minutes (two poll cycles) for graphs to populate.

Optional hardening & tuning (manual, recommended later):
  - Switch poller to "Spine" in Settings -> Poller (since cacti-spine is installed).
  - Move SNMP beyond localhost:
      * /etc/snmp/snmpd.conf:   agentAddress udp:161,udp6:[::1]:161
      * (optional) UFW allow from your LAN: ufw allow from 192.168.1.0/24 to any port 161 proto udp
      * systemctl restart snmpd
  - Put Cacti behind HTTPS and authentication at nginx.
----------------------------------------------------------------------

POST

log "Done. Open: http://${PRIMARY_IP}/cacti/"
