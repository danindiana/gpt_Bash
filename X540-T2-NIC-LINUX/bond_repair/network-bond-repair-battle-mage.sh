#!/bin/bash
# Battle-Ready Network Bond Repair Script
set -e

# Configuration - Environment Variable Overrides
NET=${NET:-192.168.1.0/24}
IP=${IP:-192.168.1.100}
GW=${GW:-192.168.1.254}
DNS=${DNS:-$GW}
BOND_NAME=${BOND_NAME:-bond0}
ONBOARD_CONN=${ONBOARD_CONN:-onboard-eth}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Quiet mode
QUIET=${QUIET:-0}
log_info() { (( QUIET )) || echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { (( QUIET )) || echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { (( QUIET )) || echo -e "${RED}[ERROR]${NC} $1"; }

# Privileged command runner
run_priv() {
    sudo -n "$@" 2>/dev/null || { log_warn "Need sudo for $*"; return 1; }
}

# DNS test function with fallbacks
dns_test() {
    { command -v nslookup >/dev/null && nslookup google.com >/dev/null 2>&1; } ||
    { command -v resolvectl >/dev/null && resolvectl query google.com >/dev/null 2>&1; } ||
    { command -v dig >/dev/null && dig +short google.com >/dev/null 2>&1; } ||
    { log_warn "All DNS test methods failed"; return 1; }
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_tools() {
    local missing=()
    for cmd in nmcli ip modprobe systemctl; do
        command -v "$cmd" >/dev/null || missing+=("$cmd")
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi
}

check_bond_connections() {
    if ! nmcli -t -f TYPE,NAME c s | grep -q "bond"; then
        log_error "No bond connections found in NetworkManager"
        exit 2
    fi
}

check_vlan_dependencies() {
    local bond_dev="$1"
    vlans=$(ip -o link show type vlan 2>/dev/null | awk -F': ' -v b="$bond_dev" '$2 ~ b {print $2}')
    bridges=$(ip -o link show type bridge 2>/dev/null | awk -F': ' -v b="$bond_dev" '$2 ~ b {print $2}')
    
    if [ -n "$vlans" ] || [ -n "$bridges" ]; then
        log_warn "Dependent interfaces detected:"
        [ -n "$vlans" ] && echo "  VLANs: $vlans"
        [ -n "$bridges" ] && echo "  Bridges: $bridges"
        log_warn "These may be affected by bond restart"
    fi
}

main() {
    check_root
    check_tools
    check_bond_connections
    
    echo -e "${GREEN}=== Battle-Ready Network Bond Repair ===${NC}"
    log_info "Configuration: IP=$IP, GW=$GW, DNS=$DNS, Bond=$BOND_NAME"
    echo ""
    
    # Check for dependent interfaces
    check_vlan_dependencies "$BOND_NAME"
    
    # 1. Load bonding module
    log_info "1. Loading bonding kernel module..."
    if ! lsmod | grep -q bonding; then
        if run_priv modprobe bonding; then
            log_info "Bonding module loaded successfully"
        else
            log_error "Failed to load bonding module"
            exit 1
        fi
    else
        log_info "Bonding module already loaded"
    fi
    
    # 2. Ensure module loads at boot (idempotent)
    log_info "2. Configuring bonding module to load at boot..."
    run_priv bash -c 'grep -qxF bonding /etc/modules-load.d/bonding.conf 2>/dev/null || echo bonding >> /etc/modules-load.d/bonding.conf'
    log_info "Bonding autoload configured"
    
    # 3. Enable NetworkManager-wait-online
    log_info "3. Configuring NetworkManager-wait-online service..."
    if ! systemctl is-enabled NetworkManager-wait-online.service >/dev/null 2>&1; then
        run_priv systemctl enable NetworkManager-wait-online.service
        log_info "Enabled NetworkManager-wait-online service"
    fi
    if ! systemctl is-active NetworkManager-wait-online.service >/dev/null 2>&1; then
        run_priv systemctl start NetworkManager-wait-online.service
        log_info "Started NetworkManager-wait-online service"
    fi
    
    # 4. Configure bond connection properties
    log_info "4. Configuring bond connection properties..."
    if nmcli c show "$BOND_NAME" >/dev/null 2>&1; then
        # Set manual IP configuration using parameterized values
        nmcli c mod "$BOND_NAME" ipv4.method manual
        nmcli c mod "$BOND_NAME" ipv4.addresses "$IP/24"
        nmcli c mod "$BOND_NAME" ipv4.gateway "$GW"
        nmcli c mod "$BOND_NAME" ipv4.dns "$DNS"
        nmcli c mod "$BOND_NAME" ipv4.ignore-auto-dns yes
        
        # Set proper metrics and priorities
        nmcli c mod "$BOND_NAME" ipv4.route-metric 100
        nmcli c mod "$BOND_NAME" connection.autoconnect yes
        nmcli c mod "$BOND_NAME" connection.autoconnect-priority 100
        
        log_info "Bond configuration updated"
    else
        log_error "Bond connection '$BOND_NAME' not found"
        return 1
    fi
    
    # 5. Configure slave connections (safe array handling)
    log_info "5. Configuring slave connections..."
    slaves=()
    while IFS= read -r -d '' slave; do
        slaves+=("$slave")
    done < <(nmcli -t -f TYPE,NAME c s 2>/dev/null | \
             awk -F: '$1=="802-3-ethernet" && $2~/(slave|bond-slave)/ {print $2}' | \
             tr '\n' '\0')
    
    if [ ${#slaves[@]} -eq 0 ]; then
        log_warn "No slave connections found automatically, trying default patterns..."
        # Try to discover slave interfaces by pattern
        while IFS= read -r -d '' slave; do
            slaves+=("$slave")
        done < <(nmcli -t -f NAME c s 2>/dev/null | grep -E "(slave|bond)" | tr '\n' '\0')
    fi
    
    if [ ${#slaves[@]} -eq 0 ]; then
        log_warn "No slave connections found, bond may not function properly"
    else
        for slave in "${slaves[@]}"; do
            if nmcli c show "$slave" >/dev/null 2>&1; then
                nmcli c mod "$slave" connection.autoconnect yes
                nmcli c mod "$slave" connection.master "$BOND_NAME"
                nmcli c mod "$slave" connection.slave-type "bond"
                log_info "Slave '$slave' configured"
            else
                log_warn "Slave connection '$slave' not found"
            fi
        done
    fi
    
    # 6. Configure onboard-eth as backup
    log_info "6. Configuring $ONBOARD_CONN as backup..."
    if nmcli c show "$ONBOARD_CONN" >/dev/null 2>&1; then
        nmcli c mod "$ONBOARD_CONN" connection.autoconnect yes
        nmcli c mod "$ONBOARD_CONN" ipv4.route-metric 200
        nmcli c mod "$ONBOARD_CONN" connection.autoconnect-priority 50
        log_info "$ONBOARD_CONN configured as backup"
    else
        log_warn "Onboard connection '$ONBOARD_CONN' not found"
    fi
    
    # 7. Bring down all connections and restart
    log_info "7. Restarting network connections..."
    nmcli c down "$BOND_NAME" 2>/dev/null || true
    for slave in "${slaves[@]}"; do
        nmcli c down "$slave" 2>/dev/null || true
    done
    nmcli c down "$ONBOARD_CONN" 2>/dev/null || true
    
    sleep 2
    
    # 8. Bring up connections in proper order
    log_info "8. Bringing up connections..."
    if ! nmcli c up "$BOND_NAME"; then
        log_error "Failed to activate bond $BOND_NAME"
        return 1
    fi
    sleep 3  # Give bond time to initialize
    
    for slave in "${slaves[@]}"; do
        if nmcli c up "$slave" 2>/dev/null; then
            log_info "Slave '$slave' activated"
        else
            log_warn "Failed to activate '$slave' - may need physical connection check"
        fi
    done
    
    # 9. Verify physical connections
    log_info "9. Verifying physical connections..."
    interfaces=()
    while IFS= read -r -d '' iface; do
        interfaces+=("$iface")
    done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E "^(en|eth)" | tr '\n' '\0')
    
    for intf in "${interfaces[@]}"; do
        if ip link show "$intf" | grep -q "state UP"; then
            link_status=$(run_priv ethtool "$intf" 2>/dev/null | grep "Link detected" || echo "Unknown")
            log_info "$intf: UP, $link_status"
        else
            log_warn "$intf: DOWN - checking physical connection"
            run_priv ip link set "$intf" up
            sleep 1
            link_status=$(run_priv ethtool "$intf" 2>/dev/null | grep "Link detected" || echo "Unknown")
            if [[ "$link_status" == *"yes"* ]]; then
                log_info "$intf: Now UP after manual intervention"
            else
                log_error "$intf: Physical connection issue - check cable/switch"
            fi
        fi
    done
    
    # 10. Flush routing cache
    log_info "10. Flushing routing cache..."
    run_priv ip route flush cache
    
    # 11. Verify final configuration
    log_info "11. Verifying final configuration..."
    echo "--- Bond Status ---"
    if [ -f "/proc/net/bonding/$BOND_NAME" ]; then
        cat "/proc/net/bonding/$BOND_NAME"
    else
        log_error "Bond $BOND_NAME not active"
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
    
    # 12. Test connectivity
    log_info "12. Testing connectivity..."
    gateway=$(ip route show default | awk '{print $3}' | head -1)
    if [ -n "$gateway" ]; then
        if ping -c 2 -W 1 -I "$BOND_NAME" "$gateway" >/dev/null 2>&1; then
            log_info "✓ Connectivity test passed through $BOND_NAME"
        else
            log_error "✗ Connectivity test failed through $BOND_NAME"
        fi
    fi
    
    # 13. Test DNS
    log_info "13. Testing DNS resolution..."
    if dns_test; then
        log_info "✓ DNS resolution working"
    else
        log_error "✗ DNS resolution failed"
    fi
    
    # 14. Create persistence check script
    log_info "14. Creating persistence verification..."
    run_priv install -m 0755 /dev/stdin /usr/local/bin/check-bond-status <<EOF
#!/usr/bin/env bash
echo "=== Bond Status Check ==="
echo "Time: \$(date)"
echo "Bond module: \$(lsmod | grep bonding || echo 'NOT LOADED')"
echo "Bond interface: \$(cat /proc/net/bonding/$BOND_NAME 2>/dev/null | grep -E '(MII Status|Slave Interface)' || echo 'NOT ACTIVE')"
echo "Default route: \$(ip route show default)"
ping -c 1 -W 1 "$GW" >/dev/null 2>&1 && echo "Connectivity: OK" || echo "Connectivity: FAILED"
EOF
    
    log_info "Persistence check script installed"
    
    echo -e "${GREEN}=== Repair Complete ===${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Reboot to test persistence: sudo reboot"
    echo "2. Check status after reboot: check-bond-status"
    echo "3. Verify physical connections for both network cables"
    echo "4. Check switch configuration for LACP on both ports"
    echo ""
    echo "Environment variables for customization:"
    echo "  NET=$NET, IP=$IP, GW=$GW, DNS=$DNS"
    echo "  BOND_NAME=$BOND_NAME, ONBOARD_CONN=$ONBOARD_CONN"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo "  -d, --dry-run  Show what would be done without making changes"
        echo "  -q, --quiet    Quiet mode (minimal output)"
        echo ""
        echo "Environment variables:"
        echo "  NET=192.168.1.0/24    Network subnet"
        echo "  IP=192.168.1.100      Bond IP address"
        echo "  GW=192.168.1.254      Gateway address"
        echo "  DNS=192.168.1.254     DNS server"
        echo "  BOND_NAME=bond0       Bond interface name"
        echo "  ONBOARD_CONN=onboard-eth  Onboard connection name"
        ;;
    --dry-run|-d)
        echo "Dry run mode - would execute the following steps:"
        grep -E "^(log_info|nmcli|modprobe|systemctl|ip)" $0 | grep -v "grep" | head -10
        echo "... and many more configuration steps"
        exit 0
        ;;
    --quiet|-q)
        QUIET=1
        main
        ;;
    *)
        main
        ;;
esac
