#!/bin/bash
# Bond Restore Script - Fixes bonding interface activation issues
# Created for bond0 with slaves enp3s0f0 and enp3s0f1

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

load_bonding_module() {
    log_info "Checking if bonding module is loaded..."
    if ! lsmod | grep -q bonding; then
        log_info "Loading bonding kernel module..."
        modprobe bonding
        if [ $? -eq 0 ]; then
            log_info "Bonding module loaded successfully"
        else
            log_error "Failed to load bonding module"
            return 1
        fi
    else
        log_info "Bonding module is already loaded"
    fi
    
    # Ensure bonding module loads at boot
    if [ ! -f /etc/modules-load.d/bonding.conf ]; then
        log_info "Creating bonding module autoload configuration..."
        echo "bonding" > /etc/modules-load.d/bonding.conf
        log_info "Bonding module will now load automatically at boot"
    fi
}

ensure_autoconnect() {
    log_info "Ensuring bond connections have autoconnect enabled..."
    
    # List of bond connections to check
    local bond_connections=("bond0" "bond-slave-enp3s0f0" "bond-slave-enp3s0f1")
    
    for conn in "${bond_connections[@]}"; do
        if nmcli c show "$conn" 2>/dev/null | grep -q "connection.autoconnect:.*yes"; then
            log_info "Connection $conn already has autoconnect enabled"
        else
            log_info "Enabling autoconnect for $conn..."
            nmcli c mod "$conn" connection.autoconnect yes
        fi
    done
}

check_network_manager_wait() {
    log_info "Checking NetworkManager-wait-online service..."
    
    if systemctl is-enabled NetworkManager-wait-online.service >/dev/null 2>&1; then
        log_info "NetworkManager-wait-online service is enabled"
    else
        log_info "Enabling NetworkManager-wait-online service..."
        systemctl enable NetworkManager-wait-online.service
    fi
    
    if systemctl is-active NetworkManager-wait-online.service >/dev/null 2>&1; then
        log_info "NetworkManager-wait-online service is active"
    else
        log_info "Starting NetworkManager-wait-online service..."
        systemctl start NetworkManager-wait-online.service
    fi
}

verify_slave_dependencies() {
    log_info "Verifying bond slave dependencies..."
    
    # Check if slaves are properly linked to bond master
    if nmcli c show bond-slave-enp3s0f0 | grep -q "connection.master:.*bond0"; then
        log_info "enp3s0f0 is properly linked to bond0"
    else
        log_warn "enp3s0f0 not properly linked to bond0, fixing..."
        nmcli c mod bond-slave-enp3s0f0 connection.master bond0 connection.slave-type bond
    fi
    
    if nmcli c show bond-slave-enp3s0f1 | grep -q "connection.master:.*bond0"; then
        log_info "enp3s0f1 is properly linked to bond0"
    else
        log_warn "enp3s0f1 not properly linked to bond0, fixing..."
        nmcli c mod bond-slave-enp3s0f1 connection.master bond0 connection.slave-type bond
    fi
}

activate_bond() {
    log_info "Activating bond interface and slaves..."
    
    # Try to activate bond first
    if nmcli c up bond0; then
        log_info "Bond0 activated successfully"
    else
        log_error "Failed to activate bond0, trying alternative approach..."
        
        # Check if there's a conflicting bond interface
        if ip link show bond0 2>/dev/null; then
            log_info "Removing existing bond0 interface..."
            ip link delete bond0
            sleep 2
            nmcli c up bond0
        fi
    fi
    
    # Activate slaves
    log_info "Activating slave interfaces..."
    nmcli c up bond-slave-enp3s0f0
    nmcli c up bond-slave-enp3s0f1
    
    # Wait a moment for bond to stabilize
    sleep 3
}

verify_bond_status() {
    log_info "Verifying bond status..."
    
    if [ -f /proc/net/bonding/bond0 ]; then
        log_info "Bond0 is active:"
        echo "=========================================="
        cat /proc/net/bonding/bond0
        echo "=========================================="
        
        # Check if both slaves are active
        if grep -q "MII Status: up" /proc/net/bonding/bond0; then
            log_info "✓ Bond is functioning correctly with active slaves"
        else
            log_warn "Bond is active but some slaves may be down"
        fi
    else
        log_error "Bond0 is not active or not functioning properly"
        return 1
    fi
}

check_network_conflicts() {
    log_info "Checking for network configuration conflicts..."
    
    # Check if netplan might be interfering
    if [ -d /etc/netplan ] && [ "$(ls -A /etc/netplan/*.yaml 2>/dev/null)" ]; then
        log_warn "Netplan configuration files detected. Ensure they don't conflict with NetworkManager:"
        ls -la /etc/netplan/*.yaml 2>/dev/null || true
    fi
}

main() {
    log_info "Starting bond restoration procedure..."
    check_root
    
    log_info "=== Step 1: Load bonding kernel module ==="
    load_bonding_module
    
    log_info "=== Step 2: Check NetworkManager wait service ==="
    check_network_manager_wait
    
    log_info "=== Step 3: Ensure autoconnect is enabled ==="
    ensure_autoconnect
    
    log_info "=== Step 4: Verify slave dependencies ==="
    verify_slave_dependencies
    
    log_info "=== Step 5: Check for configuration conflicts ==="
    check_network_conflicts
    
    log_info "=== Step 6: Activate bond interface ==="
    activate_bond
    
    log_info "=== Step 7: Verify bond status ==="
    if verify_bond_status; then
        log_info "✓ Bond restoration completed successfully!"
        log_info "Current bond connections:"
        nmcli c show | grep -E "(bond|enp3s0f)"
    else
        log_error "Bond restoration encountered issues"
        log_info "Checking NetworkManager logs for details..."
        journalctl -u NetworkManager --since "5 minutes ago" | grep -i bond
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo "  -s, --status   Show current bond status only"
        echo "  -r, --restart  Restart NetworkManager and reactivate bond"
        ;;
    --status|-s)
        verify_bond_status
        exit 0
        ;;
    --restart|-r)
        check_root
        log_info "Restarting NetworkManager and reactivating bond..."
        systemctl restart NetworkManager
        sleep 5
        activate_bond
        verify_bond_status
        exit 0
        ;;
    *)
        main
        ;;
esac
