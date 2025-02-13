#!/bin/bash

# Disk Drive Enrollment Script
# This script formats, mounts, and configures a disk drive for automatic mounting on boot.
# It prompts the user for each action and warns about potential data loss.

# --- Functions ---

# Function to handle errors and exit
handle_error() {
  echo "Error: $1"
  exit 1
}

# Function to confirm user action
confirm_action() {
  read -p "$1 (y/N) " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborting."
    exit 1
  fi
}

# --- Main Script ---

# Welcome message
echo "=== Disk Drive Enrollment Script ==="
echo "This script will help you format, mount, and configure a disk drive."
echo "WARNING: This process may result in data loss. Proceed with caution!"
echo ""

# Step 1: Prompt for the drive to configure
echo "Available drives:"
lsblk -o NAME,SIZE,MODEL
read -p "Enter the drive to configure (e.g., /dev/sdb): " DRIVE

# Verify the drive exists
lsblk "$DRIVE" || handle_error "Drive $DRIVE not found. Double-check the drive name."

# Step 2: Warn about data loss
echo ""
echo "WARNING: All data on $DRIVE will be lost!"
confirm_action "Are you absolutely sure you want to proceed?"

# Step 3: Wipe the drive (optional)
echo ""
confirm_action "Do you want to wipe the drive $DRIVE? (This will erase all data!)"
if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
  echo "Wiping the drive..."
  sudo wipefs -a "$DRIVE" || handle_error "Failed to wipe the drive."
fi

# Step 4: Partition the drive
echo ""
echo "Partitioning the drive $DRIVE..."
confirm_action "Do you want to create a new partition on $DRIVE?"
sudo gdisk "$DRIVE" << EOF
n  # New partition
1  # Partition number (default 1)
   # First sector (default)
   # Last sector or size (default - uses all space)
8300 # Linux filesystem type
w  # Write changes
y  # Confirm write
EOF

# Verify the partition
PARTITION="${DRIVE}1"
lsblk "$PARTITION" || handle_error "Partition $PARTITION not found."

# Step 5: Format the partition
echo ""
echo "Formatting the partition $PARTITION..."
read -p "Enter the filesystem type (e.g., ext4, xfs): " FILESYSTEM
confirm_action "Do you want to format $PARTITION as $FILESYSTEM?"
sudo mkfs."$FILESYSTEM" "$PARTITION" || handle_error "Failed to format the partition."

# Step 6: Set a label for the partition
echo ""
read -p "Enter a label for the partition (e.g., my_drive): " DRIVE_LABEL
echo "Setting label..."
sudo e2label "$PARTITION" "$DRIVE_LABEL" || handle_error "Failed to set label."

# Step 7: Create the mount point
echo ""
read -p "Enter the mount point directory (e.g., /mnt/my_drive): " MOUNT_POINT
echo "Creating the mount point directory..."
sudo mkdir -p "$MOUNT_POINT" || handle_error "Failed to create mount point directory."

# Step 8: Mount the partition
echo ""
echo "Mounting the partition $PARTITION to $MOUNT_POINT..."
sudo mount "$PARTITION" "$MOUNT_POINT" || handle_error "Failed to mount the partition."

# Step 9: Add to /etc/fstab
echo ""
echo "Adding the partition to /etc/fstab for automatic mounting on boot..."
UUID=$(sudo blkid -s UUID -o value "$PARTITION") || handle_error "Failed to get UUID."
FSTAB_ENTRY="UUID=$UUID $MOUNT_POINT $FILESYSTEM defaults 0 2"
echo "Adding the following line to /etc/fstab:"
echo "$FSTAB_ENTRY"
confirm_action "Do you want to proceed?"
echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab || handle_error "Failed to add to /etc/fstab."

# Step 10: Test the /etc/fstab entry
echo ""
echo "Testing /etc/fstab entry..."
sudo mount -a || handle_error "Failed to mount using /etc/fstab. Check /etc/fstab for errors."

# Step 11: Verify the configuration
echo ""
echo "Drive $DRIVE successfully configured!"
echo "Partition $PARTITION is mounted at $MOUNT_POINT."
echo "Here are the current mounts:"
df -h | grep "$MOUNT_POINT"

# Step 12: Set permissions (optional)
echo ""
confirm_action "Do you want to set permissions for $MOUNT_POINT?"
read -p "Enter the username to grant ownership (e.g., $USER): " USERNAME
sudo chown -R "$USERNAME:$USERNAME" "$MOUNT_POINT" || handle_error "Failed to set ownership."
echo "Ownership of $MOUNT_POINT set to $USERNAME."

# Completion message
echo ""
echo "=== Enrollment Complete ==="
echo "The drive $DRIVE has been successfully enrolled and will automatically mount on boot."
echo "Mount point: $MOUNT_POINT"
echo "Partition UUID: $UUID"
echo "Filesystem: $FILESYSTEM"
echo "Label: $DRIVE_LABEL"

exit 0
