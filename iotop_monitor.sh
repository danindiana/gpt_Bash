#!/bin/bash

# Check if iotop is installed
if ! command -v iotop &> /dev/null; then
    echo "iotop is not installed. Please install it first."
    exit 1
fi

# Specify the log file in the current directory
LOGFILE="./iotop_monitor.log"

# Add a header to the log file
echo "Starting iotop disk monitor on $(date)" | tee -a "$LOGFILE"
echo "========================================" | tee -a "$LOGFILE"

# Monitor disk I/O activity using iotop
while true; do
    echo "Timestamp: $(date)" | tee -a "$LOGFILE"
    iotop -n 1 -b | tee -a "$LOGFILE"  # -n 1: take 1 snapshot, -b: batch mode
    echo "----------------------------------------" | tee -a "$LOGFILE"
    sleep 10  # Wait for 10 seconds before the next snapshot
done
