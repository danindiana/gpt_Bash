#!/usr/bin/env bash
set -euo pipefail

# === Versions (adjust as needed) ===
NAGIOS_VERSION="4.5.9"
# Stable plugins release with generated ./configure
PLUGINS_VERSION="2.4.6"

# === Paths & users ===
NAGIOS_USER="nagios"
NAGIOS_GROUP="nagios"
NAGCMD_GROUP="nagcmd"
APACHE_USER="www-data"
APACHE_PORT="8081"

echo "==> Updating packages & installing build deps"
sudo apt update
sudo apt install -y \
  build-essential gcc make autoconf automake libtool pkg-config \
  libgd-dev openssl libssl-dev apache2 apache2-utils php libapache2-mod-php php-gd \
  wget curl unzip

echo "==> Creating users/groups (safe if already exist)"
if ! id -u "${NAGIOS_USER}" >/dev/null 2>&1; then
  sudo useradd "${NAGIOS_USER}"
fi
if ! getent group "${NAGCMD_GROUP}" >/dev/null; then
  sudo groupadd "${NAGCMD_GROUP}"
fi
sudo usermod -a -G "${NAGCMD_GROUP}" "${NAGIOS_USER}"
sudo usermod -a -G "${NAGCMD_GROUP}" "${APACHE_USER}"

cd /tmp

echo "==> Downloading Nagios Core ${NAGIOS_VERSION}"
# Use the official GitHub release tarball that includes the build system
CORE_TGZ="nagios-${NAGIOS_VERSION}.tar.gz"
if [ ! -f "${CORE_TGZ}" ]; then
  wget -O "${CORE_TGZ}" \
    "https://github.com/NagiosEnterprises/nagioscore/releases/download/nagios-${NAGIOS_VERSION}/nagios-${NAGIOS_VERSION}.tar.gz"
fi

echo "==> Extracting Nagios Core"
rm -rf "nagios-${NAGIOS_VERSION}" || true
tar xzf "${CORE_TGZ}"
cd "nagios-${NAGIOS_VERSION}"

echo "==> Configuring Nagios Core"
./configure --with-nagios-group="${NAGIOS_GROUP}" --with-command-group="${NAGCMD_GROUP}"

echo "==> Building Nagios Core"
make all

echo "==> Installing Nagios Core (binaries, service, configs, command mode, webconf)"
sudo make install
sudo make install-daemoninit
sudo make install-commandmode
sudo make install-config
sudo make install-webconf

echo "==> Adjusting Apache to listen on ${APACHE_PORT} (nginx fronts :80)"
# Switch Apache listen 80 -> 8081 only if a plain 'Listen 80' exists
if grep -qE '^[[:space:]]*Listen[[:space:]]+80$' /etc/apache2/ports.conf; then
  sudo sed -i 's/^\s*Listen 80$/Listen '"${APACHE_PORT}"'/' /etc/apache2/ports.conf
fi

# Basic ServerName to silence AH00558 (optional)
if [ ! -f /etc/apache2/conf-available/fqdn.conf ]; then
  echo 'ServerName localhost' | sudo tee /etc/apache2/conf-available/fqdn.conf >/dev/null
  sudo a2enconf fqdn
fi

echo "==> Enabling required Apache modules & restarting"
sudo a2enmod rewrite cgi
sudo systemctl restart apache2

echo "==> Creating Nagios web user 'nagiosadmin' (set a password when prompted)"
if [ ! -f /usr/local/nagios/etc/htpasswd.users ]; then
  sudo htpasswd -c /usr/local/nagios/etc/htpasswd.users nagiosadmin
else
  sudo htpasswd /usr/local/nagios/etc/htpasswd.users nagiosadmin
fi
sudo chown root:www-data /usr/local/nagios/etc/htpasswd.users
sudo chmod 640 /usr/local/nagios/etc/htpasswd.users

echo "==> Downloading Nagios Plugins ${PLUGINS_VERSION}"
cd /tmp
PLUGINS_TGZ="nagios-plugins-${PLUGINS_VERSION}.tar.gz"
if [ ! -f "${PLUGINS_TGZ}" ]; then
  wget -O "${PLUGINS_TGZ}" "https://nagios-plugins.org/download/nagios-plugins-${PLUGINS_VERSION}.tar.gz"
fi

echo "==> Extracting & building Nagios Plugins"
rm -rf "nagios-plugins-${PLUGINS_VERSION}" || true
tar xzf "${PLUGINS_TGZ}"
cd "nagios-plugins-${PLUGINS_VERSION}"
./configure --with-nagios-user="${NAGIOS_USER}" --with-nagios-group="${NAGIOS_GROUP}"
make
sudo make install

echo "==> Creating an optional host config directory & include (if not present)"
if ! grep -q '^cfg_dir=/usr/local/nagios/etc/servers' /usr/local/nagios/etc/nagios.cfg; then
  echo 'cfg_dir=/usr/local/nagios/etc/servers' | sudo tee -a /usr/local/nagios/etc/nagios.cfg >/dev/null
fi
sudo mkdir -p /usr/local/nagios/etc/servers

echo "==> Setting up nginx reverse proxy for /nagios (port 80 -> Apache ${APACHE_PORT})"
# Create a simple server block under conf.d; adjust if you prefer sites-available/sites-enabled
sudo tee /etc/nginx/conf.d/nagios.conf >/dev/null <<NGINX
server {
    listen 80;
    server_name _;

    location /nagios/ {
        proxy_pass http://127.0.0.1:${APACHE_PORT}/nagios/;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX

echo "==> Testing & reloading nginx"
sudo nginx -t
sudo systemctl reload nginx || true

echo "==> Verifying Nagios configuration"
sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg

echo "==> Enabling & starting Nagios"
sudo systemctl enable --now nagios

echo "==> Done!"
echo "Browse to:  http://<this-host>/nagios"
echo "Login with:  nagiosadmin (password you just set)"
