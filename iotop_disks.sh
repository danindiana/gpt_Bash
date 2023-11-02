#!/bin/bash

# Check if iotop is installed
if ! command -v iotop &> /dev/null; then
    echo "iotop is not installed. Please install it first."
    exit 1
fi

# Specify the log file
LOGFILE="/var/log/iotop_monitor.log"

# Add a header to the log file
echo "Starting iotop disk monitor on $(date)" >> "$LOGFILE"
echo "========================================" >> "$LOGFILE"

# Monitor disk I/O activity using iotop
while true; do
    echo "Timestamp: $(date)" >> "$LOGFILE"
    iotop -n 1 -b -o >> "$LOGFILE"  # -n 1: take 1 snapshot, -b: batch mode, -o: only show processes doing I/O
    echo "----------------------------------------" >> "$LOGFILE"
    sleep 10  # Wait for 10 seconds before the next snapshot
done
