#!/bin/bash
# Comprehensive Network Bond Diagnostic Script
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${BLUE}=== Comprehensive Network Bond Diagnostic ===${NC}"
echo "Timestamp: $(date)"
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
echo "Bonding config: $(grep BONDING /boot/config-$(uname -r) 2>/dev/null || echo "Not found")"
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
    bonds=$(ls /proc/net/bonding/)
    for bond in $bonds; do
        echo "Bond: $bond"
        echo "----------------------------------------"
        cat /proc/net/bonding/$bond | grep -E "(MII Status|Speed|Duplex|Link detected|Bonding Mode|Slave Interface)"
        echo ""
    done
else
    log_error "No bonding interfaces found in /proc/net/bonding"
fi
echo ""

# 5. Physical Interface Status
log_info "5. Physical Interface Status"
interfaces=$(ip link show | grep -E "^[0-9]+:" | awk -F: '{print $2}' | tr -d ' ')
for intf in $interfaces; do
    if [[ $intf != "lo" ]]; then
        state=$(ip link show $intf | grep -o "state [A-Z]\+" | cut -d' ' -f2)
        mac=$(ip link show $intf | grep -o "link/ether [^ ]\+" | cut -d' ' -f2)
        speed=$(ethtool $intf 2>/dev/null | grep -E "(Speed|Link detected)" || echo "ethtool failed")
        echo "$intf: State=$state, MAC=$mac"
        echo "  $speed" | tr '\n' ' '
        echo -e "\n"
    fi
done
echo ""

# 6. Network Connections
log_info "6. Network Manager Connections"
nmcli -f NAME,UUID,TYPE,DEVICE,STATE,AUTOCONNECT c s
echo ""

# 7. Connection Details
log_info "7. Bond Connection Details"
bond_conns=$(nmcli c s | grep bond | awk '{print $1}')
for conn in $bond_conns; do
    echo "--- $conn ---"
    nmcli c s "$conn" | grep -E "(connection\.autoconnect|ipv4\.method|ipv4\.addresses|ipv4\.gateway|ipv4\.dns|ipv4\.route-metric|connection\.autoconnect-priority)"
    echo ""
done
echo ""

# 8. IP Configuration
log_info "8. IP Configuration"
ip -4 addr show
echo ""

# 9. Routing Table
log_info "9. Routing Table"
ip route show
echo "Default routes:"
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
    sudo netplan get all 2>/dev/null || echo "Netplan get failed"
else
    echo "No netplan configuration found"
fi
echo ""

# 14. Connectivity Test
log_info "14. Connectivity Test"
gateway=$(ip route show default | awk '{print $3}' | head -1)
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

log_info "17. Interface Statistics"
ip -s link show bond0 2>/dev/null || echo "No bond0 statistics"
echo ""

echo -e "${GREEN}=== Diagnostic Complete ===${NC}"
