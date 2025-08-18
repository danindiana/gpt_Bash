#!/bin/bash

# ===================================================================================
# Comprehensive Diagnostic Script for OpenWebUI + Nginx + Nginx-UI Stack
#
# Based on lessons learned from a manual debugging session on Ubuntu 24.04.
# This script checks prerequisites, DNS, certificates, service status,
# Nginx configuration content (including map blocks), and network endpoints.
# It will also display the relevant Nginx location block for visual inspection.
#
# Usage:
# 1. Make the script executable: chmod +x diagnostic_script.sh
# 2. Run with sudo: sudo ./diagnostic_script.sh your-domain.duckdns.org
# ===================================================================================

# --- Configuration ---
# The script will use the first argument as the domain name.
# If no argument is provided, it will exit.
DOMAIN=$1
OPENWEBUI_PORT="5000"
NGINXUI_PORT="9000"
OPENWEBUI_LOCAL_URL="http://127.0.0.1:${OPENWEBUI_PORT}"
NGINXUI_LOCAL_URL="http://127.0.0.1:${NGINXUI_PORT}"

# --- Colors for Output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Helper Functions ---
print_header() {
    echo -e "\n${BLUE}=======================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}=======================================================${NC}"
}

print_success() {
    echo -e "[ ${GREEN}SUCCESS${NC} ] $1"
}

print_warning() {
    echo -e "[ ${YELLOW}WARNING${NC} ] $1"
}

print_error() {
    echo -e "[ ${RED}FAILURE${NC} ] $1"
}

print_info() {
    echo -e "[ ${BLUE}INFO${NC}    ] $1"
}

# --- Pre-flight Check ---
if [ -z "$DOMAIN" ]; then
    print_error "No domain name provided."
    echo "Usage: sudo $0 your-domain.duckdns.org"
    exit 1
fi

# Sanitize Domain Input: Remove protocol (http/https) and trailing slashes.
DOMAIN=$(echo "$DOMAIN" | sed -e 's|^[^/]*//||' -e 's|/.*$||')

if [ "$EUID" -ne 0 ]; then
  print_error "This script must be run as root (sudo)."
  exit 1
fi

# ===================================================================================
# 1. PREREQUISITE CHECKS
# ===================================================================================
check_prerequisites() {
    print_header "1. Checking Prerequisites"
    local all_ok=true
    for cmd in nginx docker certbot systemctl ufw curl dig; do
        if command -v $cmd &> /dev/null; then
            print_success "$cmd is installed."
        else
            print_error "$cmd is not installed. Please install it."
            all_ok=false
        fi
    done
    [[ "$all_ok" = true ]] || exit 1
}

# ===================================================================================
# 2. DNS & CERTIFICATE CHECKS
# ===================================================================================
check_dns() {
    print_header "2. Checking DuckDNS Mapping"
    local public_ip=$(curl -s https://api.ipify.org)
    local dns_ip=$(dig +short $DOMAIN @1.1.1.1)

    print_info "Your public IP appears to be: ${public_ip}"
    print_info "Domain ${DOMAIN} resolves to: ${dns_ip}"

    if [ "$public_ip" == "$dns_ip" ]; then
        print_success "DuckDNS IP matches your public IP."
    else
        print_warning "DuckDNS IP (${dns_ip}) does not match your public IP (${public_ip})."
        print_info "This could be due to a recent IP change. Check your DuckDNS updater."
    fi
}

check_certificates() {
    print_header "3. Checking Let's Encrypt Certificate"
    if ! sudo certbot certificates -d "$DOMAIN" 2>/dev/null | grep -q "Domains: ${DOMAIN}"; then
        print_error "No certificate found for ${DOMAIN}. Please run Certbot."
        return 1
    fi

    local cert_info=$(sudo certbot certificates -d "$DOMAIN" 2>/dev/null)
    local expiry_date=$(echo "$cert_info" | grep 'Expiry Date' | sed -n 's/.*Expiry Date: \(.*\) (VALID.*/\1/p')
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local now_epoch=$(date +%s)
    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

    print_info "Certificate for ${DOMAIN} found."
    print_info "Expires on: ${expiry_date} (${days_left} days left)."

    if [ "$days_left" -lt 30 ]; then
        print_warning "Certificate expires in less than 30 days. Consider running 'sudo certbot renew'."
    else
        print_success "Certificate is valid and not expiring soon."
    fi
}

# ===================================================================================
# 3. SERVICE & NGINX CHECKS
# ===================================================================================
check_services() {
    print_header "4. Checking Service Status"
    # Check OpenWebUI (assuming it's running in Docker or as a service)
    if curl -s --head ${OPENWEBUI_LOCAL_URL} | head -n 1 | grep "200 OK" > /dev/null; then
        print_success "OpenWebUI is responding on ${OPENWEBUI_LOCAL_URL}."
    else
        print_error "OpenWebUI is NOT responding on ${OPENWEBUI_LOCAL_URL}."
    fi

    # Check Nginx-UI (assuming native install)
    if systemctl is-active --quiet nginx-ui.service; then
        print_success "nginx-ui.service is active."
        if curl -s --head ${NGINXUI_LOCAL_URL} | head -n 1 | grep "200 OK" > /dev/null; then
            print_success "Nginx-UI is responding on ${NGINXUI_LOCAL_URL}."
        else
            print_warning "nginx-ui.service is running, but UI is not responding on ${NGINXUI_LOCAL_URL}."
        fi
    else
        print_warning "nginx-ui.service is not running. Check with 'systemctl status nginx-ui'."
    fi
}

check_nginx_config() {
    print_header "5. Checking Nginx Configuration"
    # Check syntax first
    if sudo nginx -t &> /tmp/nginx_test.log; then
        print_success "Nginx configuration syntax is OK."
    else
        print_error "Nginx configuration test failed. See details below:"
        cat /tmp/nginx_test.log
        return 1
    fi

    # Check for duplicate server_name entries
    local duplicates=$(grep -r "server_name ${DOMAIN}" /etc/nginx/sites-enabled/ | wc -l)
    if [ "$duplicates" -gt 1 ]; then
        print_warning "Found ${duplicates} 'server_name ${DOMAIN}' entries in sites-enabled. This can cause conflicts."
    else
        print_success "No duplicate server_name entries found for ${DOMAIN}."
    fi

    # Check for WebSocket proxy headers in the config file
    print_info "Checking Nginx config for WebSocket support..."
    local config_file=$(grep -lR "server_name ${DOMAIN}" /etc/nginx/sites-enabled/ | head -n 1)

    if [ -z "$config_file" ]; then
        print_warning "Could not find a specific Nginx config file for ${DOMAIN} in sites-enabled."
        return
    fi

    print_info "Found active config file: ${config_file}"
    local ws_config_ok=true
    
    # Check for the Upgrade header directive
    if ! grep -q "proxy_set_header Upgrade \$http_upgrade;" "$config_file"; then
        print_error "Missing 'proxy_set_header Upgrade \$http_upgrade;' in ${config_file}."
        ws_config_ok=false
    fi

    # Check for the Connection header directive using the recommended map variable
    if ! grep -q "proxy_set_header Connection \$connection_upgrade;" "$config_file"; then
        print_error "Missing 'proxy_set_header Connection \$connection_upgrade;' in ${config_file}."
        ws_config_ok=false
    else
        # If the header is present, now check if the map itself exists
        print_info "Found 'Connection: \$connection_upgrade' header. Verifying map block..."
        if ! grep -qR "map \$http_upgrade \$connection_upgrade" /etc/nginx/; then
            print_error "CRITICAL: The required 'map \$http_upgrade \$connection_upgrade' block is MISSING from your Nginx configuration."
            print_info "Create a file like /etc/nginx/conf.d/websocket_map.conf with the correct map definition."
            ws_config_ok=false
        else
            print_success "Found corresponding 'map \$http_upgrade \$connection_upgrade' block."
        fi
    fi

    if [ "$ws_config_ok" = true ]; then
        print_success "Nginx appears to be correctly configured for WebSockets."
        # NEW: Display the location block for visual confirmation
        print_info "Displaying relevant location block from config for verification:"
        echo -e "${CYAN}"
        # This awk script finds the location block containing the proxy_pass and prints it
        awk '/location/,/}/{ if ($0 ~ /proxy_pass/ && p) { print buf; print $0; while (getline > 0 && $0 !~ /}/) print; print "}"; p=0; buf="" } else if ($0 ~ /location/) { p=1; buf=$0 } else if (p) { buf=buf"\n"$0 } }' "$config_file"
        echo -e "${NC}"
    else
        print_error "WebSocket support is likely misconfigured. Please review the errors above."
    fi
}

# ===================================================================================
# 4. ENDPOINT & FIREWALL CHECKS
# ===================================================================================
check_endpoints() {
    print_header "6. Testing Public Endpoints"
    # Test HTTPS connection and certificate
    print_info "Testing HTTPS endpoint: https://${DOMAIN}/"
    local https_check=$(curl -sLI "https://${DOMAIN}" -o /dev/null -w '%{http_code}')
    if [ "$https_check" == "200" ] || [ "$https_check" == "301" ] || [ "$https_check" == "302" ]; then
        print_success "HTTPS endpoint returned HTTP status ${https_check}."
    else
        print_error "HTTPS endpoint returned HTTP status ${https_check}. Expected 200, 301, or 302."
        print_info "Attempting verbose curl to diagnose..."
        curl -vkI "https://${DOMAIN}"
    fi

    # Test WebSocket upgrade
    print_info "Testing WebSocket endpoint: https://${DOMAIN}/socket.io/"
    local ws_check=$(curl -s -i -N \
        -H "Connection: Upgrade" \
        -H "Upgrade: websocket" \
        -H "Host: ${DOMAIN}" \
        -H "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
        -H "Sec-WebSocket-Version: 13" \
        "https://${DOMAIN}/socket.io/" | head -n 1)

    if [[ "$ws_check" == *"101 Switching Protocols"* ]]; then
        print_success "WebSocket upgrade successful (HTTP 101)."
    else
        print_error "WebSocket upgrade failed. Server responded with:"
        echo "${ws_check}"
    fi
}

check_firewall() {
    print_header "7. Checking UFW Firewall Status"
    if ! ufw status | grep -q "Status: active"; then
        print_warning "UFW is inactive. The server may be unnecessarily exposed."
        return
    fi

    print_success "UFW is active."
    local all_ports_ok=true
    for port in 80 443; do
        if ufw status | grep -qw "${port}/tcp"; then
            print_success "Port ${port}/tcp is allowed in UFW."
        else
            print_error "Port ${port}/tcp is NOT allowed in UFW. Run 'sudo ufw allow ${port}/tcp'."
            all_ports_ok=false
        fi
    done
    [[ "$all_ports_ok" = true ]]
}


# ===================================================================================
# MAIN EXECUTION
# ===================================================================================
main() {
    print_header "Starting OpenWebUI Stack Diagnostic for ${DOMAIN}"
    check_prerequisites
    check_dns
    check_certificates
    check_services
    check_nginx_config
    check_endpoints
    check_firewall
    print_header "Diagnostic Complete"
}

main
