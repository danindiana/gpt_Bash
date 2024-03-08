#!/bin/bash

# Function for formatted output
execute_cmd() {
  echo "----------------------"
  echo "Executing: $*"
  $*
  echo "----------------------"
  sleep 2 # Add a 1-second delay after each command
}

# --- ss commands ---
execute_cmd ss -ss 
execute_cmd ss -lnt
execute_cmd ss -lnu
execute_cmd ss -ant
execute_cmd ss -antp 
execute_cmd ss -antup

# --- ip commands ---
execute_cmd ip addr show # Show network interfaces and addresses
execute_cmd ip route   # Display routing table

# --- netstat commands --- 
execute_cmd netstat -a  # Show all active connections and listening ports
execute_cmd netstat -r  # Display the routing table 
execute_cmd netstat -s  # Network statistics

# --- Other useful tools --- (Optional)
execute_cmd arp -a    # View the ARP cache
execute_cmd hostname --all-ip-addresses # Show IP addresses for hostname
