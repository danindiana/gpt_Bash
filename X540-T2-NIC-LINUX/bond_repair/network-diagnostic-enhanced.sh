#!/bin/bash
# Enhanced Comprehensive Network Bond Diagnostic Script
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Quiet mode
QUIET=${QUIET:-0}
log_info() { (( QUIET )) || echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { (( QUIET )) || echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { (( QUIET )) || echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { (( QUIET )) || echo -e "${RED}[ERROR]${NC} $1"; }

# Privileged command runner
run_priv() {
    sudo -n "$@" 2>/dev/null || log_warn "Need sudo for $*"
}

echo -e "${BLUE}=== Enhanced Network Bond Diagnostic ===${NC}"
echo "Timestamp: $(date)"
echo ""

# Check required tools
log_info "0. Checking required tools..."
for cmd in ethtool nmcli netplan ufw ip lsmod systemctl journalctl; do
    command -v "$cmd" >/dev/null || log_warn "$cmd not found in \$PATH"
done
echo ""

# 1. System Information
log_info "1. System Information"
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"
echo "Uptime: $(uptime -p)"
echo ""

# 2. Kernel Module Status
log_info "2. Kernel Module Status"
if lsmod | grep -q bonding; then
    log_success "Bonding module loaded: $(lsmod | grep bonding)"
else
    log_error "Bonding module NOT loaded"
fi

# Check bonding config
if [ -f "/boot/config-$(uname -r)" ]; then
    if grep -q "CONFIG_BONDING=y" "/boot/config-$(uname -r)"; then
        log_success "Bonding compiled into kernel"
    elif grep -q "CONFIG_BONDING=m" "/boot/config-$(uname -r)"; then
        log_info "Bonding available as module"
    else
        log_warn "Bonding config not found in /boot/config-$(uname -r)"
    fi
else
    log_warn "Kernel config not found at /boot/config-$(uname -r)"
fi
echo ""

# 3. Network Manager Services
log_info "3. Network Manager Services"
services=("NetworkManager" "systemd-networkd" "systemd-resolved" "NetworkManager-wait-online")
for service in "${services[@]}"; do
    enabled=$(systemctl is-enabled $service.service 2>/dev/null || echo "unknown")
    active=$(systemctl is-active $service.service 2>/dev/null || echo "unknown")
    echo "$service: Enabled=$enabled, Active=$active"
done
echo ""

# 4. Bond Interface Status
log_info "4. Bond Interface Status"
if [ -d /proc/net/bonding ]; then
    bonds=$(ls /proc/net/bonding/ 2>/dev/null)
    if [ -n "$bonds" ]; then
        for bond in $bonds; do
            echo "Bond: $bond"
            echo "----------------------------------------"
            cat /proc/net/bonding/$bond | grep -E "(MII Status|Speed|Duplex|Link detected|Bonding Mode|Slave Interface)"
            echo ""
        done
    else
        log_warn "No bond interfaces active"
    fi
else
    log_error "No bonding support found in /proc/net/bonding"
fi
echo ""

# 5. Physical Interface Status
log_info "5. Physical Interface Status"
interfaces=$(ip -o link show | awk -F': ' '$2 !~ /^lo|bond[0-9]+\.[0-9]+/ {print $2}')
for intf in $interfaces; do
    state=$(ip link show $intf | grep -o "state [A-Z]\+" | cut -d' ' -f2)
    mac=$(ip link show $intf | grep -o "link/ether [^ ]\+" | cut -d' ' -f2)
    speed=$(run_priv ethtool $intf 2>/dev/null | grep -E "(Speed|Link detected)" || echo "ethtool failed")
    echo "$intf: State=$state, MAC=$mac"
    echo "  $speed" | tr '\n' ' '
    echo -e "\n"
done
echo ""

# 6. Network Connections
log_info "6. Network Manager Connections"
nmcli -t -f NAME,UUID,TYPE,DEVICE,STATE,AUTOCONNECT c s | column -t -s:
echo ""

# 7. Connection Details
log_info "7. Bond Connection Details"
bond_conns=$(nmcli -t -f TYPE,NAME c s | awk -F: '$1=="bond" {print $2}')
if [ -n "$bond_conns" ]; then
    for conn in $bond_conns; do
        echo "--- $conn ---"
        nmcli c s "$conn" | grep -E "(connection\.autoconnect|ipv4\.method|ipv4\.addresses|ipv4\.gateway|ipv4\.dns|ipv4\.route-metric|connection\.autoconnect-priority)"
        echo ""
    done
else
    log_warn "No bond connections found"
fi
echo ""

# 8. IP Configuration
log_info "8. IP Configuration"
ip -4 addr show
echo ""

# 9. Routing Table
log_info "9. Routing Table"
ip route show
echo "Default routes:"
gateway=$(ip route show default | awk '{print $3}' | head -1)
ip route show default
echo ""

# 10. DNS Configuration
log_info "10. DNS Configuration"
cat /etc/resolv.conf
echo "NM DNS: $(nmcli -g IP4.DNS c show bond0 2>/dev/null || echo "N/A")"
echo ""

# 11. ARP Table
log_info "11. ARP Table"
ip neigh show
echo ""

# 12. Firewall Status
log_info "12. Firewall Status"
if command -v ufw >/dev/null; then
    ufw status verbose
else
    echo "UFW not installed"
fi
echo ""

# 13. Netplan Configuration (if exists)
log_info "13. Netplan Configuration"
if [ -d /etc/netplan ] && [ "$(ls -A /etc/netplan/*.yaml 2>/dev/null)" ]; then
    echo "Netplan files found:"
    ls -la /etc/netplan/
    run_priv netplan get all 2>/dev/null || echo "Netplan get failed"
else
    echo "No netplan configuration found"
fi
echo ""

# 14. Connectivity Test
log_info "14. Connectivity Test"
if [ -n "$gateway" ]; then
    echo "Testing connectivity to gateway: $gateway"
    ping -c 2 -W 1 $gateway && log_success "Gateway reachable" || log_error "Gateway unreachable"
else
    log_error "No default gateway found"
fi
echo ""

# 15. Service Dependencies
log_info "15. Service Dependencies"
echo "NetworkManager-wait-online: $(systemctl is-active NetworkManager-wait-online.service)"
echo ""

# 16. Log Analysis
log_info "16. Recent NetworkManager Logs"
journalctl -u NetworkManager --since "5 minutes ago" | grep -i bond | tail -10 || echo "No recent bond logs"
echo ""

# 17. Interface Statistics
log_info "17. Interface Statistics"
ip -s link show bond0 2>/dev/null || echo "No bond0 statistics"
echo ""

# 18. DNS resolution
log_info "18. DNS Resolution Test"
if command -v nslookup >/dev/null; then
    nslookup google.com >/dev/null 2>&1 && log_success "DNS OK" || log_error "DNS failed"
else
    log_warn "nslookup not available"
fi
echo ""

# 19. Bonding driver parameters
log_info "19. Bonding driver parameters"
if [ -d /sys/class/net/bond0/bonding ]; then
    for f in /sys/class/net/bond0/bonding/*; do
        if [[ -r $f ]]; then
            param=$(basename "$f")
            value=$(cat "$f" 2>/dev/null || echo "N/A")
            echo "$param: $value"
        fi
    done
else
    log_warn "No bonding sysfs entries found"
fi
echo ""

# 20. LACP partner state (for 802.3ad)
log_info "20. LACP Partner State"
if [ -f /proc/net/bonding/bond0 ]; then
    awk '/^Aggregator ID/ || /Partner Mac Address/ || /Partner Oper Key/ {print}' /proc/net/bonding/bond0
else
    log_warn "No bond0 found for LACP check"
fi
echo ""

# 21. Interface error counters
log_info "21. Interface Error Counters"
ip -s -s link show | awk '/^[0-9]+:/ {iface=$2} /errors/ {print iface $0}' | head -10
echo ""

echo -e "${GREEN}=== Diagnostic Complete ===${NC}"
