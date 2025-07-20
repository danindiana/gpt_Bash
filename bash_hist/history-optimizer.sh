#!/bin/bash

# Bash History Optimizer & Backup Script
# Backs up current history and optimizes bash history settings for development work

SCRIPT_NAME="Bash History Optimizer"
VERSION="1.0"
BACKUP_DIR="$HOME/.history_backups"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${CYAN}[HEADER]${NC} $1"
}

# Function to get current history stats
get_history_stats() {
    local history_file="$1"
    if [[ -f "$history_file" ]]; then
        local lines=$(wc -l < "$history_file" 2>/dev/null || echo "0")
        local size=$(du -h "$history_file" 2>/dev/null | cut -f1 || echo "0")
        echo "Lines: $lines, Size: $size"
    else
        echo "File not found"
    fi
}

# Function to show current settings
show_current_settings() {
    print_header "Current Bash History Settings"
    echo "HISTSIZE (memory): ${HISTSIZE:-default}"
    echo "HISTFILESIZE (file): ${HISTFILESIZE:-default}"
    echo "HISTCONTROL: ${HISTCONTROL:-default}"
    echo "HISTTIMEFORMAT: ${HISTTIMEFORMAT:-not set}"
    echo "HISTFILE: ${HISTFILE:-$HOME/.bash_history}"
    echo
    echo "Current history stats: $(get_history_stats "$HOME/.bash_history")"
    echo "Current session commands: $(history | wc -l)"
    echo "================================"
}

# Function to create backup
backup_history() {
    print_info "Creating backup of current bash history..."
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Backup main history file
    if [[ -f "$HOME/.bash_history" ]]; then
        cp "$HOME/.bash_history" "$BACKUP_DIR/bash_history_${TIMESTAMP}.bak"
        print_success "Backed up ~/.bash_history to $BACKUP_DIR/bash_history_${TIMESTAMP}.bak"
    else
        print_warning "No existing ~/.bash_history file found"
    fi
    
    # Backup current session history
    history -w "$BACKUP_DIR/session_history_${TIMESTAMP}.bak"
    print_success "Backed up current session history to $BACKUP_DIR/session_history_${TIMESTAMP}.bak"
    
    # Create a combined backup
    {
        echo "# Bash History Backup - $TIMESTAMP"
        echo "# Original .bash_history file:"
        if [[ -f "$HOME/.bash_history" ]]; then
            cat "$HOME/.bash_history"
        fi
        echo
        echo "# Current session history:"
        history
    } > "$BACKUP_DIR/complete_history_${TIMESTAMP}.bak"
    
    print_success "Created complete backup at $BACKUP_DIR/complete_history_${TIMESTAMP}.bak"
    
    # Show backup stats
    echo
    print_info "Backup Statistics:"
    for file in "$BACKUP_DIR"/*_${TIMESTAMP}.bak; do
        if [[ -f "$file" ]]; then
            local filename=$(basename "$file")
            local stats=$(get_history_stats "$file")
            echo "  $filename: $stats"
        fi
    done
}

# Function to optimize bash history settings
optimize_history() {
    print_info "Optimizing bash history settings..."
    
    local bashrc="$HOME/.bashrc"
    local bashrc_backup="${bashrc}.backup_${TIMESTAMP}"
    
    # Backup .bashrc
    cp "$bashrc" "$bashrc_backup"
    print_success "Backed up .bashrc to $bashrc_backup"
    
    # Remove existing history settings to avoid duplicates
    print_info "Removing any existing history settings from .bashrc..."
    sed -i '/^# History settings/,/^$/d' "$bashrc"
    sed -i '/^HISTSIZE=/d' "$bashrc"
    sed -i '/^HISTFILESIZE=/d' "$bashrc"
    sed -i '/^HISTCONTROL=/d' "$bashrc"
    sed -i '/^HISTTIMEFORMAT=/d' "$bashrc"
    sed -i '/^HISTIGNORE=/d' "$bashrc"
    sed -i '/^export HISTSIZE/d' "$bashrc"
    sed -i '/^export HISTFILESIZE/d' "$bashrc"
    sed -i '/^export HISTCONTROL/d' "$bashrc"
    sed -i '/^export HISTTIMEFORMAT/d' "$bashrc"
    sed -i '/^export HISTIGNORE/d' "$bashrc"
    
    # Add optimized history settings
    print_info "Adding optimized history settings to .bashrc..."
    
    cat >> "$bashrc" << 'EOF'

# History settings - Optimized for development work
# Added by Bash History Optimizer script

# Number of commands to remember in memory during session
export HISTSIZE=100000

# Number of commands to store in history file
export HISTFILESIZE=100000

# Don't save duplicate commands and commands starting with space
export HISTCONTROL=ignoreboth:erasedups

# Add timestamps to history (format: YYYY-MM-DD HH:MM:SS)
export HISTTIMEFORMAT='%Y-%m-%d %H:%M:%S '

# Don't save common commands that clutter history
export HISTIGNORE='ls:ll:la:cd:pwd:clear:history:exit:bg:fg:jobs'

# Append to history file instead of overwriting
shopt -s histappend

# Save history after each command (for multiple terminals)
export PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"

# Increase readline history for better tab completion
export INPUTRC="$HOME/.inputrc"

EOF
    
    print_success "Added optimized history settings to .bashrc"
    
    # Create optimized .inputrc for better readline behavior
    print_info "Creating optimized .inputrc for better command-line experience..."
    
    cat > "$HOME/.inputrc" << 'EOF'
# .inputrc - Optimized readline settings
# Added by Bash History Optimizer script

# Better history search
"\e[A": history-search-backward
"\e[B": history-search-forward

# Better tab completion
set completion-ignore-case on
set completion-map-case on
set show-all-if-ambiguous on
set show-all-if-unmodified on
set menu-complete-display-prefix on

# Don't ring bell on completion
set bell-style none

# Show completion matches immediately
set show-mode-in-prompt on

# Better color support
set colored-stats on
set colored-completion-prefix on

EOF
    
    print_success "Created optimized .inputrc"
}

# Function to apply settings immediately
apply_settings() {
    print_info "Applying new settings to current session..."
    
    # Source the updated .bashrc
    source "$HOME/.bashrc"
    
    # Apply .inputrc settings
    bind -f "$HOME/.inputrc"
    
    print_success "Settings applied to current session"
}

# Function to show new settings
show_new_settings() {
    print_header "New Bash History Settings"
    echo "HISTSIZE (memory): 100,000 commands"
    echo "HISTFILESIZE (file): 100,000 commands"
    echo "HISTCONTROL: ignoreboth:erasedups (no duplicates, ignore commands starting with space)"
    echo "HISTTIMEFORMAT: YYYY-MM-DD HH:MM:SS (timestamps enabled)"
    echo "HISTIGNORE: Common commands filtered out (ls, cd, pwd, etc.)"
    echo "Additional: histappend enabled, auto-save after each command"
    echo "Readline: Enhanced tab completion and history search"
    echo
    
    # Calculate estimated file size
    local avg_command_length=50  # Estimate average characters per command
    local timestamp_length=20    # Length of timestamp
    local total_chars_per_line=$((avg_command_length + timestamp_length))
    local estimated_size_bytes=$((100000 * total_chars_per_line))
    local estimated_size_mb=$((estimated_size_bytes / 1024 / 1024))
    
    echo "Estimated maximum file size: ~${estimated_size_mb}MB (with timestamps)"
    echo "================================"
}

# Function to show usage tips
show_usage_tips() {
    print_header "Usage Tips for Enhanced History"
    echo
    echo "🔍 Enhanced History Search:"
    echo "  • Use ↑/↓ arrows: Search through commands that start with what you've typed"
    echo "  • Ctrl+R: Reverse search through history"
    echo "  • history | grep 'pattern': Search for specific commands"
    echo
    echo "💡 Useful History Commands:"
    echo "  • history 50: Show last 50 commands"
    echo "  • !123: Execute command number 123"
    echo "  • !!: Repeat last command"
    echo "  • !pattern: Execute last command starting with 'pattern'"
    echo
    echo "🧹 History Management:"
    echo "  • history -c: Clear current session history"
    echo "  • history -w: Write current session to file"
    echo "  • history -d 123: Delete specific command number"
    echo
    echo "🔒 Privacy Tips:"
    echo "  • Start commands with space to exclude from history"
    echo "  • Use 'unset HISTFILE' to disable history for current session"
    echo
    echo "📁 Backup Location: $BACKUP_DIR"
    echo "🔄 To restore backup: cp $BACKUP_DIR/bash_history_${TIMESTAMP}.bak ~/.bash_history"
    echo "================================"
}

# Function to create maintenance script
create_maintenance_script() {
    local maintenance_script="$HOME/history-maintenance.sh"
    
    print_info "Creating history maintenance script..."
    
    cat > "$maintenance_script" << 'EOF'
#!/bin/bash
# History Maintenance Script
# Run this periodically to manage history file size

BACKUP_DIR="$HOME/.history_backups"
MAX_BACKUPS=10

echo "History Maintenance - $(date)"
echo "================================"

# Current stats
echo "Current history size: $(wc -l < ~/.bash_history) lines"
echo "File size: $(du -h ~/.bash_history | cut -f1)"

# Clean up old backups (keep only latest 10)
if [[ -d "$BACKUP_DIR" ]]; then
    backup_count=$(ls -1 "$BACKUP_DIR"/bash_history_*.bak 2>/dev/null | wc -l)
    if [[ $backup_count -gt $MAX_BACKUPS ]]; then
        echo "Cleaning old backups (keeping $MAX_BACKUPS newest)..."
        ls -1t "$BACKUP_DIR"/bash_history_*.bak | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f
    fi
fi

# Remove exact duplicates while preserving order
echo "Removing exact duplicates..."
temp_file=$(mktemp)
awk '!seen[$0]++' ~/.bash_history > "$temp_file"
mv "$temp_file" ~/.bash_history

echo "Maintenance complete!"
echo "New history size: $(wc -l < ~/.bash_history) lines"
echo "================================"
EOF
    
    chmod +x "$maintenance_script"
    print_success "Created maintenance script at $maintenance_script"
    
    # Add to crontab suggestion
    echo
    print_info "💡 Suggestion: Add to crontab for automatic maintenance:"
    echo "    crontab -e"
    echo "    # Add this line for weekly maintenance:"
    echo "    0 2 * * 0 $maintenance_script"
}

# Main script execution
main() {
    echo
    print_header "$SCRIPT_NAME v$VERSION"
    echo "This script will backup your current bash history and optimize settings"
    echo "for development work with 100K line history storage."
    echo
    
    # Show current settings
    show_current_settings
    echo
    
    # Confirm with user
    read -p "Do you want to proceed with backup and optimization? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Operation cancelled by user"
        exit 0
    fi
    
    echo
    print_info "Starting bash history optimization..."
    echo
    
    # Step 1: Backup current history
    backup_history
    echo
    
    # Step 2: Optimize settings
    optimize_history
    echo
    
    # Step 3: Apply settings
    apply_settings
    echo
    
    # Step 4: Create maintenance script
    create_maintenance_script
    echo
    
    # Show results
    show_new_settings
    echo
    show_usage_tips
    
    print_success "Bash history optimization complete!"
    print_warning "Note: Open a new terminal or run 'source ~/.bashrc' to fully apply all settings"
    echo
    print_info "Your command history will now:"
    echo "  ✅ Store up to 100,000 commands with timestamps"
    echo "  ✅ Automatically backup and avoid duplicates"
    echo "  ✅ Provide enhanced search and completion"
    echo "  ✅ Filter out common clutter commands"
    echo "  ✅ Maintain reasonable file sizes (~50MB max)"
}

# Run main function
main "$@"
