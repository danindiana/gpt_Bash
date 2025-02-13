#!/bin/bash

# Script to format, mount, and configure a drive for automatic mounting on boot.

# --- Configuration (Modify these) ---
DRIVE="/dev/sdX"  # Replace /dev/sdX with the actual drive name (e.g., /dev/sdd, /dev/sde).  BE VERY CAREFUL HERE!
MOUNT_POINT="/mnt/new_drive" # Replace with your desired mount point (e.g., /media/new_drive, /data/new_drive).
FILESYSTEM="ext4" # Choose your filesystem (ext4, xfs, btrfs, etc.).
DRIVE_LABEL="new_drive_label" # Replace with the desired label for the drive.

# --- Functions ---

# Function to handle errors and exit
handle_error() {
  echo "Error: $1"
  exit 1
}

# --- Main Script ---

# 1. Verify the drive (CRITICAL!)
lsblk "$DRIVE" || handle_error "Drive $DRIVE not found. Double-check the drive name."
read -p "Are you absolutely sure you want to format and configure $DRIVE? (y/N) " confirm
if [[ "$confirm"!= "y" ]]; then
  echo "Aborting."
  exit 1
fi

# 2. Wipe the drive (if needed. Comment out if not needed)
echo "Wiping the drive..."
sudo wipefs -a "$DRIVE" || handle_error "Failed to wipe the drive."

# 3. Partition the drive (using gdisk for GPT. Change if you need MBR)
echo "Partitioning the drive..."
sudo gdisk "$DRIVE" << EOF
n  # New partition
1  # Partition number (default 1)
   # First sector (default)
   # Last sector or size (default - uses all space)
8300 # Linux filesystem type
w  # Write changes
y  # Confirm write
EOF

# 4. Format the partition
echo "Formatting the partition..."
PARTITION="${DRIVE}1" # Assumes one partition on the drive - adjust if needed
sudo mkfs."$FILESYSTEM" "$PARTITION" || handle_error "Failed to format the partition."

# 5. Set the label
echo "Setting label..."
sudo e2label "$PARTITION" "$DRIVE_LABEL" || handle_error "Failed to set label."

# 6. Create the mount point directory
echo "Creating the mount point directory..."
sudo mkdir -p "$MOUNT_POINT" || handle_error "Failed to create mount point directory."

# 7. Mount the partition
echo "Mounting the partition..."
sudo mount "$PARTITION" "$MOUNT_POINT" || handle_error "Failed to mount the partition."

# 8. Add to /etc/fstab
echo "Adding to /etc/fstab..."
UUID=$(sudo blkid -s UUID "$PARTITION" | cut -d '"' -f 2) || handle_error "Failed to get UUID."
echo "UUID=$UUID $MOUNT_POINT $FILESYSTEM defaults 0 2" | sudo tee -a /etc/fstab || handle_error "Failed to add to /etc/fstab."

# 9. Test the /etc/fstab entry
echo "Testing /etc/fstab entry..."
sudo mount -a || handle_error "Failed to mount using /etc/fstab. Check /etc/fstab for errors."

echo "Drive $DRIVE successfully configured."

exit 0
