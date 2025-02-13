This Bash script is designed to format, mount, and configure a drive for automatic mounting on boot. Below is a step-by-step explanation of how the script works:

---

### **1. Configuration Section**
```bash
DRIVE="/dev/sdX"  # Replace /dev/sdX with the actual drive name (e.g., /dev/sdd, /dev/sde).  BE VERY CAREFUL HERE!
MOUNT_POINT="/mnt/new_drive" # Replace with your desired mount point (e.g., /media/new_drive, /data/new_drive).
FILESYSTEM="ext4" # Choose your filesystem (ext4, xfs, btrfs, etc.).
DRIVE_LABEL="new_drive_label" # Replace with the desired label for the drive.
```
- **`DRIVE`**: Specifies the drive to be formatted and configured (e.g., `/dev/sdb`).
- **`MOUNT_POINT`**: Specifies the directory where the drive will be mounted.
- **`FILESYSTEM`**: Specifies the filesystem type to be used (e.g., `ext4`).
- **`DRIVE_LABEL`**: Specifies the label to be assigned to the drive.

**Note**: These variables must be modified by the user before running the script.

---

### **2. Error Handling Function**
```bash
handle_error() {
  echo "Error: $1"
  exit 1
}
```
- This function is used to handle errors. If an error occurs, it prints an error message and exits the script with a non-zero status.

---

### **3. Main Script**

#### **Step 1: Verify the Drive**
```bash
lsblk "$DRIVE" || handle_error "Drive $DRIVE not found. Double-check the drive name."
read -p "Are you absolutely sure you want to format and configure $DRIVE? (y/N) " confirm
if [[ "$confirm" != "y" ]]; then
  echo "Aborting."
  exit 1
fi
```
- The script uses `lsblk` to verify that the specified drive exists.
- It then prompts the user to confirm the operation. If the user does not enter `y`, the script aborts.

#### **Step 2: Wipe the Drive (Optional)**
```bash
echo "Wiping the drive..."
sudo wipefs -a "$DRIVE" || handle_error "Failed to wipe the drive."
```
- This step wipes all filesystem signatures from the drive using `wipefs`. This is optional and can be commented out if not needed.

#### **Step 3: Partition the Drive**
```bash
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
```
- The script uses `gdisk` to create a new GPT partition on the drive. It creates a single partition using the entire drive space and sets the partition type to `8300` (Linux filesystem).

#### **Step 4: Format the Partition**
```bash
echo "Formatting the partition..."
PARTITION="${DRIVE}1" # Assumes one partition on the drive - adjust if needed
sudo mkfs."$FILESYSTEM" "$PARTITION" || handle_error "Failed to format the partition."
```
- The script formats the newly created partition (`/dev/sdX1`) with the specified filesystem (e.g., `ext4`).

#### **Step 5: Set the Label**
```bash
echo "Setting label..."
sudo e2label "$PARTITION" "$DRIVE_LABEL" || handle_error "Failed to set label."
```
- The script assigns a label to the partition using `e2label`. This step assumes the filesystem supports labels (e.g., `ext4`).

#### **Step 6: Create the Mount Point Directory**
```bash
echo "Creating the mount point directory..."
sudo mkdir -p "$MOUNT_POINT" || handle_error "Failed to create mount point directory."
```
- The script creates the directory specified in `MOUNT_POINT` if it does not already exist.

#### **Step 7: Mount the Partition**
```bash
echo "Mounting the partition..."
sudo mount "$PARTITION" "$MOUNT_POINT" || handle_error "Failed to mount the partition."
```
- The script mounts the formatted partition to the specified mount point.

#### **Step 8: Add to `/etc/fstab`**
```bash
echo "Adding to /etc/fstab..."
UUID=$(sudo blkid -s UUID "$PARTITION" | cut -d '"' -f 2) || handle_error "Failed to get UUID."
echo "UUID=$UUID $MOUNT_POINT $FILESYSTEM defaults 0 2" | sudo tee -a /etc/fstab || handle_error "Failed to add to /etc/fstab."
```
- The script retrieves the UUID of the partition using `blkid`.
- It then adds an entry to `/etc/fstab` to ensure the partition is automatically mounted on boot.

#### **Step 9: Test the `/etc/fstab` Entry**
```bash
echo "Testing /etc/fstab entry..."
sudo mount -a || handle_error "Failed to mount using /etc/fstab. Check /etc/fstab for errors."
```
- The script tests the `/etc/fstab` entry by attempting to mount all filesystems listed in `/etc/fstab`.

---

### **4. Completion**
```bash
echo "Drive $DRIVE successfully configured."
exit 0
```
- If all steps complete successfully, the script prints a success message and exits with a status of `0`.

---

### **Key Notes**
- **Caution**: This script is destructive. It wipes and formats the specified drive, so ensure the correct drive is specified.
- **Customization**: Modify the configuration section at the top of the script to suit your needs.
- **Compatibility**: The script assumes a GPT partition table and uses `gdisk`. If you need MBR, replace `gdisk` with `fdisk` and adjust the commands accordingly.


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
