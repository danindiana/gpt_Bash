#!/bin/bash

# Function to log messages to the console
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check system details
log "Checking system details..."
lsb_release -a
bash --version

# Check for the alias in ~/.bash_aliases
log "Checking ~/.bash_aliases for the google-chrome alias..."
if grep -q 'alias google-chrome' ~/.bash_aliases; then
    log "Alias found in ~/.bash_aliases:"
    grep 'alias google-chrome' ~/.bash_aliases
else
    log "Alias not found in ~/.bash_aliases."
fi

# Check for the alias in ~/.bashrc
log "Checking ~/.bashrc for the google-chrome alias..."
if grep -q 'alias google-chrome' ~/.bashrc; then
    log "Alias found in ~/.bashrc:"
    grep 'alias google-chrome' ~/.bashrc
else
    log "Alias not found in ~/.bashrc."
fi

# Check for system-wide aliases
log "Checking /etc for system-wide google-chrome aliases..."
if sudo grep -r 'alias google-chrome' /etc 2>/dev/null; then
    log "System-wide alias found:"
    sudo grep -r 'alias google-chrome' /etc
else
    log "No system-wide alias found."
fi

# Check for other configuration files in the home directory
log "Checking home directory for other configuration files containing the google-chrome alias..."
if grep -r 'alias google-chrome' ~/ 2>/dev/null; then
    log "Alias found in other configuration files:"
    grep -r 'alias google-chrome' ~/
else
    log "No alias found in other configuration files."
fi

# Check if the alias is currently available
log "Checking if the google-chrome alias is currently available..."
if alias google-chrome 2>/dev/null; then
    log "Alias is currently available:"
    alias google-chrome
else
    log "Alias is not currently available."
fi

# Check for recent changes in Bash configuration files
log "Checking for recent changes in Bash configuration files..."
log "Last modification time of ~/.bashrc: $(stat -c %y ~/.bashrc)"
log "Last modification time of ~/.bash_aliases: $(stat -c %y ~/.bash_aliases 2>/dev/null || echo 'File not found')"

# Check for recent changes in Google Chrome settings
log "Checking for recent changes in Google Chrome settings..."
log "Last modification time of Google Chrome config directory: $(stat -c %y ~/.config/google-chrome 2>/dev/null || echo 'Directory not found')"

log "Script execution completed."
