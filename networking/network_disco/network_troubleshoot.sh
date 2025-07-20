#!/bin/bash

# Network Troubleshooting Information Gatherer
# Collects comprehensive network configuration and hardware info
# Usage: sudo ./network_troubleshoot.sh [output_file]

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Set output file
OUTPUT_FILE="${1:-network_troubleshoot_$(date +%Y%m%d_%H%M%S).txt}"
TEMP_FILE="/tmp/network_info_$$"

# Function to print colored headers
print_header() {
    echo -e "\n${BLUE}===============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===============================================${NC}"
}

# Function to run command and capture output
run_cmd() {
    local cmd="$1"
    local description="$2"
    
    echo -e "\n${GREEN}## $description${NC}"
    echo "Command: $cmd"
    echo "----------------------------------------"
    
    if eval "$cmd" 2>/dev/null; then
        echo -e "${GREEN}✓ Success${NC}"
    else
        echo -e "${RED}✗ Failed or not available${NC}"
    fi
    echo ""
}

# Check if running as root for some commands
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}Warning: Some commands require sudo privileges for complete output${NC}"
        echo -e "${YELLOW}Run as: sudo $0 $1${NC}\n"
    fi
}

# Start logging
exec > >(tee "$TEMP_FILE")

echo "=========================================="
echo "Network Troubleshooting Information Report"
echo "Generated: $(date)"
echo "Hostname: $(hostname)"
echo "User: $(whoami)"
echo "=========================================="

check_root "$1"

# System Information
print_header "SYSTEM INFORMATION"
run_cmd "uname -a" "Kernel Information"
run_cmd "lsb_release -a" "OS Release Information"
run_cmd "uptime" "System Uptime"
run_cmd "free -h" "Memory Usage"

# Hardware Detection
print_header "NETWORK HARDWARE DETECTION"
run_cmd "lspci | grep -i ethernet" "PCI Ethernet Controllers"
run_cmd "lspci -k | grep -i 'ethernet\|network' -A 3" "Ethernet Controllers with Drivers"
run_cmd "sudo lshw -class network -businfo" "Detailed Network Hardware"
run_cmd "lsmod | grep -E '(ixgbe|igb|e1000|r8169)'" "Network Driver Modules"

# Intel NIC Specific Information
print_header "INTEL NIC SPECIFIC INFO"
run_cmd "sudo dmesg | grep -i ixgbe | head -20" "Intel ixgbe Driver Messages"
run_cmd "lspci -k | grep -i 'intel.*x5' -A 3" "Intel X5 Series Detection"

# Network Interface Information
print_header "NETWORK INTERFACE CONFIGURATION"
run_cmd "ip link show" "All Network Interfaces"
run_cmd "ip addr show" "Interface IP Addresses"
run_cmd "sudo ethtool enp3s0f0" "Intel NIC Port 0 Details"
run_cmd "sudo ethtool enp3s0f1" "Intel NIC Port 1 Details"
run_cmd "sudo ethtool enp9s0" "Motherboard NIC Details"

# Bonding Information
print_header "BONDING CONFIGURATION"
run_cmd "cat /proc/net/bonding/bond0" "Bond0 Status (if exists)"
run_cmd "sudo modinfo bonding" "Bonding Module Information"
run_cmd "lsmod | grep bonding" "Bonding Module Loaded"

# Network Configuration Files
print_header "NETWORK CONFIGURATION FILES"
run_cmd "sudo cat /etc/netplan/*.yaml" "Netplan Configuration"
run_cmd "ls -la /etc/netplan/" "Netplan Files List"
run_cmd "sudo netplan --debug generate" "Netplan Configuration Test"

# Routing Information
print_header "ROUTING AND CONNECTIVITY"
run_cmd "ip route show" "Routing Table"
run_cmd "ip -6 route show" "IPv6 Routing Table"
run_cmd "cat /etc/resolv.conf" "DNS Configuration"
run_cmd "systemctl status systemd-networkd" "Networkd Service Status"

# Network Statistics
print_header "NETWORK STATISTICS"
run_cmd "cat /proc/net/dev" "Interface Statistics"
run_cmd "ip -s link show" "Interface Statistics (ip command)"
run_cmd "sudo ss -tuln" "Listening Ports"

# Switch Discovery
print_header "NETWORK DISCOVERY"
run_cmd "sudo lldpcli show neighbors" "LLDP Neighbors"
run_cmd "arp -a" "ARP Table"
run_cmd "ip neigh show" "Neighbor Table"

# Network Performance Testing
print_header "NETWORK PERFORMANCE TOOLS"
run_cmd "which speedtest" "Speedtest CLI Available"
run_cmd "which mtr" "MTR Available"
run_cmd "which iperf3" "iperf3 Available"

# Sample connectivity test
print_header "BASIC CONNECTIVITY TEST"
run_cmd "ping -c 4 8.8.8.8" "Ping Test to Google DNS"
run_cmd "ping -c 4 1.1.1.1" "Ping Test to Cloudflare DNS"

# PCIe and Power Information
print_header "SYSTEM RESOURCES"
run_cmd "lspci -vv | grep -A 10 -B 2 'Ethernet controller'" "Detailed PCI Information"
run_cmd "sudo dmidecode -t system" "System Information"
run_cmd "cat /proc/cpuinfo | grep 'model name' | head -1" "CPU Information"

# Systemd Network Configuration
print_header "SYSTEMD NETWORK FILES"
run_cmd "ls -la /run/systemd/network/" "Generated Network Files"
run_cmd "sudo cat /run/systemd/network/*.network" "Network Configuration Files"
run_cmd "sudo cat /run/systemd/network/*.netdev" "Network Device Files"

# Recent System Logs
print_header "RECENT NETWORK LOGS"
run_cmd "sudo journalctl -u systemd-networkd --no-pager -n 20" "Recent Networkd Logs"
run_cmd "sudo dmesg | grep -i 'link\|ethernet\|network' | tail -10" "Recent Kernel Network Messages"

# Environment Variables
print_header "ENVIRONMENT"
run_cmd "env | grep -i 'network\|interface'" "Network Environment Variables"

# Network Security
print_header "NETWORK SECURITY"
run_cmd "sudo iptables -L" "Iptables Rules"
run_cmd "sudo ufw status" "UFW Firewall Status"

# Final Summary
print_header "SUMMARY"
echo "Network Interfaces Found:"
ip link show | grep -E '^[0-9]+:' | sed 's/^[0-9]*: /  /'
echo ""
echo "Active IP Addresses:"
ip addr show | grep 'inet ' | grep -v '127.0.0.1' | sed 's/^/  /'
echo ""
echo "Bond Interfaces:"
if [ -f /proc/net/bonding/bond0 ]; then
    echo "  bond0: CONFIGURED"
    cat /proc/net/bonding/bond0 | grep -E 'Bonding Mode|Currently Active Slave|MII Status' | sed 's/^/    /'
else
    echo "  No bonding configured"
fi

echo ""
echo "=========================================="
echo "Report generation completed: $(date)"
echo "=========================================="

# Copy to final output file
cp "$TEMP_FILE" "$OUTPUT_FILE"
rm "$TEMP_FILE"

echo -e "\n${GREEN}Report saved to: $OUTPUT_FILE${NC}"
echo -e "${BLUE}To view: less $OUTPUT_FILE${NC}"
echo -e "${BLUE}To share: cat $OUTPUT_FILE | grep -v 'password\|secret'${NC}"
