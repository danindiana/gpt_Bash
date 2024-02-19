#!/bin/bash

# File Name: system_info.sh

# Function to get the system's UUID
get_system_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [ -f /sys/class/dmi/id/product_uuid ]; then
        cat /sys/class/dmi/id/product_uuid
    elif [ -f /etc/machine-id ]; then
        cat /etc/machine-id
    else
        echo "Unable to determine system UUID"
    fi
}

# Function to get the system's MAC address
get_mac_address() {
    ifconfig | grep -oP 'HWaddr\s+\K[\da-fA-F:]+' | head -n 1
}

# Function to get the CPU details
get_cpu_info() {
    lscpu
}

# Get the current date and time
current_date_time=$(date)
echo "Current date and time: $current_date_time"

# Get the current time in Unix timestamp format
current_unix_time=$(date +%s)
echo "Current time in Unix timestamp: $current_unix_time"

# Get the current timezone
current_timezone=$(timedatectl | grep "Time zone" | awk '{print $3}')
echo "Current timezone: $current_timezone"

# Get the current time in the current timezone
current_time_in_tz=$(TZ=$current_timezone date)
echo "Current time in current timezone: $current_time_in_tz"

# Get the system's UUID
system_uuid=$(get_system_uuid)
echo "System UUID: $system_uuid"

# Get the system's MAC address
mac_address=$(get_mac_address)
echo "MAC Address: $mac_address"

# Get the CPU details
cpu_info=$(get_cpu_info)
echo "CPU Details:"
echo "$cpu_info"

# Generate a hash of the system UUID and MAC address
system_hash=$(echo -n "$system_uuid$mac_address" | sha256sum | awk '{print $1}')
echo "System Hash (SHA256 of UUID and MAC address): $system_hash"
