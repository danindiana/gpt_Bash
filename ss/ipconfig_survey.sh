#!/bin/bash

# Function for formatted output
execute_cmd() {
  echo "----------------------"
  echo "Executing: $*"
  $*
  echo "----------------------"
}

# --- ss commands ---
# (Include the ss commands from the previous example)
execute_ss -s 
execute_ss -lnt
execute_ss -lnu
execute_ss -ant
execute_ss -antp 
execute_ss -antup

# --- ip commands ---
execute_cmd ip addr show  # Show network interfaces and addresses
execute_cmd ip route      # Display routing table

# --- netstat commands --- 
execute_cmd netstat -a    # Show all active connections and listening ports
execute_cmd netstat -r    # Show the routing table 
execute_cmd netstat -s    # Network statistics

# --- Other useful tools --- (Optional)
execute_cmd arp -a        # View the ARP cache
execute_cmd hostname --all-ip-addresses  #  Show IP addresses for hostname
