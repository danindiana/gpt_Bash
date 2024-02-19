#!/bin/bash

# Function to log the output of a command to a file
log_command_output() {
  command="$1"
  section_header="$2"
  
  echo "$section_header" >> network_report.txt
  echo "--------------" >> network_report.txt
  $command >> network_report.txt
  echo "" >> network_report.txt # Add a blank line for spacing
}

# Output filename
output_file="network_report.txt"

# Clear any existing output file
> $output_file 

# WHOIS
log_command_output "whois example.com" "WHOIS"

# NSLOOKUP
log_command_output "nslookup example.com" "NSLOOKUP"

# MTR
log_command_output "mtr --report --report-wide --report-cycles 10 example.com" "MTR"

# IPCALC 
log_command_output "ipcalc 192.168.0.0/24" "IPCALC"

# SS
log_command_output "ss -a -A inet6" "SS"

# NETSTAT
log_command_output "netstat -6av" "NETSTAT"

# TELNET NOTE (No change needed here)
echo 'TELNET' >> network_report.txt
echo 'Telnet command is interactive and cannot be logged into a file' >> network_report.txt
