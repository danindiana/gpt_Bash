#!/bin/bash

# phpBB Troubleshooting Script
# Diagnoses common phpBB installation issues
# Version 1.0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PHPBB_DIR="/var/www/html/forum"
NGINX_CONF="/etc/nginx/sites-available/phpbb"
PHP_VERSION="8.4"

log() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

success() {
    echo -e "${GREEN}✓ PASS${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠ WARN${NC} $1"
}

error() {
    echo -e "${RED}✗ FAIL${NC} $1"
}

check_services() {
    log "Checking system services..."
    
    # Check Nginx
    if systemctl is-active --quiet nginx; then
        success "Nginx is running"
    else
        error "Nginx is not running"
        echo "  Fix: sudo systemctl start nginx"
    fi
    
    # Check PHP-FPM
    if systemctl is-active --quiet php${PHP_VERSION}-fpm; then
        success "PHP-FPM is running"
    else
        error "PHP-FPM is not running"
        echo "  Fix: sudo systemctl start php${PHP_VERSION}-fpm"
    fi
    
    # Check MariaDB
    if systemctl is-active --quiet mariadb; then
        success "MariaDB is running"
    else
        error "MariaDB is not running"
        echo "  Fix: sudo systemctl start mariadb"
    fi
}

check_nginx_config() {
    log "Checking Nginx configuration..."
    
    # Test nginx config syntax
    if nginx -t &>/dev/null; then
        success "Nginx configuration syntax is valid"
    else
        error "Nginx configuration has syntax errors"
        echo "  Details:"
        nginx -t
        return
    fi
    
    # Check if phpBB site is enabled
    if [[ -f "/etc/nginx/sites-enabled/phpbb" ]]; then
        success "phpBB site is enabled"
    else
        warning "phpBB site is not enabled"
        echo "  Fix: sudo ln -sf /etc/nginx/sites-available/phpbb /etc/nginx/sites-enabled/"
    fi
    
    # Check for conflicting sites
    enabled_sites=$(ls -1 /etc/nginx/sites-enabled/ 2>/dev/null | wc -l)
    if [[ $enabled_sites -gt 1 ]]; then
        warning "Multiple sites enabled (may cause conflicts)"
        echo "  Enabled sites:"
        ls -la /etc/nginx/sites-enabled/
    fi
    
    # Check document root
    if [[ -f "$NGINX_CONF" ]]; then
        doc_root=$(grep -E "^\s*root" "$NGINX_CONF" | awk '{print $2}' | tr -d ';')
        if [[ "$doc_root" == "$PHPBB_DIR" ]]; then
            success "Document root correctly set to $PHPBB_DIR"
        else
            warning "Document root mismatch: $doc_root vs $PHPBB_DIR"
        fi
    fi
}

check_php_config() {
    log "Checking PHP configuration..."
    
    # Check PHP-FPM socket
    socket_path="/run/php/php${PHP_VERSION}-fpm.sock"
    if [[ -S "$socket_path" ]]; then
        success "PHP-FPM socket exists: $socket_path"
    else
        error "PHP-FPM socket not found: $socket_path"
        echo "  Check: sudo systemctl status php${PHP_VERSION}-fpm"
    fi
    
    # Check PHP-FPM pool config
    pool_conf="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
    if [[ -f "$pool_conf" ]]; then
        listen_setting=$(grep -E "^listen\s*=" "$pool_conf" | head -1)
        if echo "$listen_setting" | grep -q "$socket_path"; then
            success "PHP-FPM listen setting correct"
        else
            warning "PHP-FPM listen setting: $listen_setting"
        fi
        
        user_setting=$(grep -E "^user\s*=" "$pool_conf" | head -1)
        if echo "$user_setting" | grep -q "www-data"; then
            success "PHP-FPM user setting correct"
        else
            warning "PHP-FPM user setting: $user_setting"
        fi
    fi
}

check_file_permissions() {
    log "Checking file permissions..."
    
    if [[ ! -d "$PHPBB_DIR" ]]; then
        error "phpBB directory not found: $PHPBB_DIR"
        return
    fi
    
    # Check ownership
    owner=$(stat -c "%U:%G" "$PHPBB_DIR")
    if [[ "$owner" == "www-data:www-data" ]]; then
        success "phpBB directory ownership correct"
    else
        warning "phpBB directory ownership: $owner (should be www-data:www-data)"
        echo "  Fix: sudo chown -R www-data:www-data $PHPBB_DIR"
    fi
    
    # Check writable directories
    writable_dirs=("cache" "store" "files" "images/avatars/upload")
    for dir in "${writable_dirs[@]}"; do
        if [[ -d "$PHPBB_DIR/$dir" ]]; then
            perms=$(stat -c "%a" "$PHPBB_DIR/$dir")
            if [[ "$perms" == "777" || "$perms" == "775" ]]; then
                success "$dir directory is writable"
            else
                warning "$dir directory permissions: $perms (should be 777 or 775)"
                echo "  Fix: sudo chmod 777 $PHPBB_DIR/$dir"
            fi
        else
            error "$dir directory not found"
        fi
    done
}

check_database() {
    log "Checking database connectivity..."
    
    # Try to connect to database
    if mysql -u phpbb_user -psimple123 phpbb_forum -e "SELECT 1;" &>/dev/null; then
        success "Database connection successful"
    else
        error "Cannot connect to database"
        echo "  Check database credentials and ensure MariaDB is running"
        echo "  Try: mysql -u phpbb_user -psimple123 phpbb_forum"
    fi
}

check_web_access() {
    log "Testing web access..."
    
    # Create test PHP file
    test_file="$PHPBB_DIR/health_check.php"
    echo "<?php echo 'OK'; ?>" > "$test_file"
    chown www-data:www-data "$test_file" 2>/dev/null
    
    # Test HTTP access
    if curl -f -s "http://localhost/health_check.php" | grep -q "OK"; then
        success "Web server serving PHP correctly"
    else
        error "Web server not serving PHP correctly"
        echo "  Check nginx error log: sudo tail /var/log/nginx/error.log"
    fi
    
    # Test phpBB files
    if [[ -f "$PHPBB_DIR/app.php" ]]; then
        if curl -f -s "http://localhost/app.php" &>/dev/null; then
            success "phpBB main application accessible"
        else
            warning "phpBB application may have issues"
        fi
    fi
    
    # Test installer
    if [[ -f "$PHPBB_DIR/install/index.html" ]]; then
        if curl -f -s "http://localhost/install/index.html" &>/dev/null; then
            success "phpBB installer accessible"
        else
            warning "phpBB installer may have issues"
        fi
    fi
    
    # Clean up
    rm -f "$test_file"
}

check_logs() {
    log "Checking recent error logs..."
    
    # Nginx error log
    if [[ -f "/var/log/nginx/error.log" ]]; then
        recent_errors=$(tail -20 /var/log/nginx/error.log | grep -c "$(date +%Y/%m/%d)" || true)
        if [[ $recent_errors -gt 0 ]]; then
            warning "$recent_errors recent nginx errors found"
            echo "  Recent errors:"
            tail -5 /var/log/nginx/error.log | sed 's/^/    /'
        else
            success "No recent nginx errors"
        fi
    fi
    
    # PHP-FPM error log
    php_log="/var/log/php${PHP_VERSION}-fpm.log"
    if [[ -f "$php_log" ]]; then
        recent_php_errors=$(tail -20 "$php_log" | grep -c "$(date +%d-%b-%Y)" || true)
        if [[ $recent_php_errors -gt 0 ]]; then
            warning "$recent_php_errors recent PHP-FPM errors found"
        else
            success "No recent PHP-FPM errors"
        fi
    fi
}

show_config_summary() {
    log "Configuration summary..."
    
    echo ""
    echo "=== CURRENT CONFIGURATION ==="
    echo "phpBB Directory: $PHPBB_DIR"
    echo "Nginx Config: $NGINX_CONF"
    echo "PHP Version: $PHP_VERSION"
    echo ""
    
    if [[ -f "$NGINX_CONF" ]]; then
        echo "=== NGINX CONFIG SNIPPET ==="
        echo "Document Root: $(grep -E "^\s*root" "$NGINX_CONF" | awk '{print $2}' | tr -d ';')"
        echo "Listen: $(grep -E "^\s*listen" "$NGINX_CONF" | head -1 | awk '{print $2}' | tr -d ';')"
        echo ""
    fi
    
    echo "=== QUICK FIXES ==="
    echo "Restart services: sudo systemctl restart nginx php${PHP_VERSION}-fpm"
    echo "Check nginx config: sudo nginx -t"
    echo "View error logs: sudo tail -f /var/log/nginx/error.log"
    echo "Fix permissions: sudo chown -R www-data:www-data $PHPBB_DIR"
    echo ""
}

run_all_checks() {
    echo "phpBB Troubleshooting Report"
    echo "Generated: $(date)"
    echo "================================"
    echo ""
    
    check_services
    echo ""
    check_nginx_config
    echo ""
    check_php_config
    echo ""
    check_file_permissions
    echo ""
    check_database
    echo ""
    check_web_access
    echo ""
    check_logs
    echo ""
    show_config_summary
}

# Parse command line arguments
case "${1:-}" in
    --services)
        check_services
        ;;
    --nginx)
        check_nginx_config
        ;;
    --php)
        check_php_config
        ;;
    --permissions)
        check_file_permissions
        ;;
    --database)
        check_database
        ;;
    --web)
        check_web_access
        ;;
    --logs)
        check_logs
        ;;
    --help)
        echo "Usage: $0 [option]"
        echo "Options:"
        echo "  --services      Check system services"
        echo "  --nginx         Check nginx configuration"
        echo "  --php           Check PHP configuration"
        echo "  --permissions   Check file permissions"
        echo "  --database      Check database connectivity"
        echo "  --web           Test web access"
        echo "  --logs          Check error logs"
        echo "  (no option)     Run all checks"
        echo "  --help          Show this help"
        ;;
    *)
        run_all_checks
        ;;
esac
