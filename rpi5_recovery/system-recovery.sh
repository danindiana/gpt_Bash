#!/bin/bash

# System Recovery Script for Raspberry Pi
# Fixes common issues: read-only filesystem, failed services, etc.

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Fix filesystem read-only issues
fix_filesystem() {
    log "Checking filesystem status..."
    
    # Check if root filesystem is read-only
    if mount | grep -q "on / .*ro,"; then
        warning "Root filesystem is read-only. Attempting to remount as read-write..."
        mount -o remount,rw / || {
            error "Failed to remount root filesystem as read-write"
            log "Attempting filesystem check..."
            fsck -y /dev/mmcblk0p2 || true
            mount -o remount,rw /
        }
    fi
    
    # Test write capability
    if echo "test" > /tmp/write_test 2>/dev/null; then
        rm -f /tmp/write_test
        success "Filesystem is writable"
    else
        error "Filesystem is still not writable"
        return 1
    fi
    
    # Check disk space
    log "Checking disk space..."
    df -h | grep -E "/$|boot"
}

# Fix swap issues
fix_swap() {
    log "Fixing swap configuration..."
    
    # Check if swap file exists and is correct
    if [[ -f /var/swap ]]; then
        # Fix swap file permissions
        chmod 600 /var/swap
        
        # Try to enable swap
        if ! swapon /var/swap 2>/dev/null; then
            warning "Recreating swap file..."
            swapoff /var/swap 2>/dev/null || true
            rm -f /var/swap
            fallocate -l 512M /var/swap
            chmod 600 /var/swap
            mkswap /var/swap
            swapon /var/swap
        fi
    fi
    
    # Restart swap service
    systemctl restart dphys-swapfile || warning "Could not restart swap service"
}

# Fix Docker and containerd
fix_docker() {
    log "Fixing Docker services..."
    
    # Stop services
    systemctl stop docker containerd 2>/dev/null || true
    
    # Clean up problematic files
    rm -rf /var/lib/docker/tmp/* 2>/dev/null || true
    rm -rf /run/containerd/* 2>/dev/null || true
    rm -rf /run/docker/* 2>/dev/null || true
    
    # Start containerd first
    systemctl start containerd
    sleep 3
    
    # Then start Docker
    if systemctl start docker; then
        success "Docker services started successfully"
    else
        warning "Docker failed to start - this may be normal if not needed"
        # Disable Docker if it keeps failing
        systemctl disable docker containerd 2>/dev/null || true
    fi
}

# Fix database services
fix_database() {
    log "Fixing database services..."
    
    # Check MariaDB/MySQL
    if systemctl is-enabled mariadb >/dev/null 2>&1; then
        log "Starting MariaDB..."
        if systemctl start mariadb; then
            success "MariaDB started successfully"
        else
            warning "MariaDB failed to start, checking logs..."
            journalctl -u mariadb -n 10 --no-pager
            
            # Try to fix common MariaDB issues
            chown -R mysql:mysql /var/lib/mysql/ 2>/dev/null || true
            systemctl start mariadb || warning "MariaDB still failing"
        fi
    fi
}

# Fix web services
fix_web_services() {
    log "Fixing web services..."
    
    # Fix PHP-FPM
    if systemctl is-enabled php8.4-fpm >/dev/null 2>&1; then
        systemctl start php8.4-fpm || warning "PHP-FPM failed to start"
    fi
    
    # Fix Nginx
    if systemctl is-enabled nginx >/dev/null 2>&1; then
        # Test nginx configuration
        if nginx -t; then
            systemctl start nginx || warning "Nginx failed to start"
        else
            error "Nginx configuration is invalid"
        fi
    fi
}

# Fix system services
fix_system_services() {
    log "Fixing system services..."
    
    # List of services to attempt to restart
    local services=(
        "systemd-hostnamed"
        "accounts-daemon"
        "vnstat"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            log "Restarting $service..."
            systemctl restart "$service" || warning "$service failed to restart"
        fi
    done
}

# Disable problematic services
disable_problematic_services() {
    log "Disabling known problematic services..."
    
    # Services that often fail and aren't critical
    local services_to_disable=(
        "rp1-test.service"
        "nvmf-autoconnect.service"
    )
    
    for service in "${services_to_disable[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            log "Disabling $service (not critical)..."
            systemctl disable "$service" || true
        fi
    done
}

# Fix snap services
fix_snap_services() {
    log "Fixing snap services..."
    
    # Restart snapd if it's enabled
    if systemctl is-enabled snapd >/dev/null 2>&1; then
        systemctl restart snapd || {
            warning "Snapd failed to restart"
            # Try to fix snap issues
            snap refresh 2>/dev/null || true
        }
    fi
}

# Set proper permissions
fix_permissions() {
    log "Fixing critical file permissions..."
    
    # Web directories
    if [[ -d /var/www ]]; then
        chown -R www-data:www-data /var/www/
        find /var/www -type d -exec chmod 755 {} \;
        find /var/www -type f -exec chmod 644 {} \;
    fi
    
    # Log directories
    chmod 755 /var/log
    
    # Tmp directories
    chmod 1777 /tmp /var/tmp
}

# System health check
system_health_check() {
    log "Performing system health check..."
    
    echo "=== FILESYSTEM STATUS ==="
    df -h
    echo
    
    echo "=== MEMORY USAGE ==="
    free -h
    echo
    
    echo "=== SWAP STATUS ==="
    swapon --show
    echo
    
    echo "=== FAILED SERVICES ==="
    systemctl --failed --no-pager
    echo
    
    echo "=== DISK I/O ERRORS ==="
    dmesg | grep -i "i/o error\|readonly" | tail -5
    echo
    
    echo "=== TEMPERATURE ==="
    if command -v vcgencmd >/dev/null; then
        vcgencmd measure_temp
    fi
}

# Main recovery function
main() {
    log "Starting system recovery..."
    
    check_root
    
    log "=== PHASE 1: Filesystem Recovery ==="
    fix_filesystem
    
    log "=== PHASE 2: Swap Recovery ==="
    fix_swap
    
    log "=== PHASE 3: Permission Fixes ==="
    fix_permissions
    
    log "=== PHASE 4: Critical Services ==="
    fix_database
    fix_web_services
    
    log "=== PHASE 5: System Services ==="
    fix_system_services
    
    log "=== PHASE 6: Docker Services ==="
    fix_docker
    
    log "=== PHASE 7: Snap Services ==="
    fix_snap_services
    
    log "=== PHASE 8: Cleanup ==="
    disable_problematic_services
    
    log "=== PHASE 9: Health Check ==="
    system_health_check
    
    success "System recovery completed!"
    log "Please review the output above for any remaining issues."
    log "You may want to reboot the system: sudo reboot"
}

# Handle script arguments
case "${1:-}" in
    --filesystem-only)
        check_root
        fix_filesystem
        ;;
    --services-only)
        check_root
        fix_database
        fix_web_services
        fix_system_services
        ;;
    --health-check)
        system_health_check
        ;;
    --help|-h)
        echo "Usage: $0 [OPTION]"
        echo "System recovery script for Raspberry Pi"
        echo ""
        echo "Options:"
        echo "  (no args)         Run full recovery"
        echo "  --filesystem-only Fix only filesystem issues"
        echo "  --services-only   Fix only services"
        echo "  --health-check    Show system status only"
        echo "  --help           Show this help"
        ;;
    *)
        main
        ;;
esac
