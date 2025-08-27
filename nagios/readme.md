---

# Nagios Core 4.5.9 Installation (Ubuntu 24.04)

A complete setup for **Nagios Core 4.5.9** with **Nagios Plugins 2.4.6**, using **Apache (port 8081)** as the backend and **nginx (port 80)** as a reverse proxy.

---

## ✅ What We Set Up (At a Glance)

- Built and installed **Nagios Core 4.5.9** from source  
  🔗 [GitHub - Nagios Enterprises](https://github.com/NagiosEnterprises/nagioscore)
- Installed **Nagios Plugins 2.4.6** (stable baseline)  
  🔗 [nagios-plugins.org](https://nagios-plugins.org)
- Configured **Apache** as CGI backend on port `8081` + **nginx** as front-end reverse proxy on port `80`
- Proper trailing-slash handling in proxy ensures Nagios web paths work correctly  
  🔗 [Vultr Docs](https://www.vultr.com/docs/) | [Stack Overflow](https://stackoverflow.com/) | [DigitalOcean](https://www.digitalocean.com/)
- Created `nagiosadmin` web user via `htpasswd`, integrated into Nagios web config  
  🔗 [Nagios Enterprises](https://www.nagios.com/) | [Apache HTTP Server Docs](https://httpd.apache.org/)
- Verified configuration with `nagios -v` for clean pre-flight check (standard quickstart step)

---

## 🚀 One-Shot Install Script

Save the script below as `install_nagios.sh`, then run:

```bash
chmod +x install_nagios.sh
sudo bash install_nagios.sh
```

> ✅ **Idempotent-ish**: Safe to re-run where possible.  
> 📢 Prints helpful status messages at each step.

### `install_nagios.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# === Versions (adjust as needed) ===
NAGIOS_VERSION="4.5.9"
PLUGINS_VERSION="2.4.6"

# === Paths & users ===
NAGIOS_USER="nagios"
NAGIOS_GROUP="nagios"
NAGCMD_GROUP="nagcmd"
APACHE_USER="www-data"
APACHE_PORT="8081"

echo "==> Updating packages & installing build dependencies"
sudo apt update
sudo apt install -y \
    build-essential gcc make autoconf automake libtool pkg-config \
    libgd-dev openssl libssl-dev apache2 apache2-utils php libapache2-mod-php php-gd \
    wget curl unzip

echo "==> Creating users/groups (safe if already exist)"
if ! id -u "${NAGIOS_USER}" >/dev/null 2>&1; then
    sudo useradd --system --home-dir /usr/local/nagios "${NAGIOS_USER}"
fi
if ! getent group "${NAGCMD_GROUP}" >/dev/null; then
    sudo groupadd "${NAGCMD_GROUP}"
fi
sudo usermod -a -G "${NAGCMD_GROUP}" "${NAGIOS_USER}"
sudo usermod -a -G "${NAGCMD_GROUP}" "${APACHE_USER}"

cd /tmp

echo "==> Downloading Nagios Core ${NAGIOS_VERSION}"
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
./configure \
    --with-nagios-user="${NAGIOS_USER}" \
    --with-nagios-group="${NAGIOS_GROUP}" \
    --with-command-group="${NAGCMD_GROUP}"

echo "==> Building Nagios Core"
make all

echo "==> Installing Nagios Core (binaries, service, configs, command mode, webconf)"
sudo make install
sudo make install-daemoninit
sudo make install-commandmode
sudo make install-config
sudo make install-webconf

echo "==> Adjusting Apache to listen on ${APACHE_PORT} (nginx fronts :80)"
if grep -qE '^[[:space:]]*Listen[[:space:]]+80$' /etc/apache2/ports.conf; then
    sudo sed -i 's/^\s*Listen 80$/Listen '"${APACHE_PORT}"'/' /etc/apache2/ports.conf
fi

echo "==> Setting up ServerName to suppress AH00558 warning"
if [ ! -f /etc/apache2/conf-available/fqdn.conf ]; then
    echo 'ServerName localhost' | sudo tee /etc/apache2/conf-available/fqdn.conf >/dev/null
    sudo a2enconf fqdn
fi

echo "==> Enabling required Apache modules & restarting"
sudo a2enmod rewrite cgi
sudo systemctl restart apache2

echo "==> Creating Nagios web user 'nagiosadmin' (you will set a password)"
HTPASSWD_FILE="/usr/local/nagios/etc/htpasswd.users"
if [ ! -f "${HTPASSWD_FILE}" ]; then
    sudo htpasswd -c "${HTPASSWD_FILE}" nagiosadmin
else
    sudo htpasswd "${HTPASSWD_FILE}" nagiosadmin
fi
sudo chown root:"${APACHE_USER}" "${HTPASSWD_FILE}"
sudo chmod 640 "${HTPASSWD_FILE}"

echo "==> Downloading Nagios Plugins ${PLUGINS_VERSION}"
cd /tmp
PLUGINS_TGZ="nagios-plugins-${PLUGINS_VERSION}.tar.gz"
if [ ! -f "${PLUGINS_TGZ}" ]; then
    wget -O "${PLUGINS_TGZ}" \
        "https://nagios-plugins.org/download/nagios-plugins-${PLUGINS_VERSION}.tar.gz"
fi

echo "==> Extracting & building Nagios Plugins"
rm -rf "nagios-plugins-${PLUGINS_VERSION}" || true
tar xzf "${PLUGINS_TGZ}"
cd "nagios-plugins-${PLUGINS_VERSION}"

./configure \
    --with-nagios-user="${NAGIOS_USER}" \
    --with-nagios-group="${NAGIOS_GROUP}"
make
sudo make install

echo "==> Creating optional host config directory & include"
CFG_FILE="/usr/local/nagios/etc/nagios.cfg"
if ! grep -q "^cfg_dir=/usr/local/nagios/etc/servers" "${CFG_FILE}"; then
    echo 'cfg_dir=/usr/local/nagios/etc/servers' | sudo tee -a "${CFG_FILE}" >/dev/null
fi
sudo mkdir -p /usr/local/nagios/etc/servers

echo "==> Setting up nginx reverse proxy for /nagios (port 80 → Apache ${APACHE_PORT})"
sudo tee /etc/nginx/conf.d/nagios.conf >/dev/null <<NGINX
server {
    listen 80;
    server_name _;

    location /nagios/ {
        proxy_pass http://127.0.0.1:${APACHE_PORT}/nagios/;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Host \$host;
    }
}
NGINX

echo "==> Testing & reloading nginx"
sudo nginx -t && sudo systemctl reload nginx || true

echo "==> Verifying Nagios configuration"
sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg

echo "==> Enabling & starting Nagios service"
sudo systemctl enable --now nagios

echo ""
echo "✅ Done! Nagios is now installed and running."
echo ""
echo "🔗 Access the Web UI: http://<your-server-ip>/nagios"
echo "👤 Login: nagiosadmin"
echo "🔐 Password: (the one you just set)"
```

---

## 🧠 Why This Script Follows Best Practices

- ✅ Uses official **Nagios Core GitHub releases** (correct ~2.47 MB tarball with build system)  
  🔗 [GitHub - nagioscore](https://github.com/NagiosEnterprises/nagioscore)
- ✅ Plugins sourced from **official nagios-plugins.org** tarballs (with `./configure` support)  
  🔗 [nagios-plugins.org](https://nagios-plugins.org)
- ✅ Follows Nagios **Quickstart Guide** steps: `make install-*` targets, proper permissions, `htpasswd`, etc.  
  🔗 [Nagios Enterprises Documentation](https://support.nagios.com/)
- ✅ Correct **reverse proxy pattern** (`/nagios/` → `/nagios/`) ensures static assets load properly  
  🔗 [Stack Overflow](https://stackoverflow.com/questions/13240561/) | [DigitalOcean Community](https://www.digitalocean.com/community/)
- ✅ Avoids common Apache warning `AH00558` by setting `ServerName`
- ✅ Optional: To run Apache directly on port 80, remove the nginx section and set `APACHE_PORT=80`

---

## ✅ Post-Install Checklist

1. 🌐 **Access the UI**:  
   Open `http://<your-server-ip>/nagios` → log in as `nagiosadmin`

2. 🖥️ **Add Remote Hosts**:  
   Place `.cfg` files in `/usr/local/nagios/etc/servers/`, then validate and restart:
   ```bash
   sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg
   sudo systemctl restart nagios
   ```

3. 📧 **Set Up Email Alerts**:  
   Install and configure a mail transfer agent like **Postfix**:
   ```bash
   sudo apt install postfix mailutils
   ```
   Test with:
   ```bash
   echo "Test email body" | mail -s "Nagios Test" your@email.com
   ```
   Then update contact definitions in Nagios config (`contacts.cfg` or equivalent).

---

## 📚 References

- [Nagios Core Quickstart Installation Guide](https://support.nagios.com/kb/article.php?id=515)
- [Nagios Plugins Official Site](https://nagios-plugins.org/)
- [Apache HTTP Server Authentication](https://httpd.apache.org/docs/2.4/mod/mod_authn_file.html#htpasswd)
- [nginx Reverse Proxy Guide](https://www.nginx.com/resources/admin-guide/reverse-proxy/)

---

> 💡 **Tip**: Customize `NAGIOS_VERSION` and `PLUGINS_VERSION` as needed for newer stable releases.

--- 
