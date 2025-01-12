#!/bin/bash

# Default network range
DEFAULT_NETWORK="192.168.1.0/24"
declare -A ANONYMIZED_MAP  # Mapping for anonymized IPs
declare -A PORT_MAP        # Mapping for anonymized ports/services

# Generate a random anonymized identifier
generate_random_id() {
    echo "$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 8)"
}

# Function to anonymize identifiers
anonymize_id() {
    local key=$1
    if [[ -z "${ANONYMIZED_MAP[$key]}" ]]; then
        ANONYMIZED_MAP[$key]=$(generate_random_id)
    fi
    echo "${ANONYMIZED_MAP[$key]}"
}

# Function to anonymize ports/services
anonymize_port_service() {
    local key=$1
    if [[ -z "${PORT_MAP[$key]}" ]]; then
        PORT_MAP[$key]=$(generate_random_id)
    fi
    echo "${PORT_MAP[$key]}"
}

# Function to scan LAN for active machines
scan_network() {
    echo "Scanning the network for active machines..."
    read -p "Enter your network range (default: $DEFAULT_NETWORK): " network
    network=${network:-$DEFAULT_NETWORK}  # Use default if no input provided
    # Perform a ping scan and extract IP addresses
    nmap -sn "$network" | grep "Nmap scan report for" | awk '{print $NF}' | tr -d '()'
}

# Function to perform a port scan on a machine with a 30-second timeout
scan_ports() {
    local ip=$1
    local display_ip=$2
    echo "Scanning ports on $display_ip (timeout: 30 seconds)..."
    nmap --host-timeout 30s -Pn "$ip" | grep "open" | while read -r line; do
        if [[ "$anonymize_choice" == "y" ]]; then
            port=$(echo "$line" | awk '{print $1}')
            service=$(echo "$line" | awk '{print $3}')
            anonymized_port=$(anonymize_port_service "$port-$service")
            echo "$anonymized_port anonymized"
        else
            echo "$line"
        fi
    done
}

# Main script logic
discover_and_scan() {
    local ips=$(scan_network)
    echo "Discovered machines:"
    echo "$ips"

    # Ask the user if they want anonymized output
    read -p "Do you want to anonymize the output? (Y/N): " anonymize_choice
    anonymize_choice=${anonymize_choice,,}  # Convert to lowercase

    for ip in $ips; do
        if [[ "$anonymize_choice" == "y" ]]; then
            display_id=$(anonymize_id "$ip")
        else
            display_id=$ip
        fi

        echo "=== $display_id ==="
        scan_ports "$ip" "$display_id"
        echo "============"
    done
}

# Start the process
discover_and_scan
