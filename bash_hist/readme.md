Here's a comprehensive bash script that will backup your current CLI history and optimize it for 100K lines with intelligent management:
Quick Setup & Run
Step 1: Create and Run the Script
bash# Create the script
nano ~/history-optimizer.sh

# Copy the entire script from the artifact above, then:

# Make executable and run
chmod +x ~/history-optimizer.sh
./history-optimizer.sh
What This Script Does
🔄 Backup Features:

Current .bash_history file → timestamped backup
Current session history → separate backup
Combined complete backup → everything in one file
Automatic .bashrc backup → before making changes

⚙️ Optimization Settings:

HISTSIZE=100,000 (commands in memory)
HISTFILESIZE=100,000 (commands in file)
Intelligent deduplication (removes duplicate commands)
Timestamp format: YYYY-MM-DD HH:MM:SS
Smart filtering: Ignores ls, cd, pwd, clear, etc.
Auto-save: History saved after each command

📏 Size Management:

Estimated max size: ~50MB (with timestamps)
Automatic cleanup of exact duplicates
Maintenance script included for periodic cleanup
Backup rotation (keeps 10 newest backups)

🚀 Enhanced Features:

Arrow key search: ↑/↓ searches commands starting with what you type
Better tab completion: Case-insensitive, shows all matches
Enhanced readline: Improved command-line experience
Multiple terminal sync: History shared across terminals

Expected File Size Calculation
100,000 lines × (50 chars avg command + 20 chars timestamp) = ~50MB maximum
Quick Test After Running
bash# Check new settings are active
echo $HISTSIZE
echo $HISTFILESIZE

# Test enhanced search (type 'sudo' then press ↑)
sudo ↑

# Check current history size
wc -l ~/.bash_history

# View recent commands with timestamps
history 10
Maintenance Commands Created
The script also creates ~/history-maintenance.sh for ongoing management:
bash# Run manual maintenance
~/history-maintenance.sh

# Add to crontab for weekly automatic cleanup
crontab -e
# Add: 0 2 * * 0 /home/ryleh/history-maintenance.sh
Backup Location
All backups stored in: ~/.history_backups/
Restore if Needed
bash# Restore original history
cp ~/.history_backups/bash_history_TIMESTAMP.bak ~/.bash_history

# Restore original .bashrc
cp ~/.bashrc.backup_TIMESTAMP ~/.bashrc
This gives you professional-grade command history management perfect for development work, with all the safety backups and intelligent features you need! 🎯
