#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-ryleh-openweb.duckdns.org}"
WEBROOT="${2:-/var/www/letsencrypt-challenges}"

say(){ printf "\n== %s ==\n" "$*"; }

say "NGINX basics"
sudo nginx -t && echo "OK: nginx -t"
systemctl is-active --quiet nginx && echo "OK: nginx running" || echo "WARN: nginx not running"

say "Virtual host duplicates for ${HOST}"
sudo nginx -T 2>/dev/null | awk '/server_name/{print NR": "$0}' | grep -F "$HOST" || echo "No server_name lines found"
sudo nginx -T 2>/dev/null | grep -nE "server_name .*${HOST}" -n || true

say "ACME location reachability (LOCAL with Host SNI)"
TESTFILE="${WEBROOT%/}/health"
sudo install -d -o www-data -g www-data -m 0755 "$WEBROOT" >/dev/null 2>&1 || true
echo diag | sudo tee "$TESTFILE" >/dev/null
curl -si -H "Host: ${HOST}" "http://127.0.0.1/.well-known/acme-challenge/health" | sed -n '1,6p'

say "DuckDNS A/AAAA vs WAN IP"
WAN4=$(curl -s ifconfig.me)
DNS4=$(dig +short "${HOST}" A | tail -n1)
DNS6=$(dig +short "${HOST}" AAAA | tail -n1)
echo "WAN IPv4: ${WAN4}"
echo "DNS  A  : ${DNS4:-<none>}"
echo "DNS AAAA: ${DNS6:-<none>}"
[ -n "${DNS4}" ] && [ "${WAN4}" = "${DNS4}" ] && echo "OK: A record matches WAN" || echo "WARN: A != WAN (update DuckDNS)"
[ -n "${DNS6}" ] && echo "NOTE: AAAA present; ensure host serves IPv6 or clear AAAA at DuckDNS"

say "HTTP from outside? (best check from LTE). Quick local check:"
curl -s "http://${HOST}/.well-known/acme-challenge/health" | sed -n '1p'

say "Certbot inventory & renewal"
sudo certbot certificates || true
echo
sudo systemctl list-timers | grep -i certbot || echo "No certbot timer? Using cron or manual DNS-01."

say "Notes"
cat <<'TIP'
- If ACME test 404s locally, ensure nginx has:
    location ^~ /.well-known/acme-challenge/ {
        alias /var/www/letsencrypt-challenges/;
        default_type "text/plain";
        try_files $uri =404;
    }
  (and that block is in the SAME :80 server as your host, not proxied)
- For webroot plugin, server must serve /.well-known/acme-challenge files literally. :contentReference[oaicite:5]{index=5}
- For DuckDNS DNS-01, use the TXT API with your token for auth/cleanup hooks. :contentReference[oaicite:6]{index=6}
TIP
