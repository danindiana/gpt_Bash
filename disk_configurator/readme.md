How to use:

Save: Save the script to a file (e.g., configure_drive.sh).
Make executable: chmod +x configure_drive.sh
Run (with sudo): sudo./configure_drive.sh
Key improvements and explanations:

Configuration variables: The drive, mount point, filesystem, and label are now set as variables at the beginning of the script. This makes it easy to modify the script for different drives.
Error handling: The handle_error function will print an error message and exit the script if any command fails. This is crucial for preventing accidental data loss.
Drive verification: The script now checks if the specified drive exists using lsblk. This is a crucial step to prevent accidentally formatting the wrong drive.
Confirmation prompt: The script asks for confirmation before proceeding with formatting. This is another important safety measure.
gdisk for GPT: The script uses gdisk for partitioning, which is recommended for modern systems. If you need MBR partitioning for compatibility with very old systems, you can replace the gdisk commands with fdisk commands.
Partition variable: The script dynamically determines the partition name (/dev/sdc1, /dev/sdd1, etc.) based on the drive you specify.
Label setting: The script sets the label after formatting.
-p option for mkdir: The -p option with mkdir will create parent directories if they don't exist, preventing errors if the full path to the mount point isn't present.
tee -a for /etc/fstab: The script uses tee -a to append the entry to /etc/fstab. tee is safer than redirection (>) because it won't overwrite the file if something goes wrong.
UUID retrieval: The script now uses blkid to get the UUID and uses cut to extract the UUID value, making it more robust.
Clearer output: The script provides more informative output messages.
Extremely Important:

Double-check the DRIVE variable: Make absolutely sure you set the DRIVE variable to the correct drive name. Formatting the wrong drive will result in irreversible data loss. Use lsblk to confirm.
Understand the script: Before running the script, read it carefully and make sure you understand what each command does.
Test on a non-critical drive first: If you're unsure, test the script on a drive that doesn't contain important data before using it on a drive with valuable data.
