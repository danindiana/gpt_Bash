#!/bin/bash

# Function for formatted output
execute_ss() {
  echo "----------------------"
  echo "Executing: ss $*"  # Show the ss command
  ss $*
  echo "----------------------"
}

# Summary of active connections
execute_ss -s 

# All listening TCP sockets
execute_ss -lnt

# All listening UDP sockets
execute_ss -lnu

# TCP sockets with established connections
execute_ss -ant

# TCP sockets in various states (listen, established, time-wait, etc.)
execute_ss -antp 

# Show process information associated with sockets
execute_ss -antup
