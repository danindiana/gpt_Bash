#!/bin/bash
# Comprehensive Network Bond Repair Script
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

main() {
    check_root
    echo -e "${GREEN}=== Starting Network Bond Repair ===${NC}"
    
    # 1. Load bonding module
    log_info "1. Loading bonding kernel module..."
    if ! lsmod | grep -q bonding; then
        modprobe bonding
        if [ $? -eq 0 ]; then
            log_info "Bonding module loaded successfully"
        else
            log_error "Failed to load bonding module"
            exit 1
        fi
    else
        log_info "Bonding module already loaded"
    fi
    
    # 2. Ensure module loads at boot
    log_info "2. Configuring bonding module to load at boot..."
    if [ ! -f /etc/modules-load.d/bonding.conf ]; then
        echo "bonding" > /etc/modules-load.d/bonding.conf
        log_info "Created /etc/modules-load.d/bonding.conf"
    else
        log_info "Bonding autoload already configured"
    fi
    
    # 3. Enable NetworkManager-wait-online
    log_info "3. Configuring NetworkManager-wait-online service..."
    if ! systemctl is-enabled NetworkManager-wait-online.service >/dev/null 2>&1; then
        systemctl enable NetworkManager-wait-online.service
        log_info "Enabled NetworkManager-wait-online service"
    fi
    if ! systemctl is-active NetworkManager-wait-online.service >/dev/null 2>&1; then
        systemctl start NetworkManager-wait-online.service
        log_info "Started NetworkManager-wait-online service"
    fi
    
    # 4. Configure bond connection properties
    log_info "4. Configuring bond connection properties..."
    bond_conn="bond0"
    if nmcli c show "$bond_conn" >/dev/null 2>&1; then
        # Set manual IP configuration
        nmcli c mod "$bond_conn" ipv4.method manual
        nmcli c mod "$bond_conn" ipv4.addresses "192.168.1.100/24"
        nmcli c mod "$bond_conn" ipv4.gateway "192.168.1.254"
        nmcli c mod "$bond_conn" ipv4.dns "192.168.1.254"
        nmcli c mod "$bond_conn" ipv4.ignore-auto-dns yes
        
        # Set proper metrics and priorities
        nmcli c mod "$bond_conn" ipv4.route-metric 100
        nmcli c mod "$bond_conn" connection.autoconnect yes
        nmcli c mod "$bond_conn" connection.autoconnect-priority 100
        
        log_info "Bond0 configuration updated"
    else
        log_error "Bond0 connection not found"
    fi
    
    # 5. Configure slave connections
    log_info "5. Configuring slave connections..."
    slaves=("bond-slave-enp3s0f0" "bond-slave-enp3s0f1")
    for slave in "${slaves[@]}"; do
        if nmcli c show "$slave" >/dev/null 2>&1; then
            nmcli c mod "$slave" connection.autoconnect yes
            nmcli c mod "$slave" connection.master "bond0"
            nmcli c mod "$slave" connection.slave-type "bond"
            log_info "Slave $slave configured"
        else
            log_warn "Slave connection $slave not found"
        fi
    done
    
    # 6. Configure onboard-eth as backup
    log_info "6. Configuring onboard-eth as backup..."
    onboard_conn="onboard-eth"
    if nmcli c show "$onboard_conn" >/dev/null 2>&1; then
        nmcli c mod "$onboard_conn" connection.autoconnect yes
        nmcli c mod "$onboard_conn" ipv4.route-metric 200
        nmcli c mod "$onboard_conn" connection.autoconnect-priority 50
        log_info "Onboard-eth configured as backup"
    fi
    
    # 7. Bring down all connections and restart
    log_info "7. Restarting network connections..."
    nmcli c down "$bond_conn" 2>/dev/null || true
    for slave in "${slaves[@]}"; do
        nmcli c down "$slave" 2>/dev/null || true
    done
    nmcli c down "$onboard_conn" 2>/dev/null || true
    
    sleep 2
    
    # 8. Bring up connections in proper order
    log_info "8. Bringing up connections..."
    nmcli c up "$bond_conn"
    sleep 1
    for slave in "${slaves[@]}"; do
        nmcli c up "$slave" 2>/dev/null || log_warn "Failed to activate $slave"
    done
    # Don't bring up onboard-eth immediately - let it be backup
    
    # 9. Wait for bond stabilization
    log_info "9. Waiting for bond stabilization..."
    sleep 3
    
    # 10. Verify physical connections
    log_info "10. Verifying physical connections..."
    interfaces=("enp3s0f0" "enp3s0f1")
    for intf in "${interfaces[@]}"; do
        if ip link show "$intf" | grep -q "state UP"; then
            link_status=$(ethtool "$intf" 2>/dev/null | grep "Link detected" || echo "Unknown")
            log_info "$intf: UP, $link_status"
        else
            log_warn "$intf: DOWN - checking physical connection"
            # Try to bring up interface
            ip link set "$intf" up
            sleep 1
            link_status=$(ethtool "$intf" 2>/dev/null | grep "Link detected" || echo "Unknown")
            if [ "$link_status" = "Link detected: yes" ]; then
                log_info "$intf: Now UP after manual intervention"
            else
                log_error "$intf: Physical connection issue - check cable/switch"
            fi
        fi
    done
    
    # 11. Flush routing cache
    log_info "11. Flushing routing cache..."
    ip route flush cache
    
    # 12. Verify final configuration
    log_info "12. Verifying final configuration..."
    echo "--- Bond Status ---"
    if [ -f /proc/net/bonding/bond0 ]; then
        cat /proc/net/bonding/bond0
    else
        log_error "Bond0 not active"
    fi
    
    echo ""
    echo "--- Routing Table ---"
    ip route show
    
    echo ""
    echo "--- Default Route ---"
    ip route show default
    
    echo ""
    echo "--- Active Connections ---"
    nmcli -f NAME,DEVICE,STATE c s
    
    # 13. Test connectivity
    log_info "13. Testing connectivity..."
    gateway=$(ip route show default | awk '{print $3}' | head -1)
    if [ -n "$gateway" ]; then
        if ping -c 2 -W 1 -I bond0 "$gateway" >/dev/null 2>&1; then
            log_info "✓ Connectivity test passed through bond0"
        else
            log_error "✗ Connectivity test failed through bond0"
        fi
    fi
    
    # 14. Create persistence check
    log_info "14. Creating persistence verification..."
    cat > /usr/local/bin/check-bond-status << 'EOF'
#!/bin/bash
echo "=== Bond Status Check ==="
echo "Time: $(date)"
echo "Bond module: $(lsmod | grep bonding || echo 'NOT LOADED')"
echo "Bond interface: $(cat /proc/net/bonding/bond0 2>/dev/null | grep -E '(MII Status|Slave Interface)' || echo 'NOT ACTIVE')"
echo "Default route: $(ip route show default)"
echo "Connectivity: $(ping -c 1 -W 1 192.168.1.254 >/dev/null 2>&1 && echo 'OK' || echo 'FAILED')"
EOF
    chmod +x /usr/local/bin/check-bond-status
    
    echo -e "${GREEN}=== Repair Complete ===${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Reboot to test persistence: sudo reboot"
    echo "2. Check status after reboot: check-bond-status"
    echo "3. Verify physical connections for both network cables"
    echo "4. Check switch configuration for LACP on both ports"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo "  -d, --dry-run  Show what would be done without making changes"
        ;;
    --dry-run|-d)
        echo "Dry run mode - would execute:"
        grep -E "^(log_info|nmcli|modprobe|systemctl|ip)" $0 | head -20
        ;;
    *)
        main
        ;;
esac
