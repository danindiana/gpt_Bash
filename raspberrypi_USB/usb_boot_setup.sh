#!/bin/bash

# Raspberry Pi USB Boot Setup Script
# Copies OS/files to USB storage and configures boot
# Version: 1.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
MOUNT_ROOT="/mnt/usb_target_root"
MOUNT_BOOT="/mnt/usb_target_boot"
LOG_FILE="/tmp/usb_boot_setup.log"

# Functions
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

success() {
    log "${GREEN}✓ $1${NC}"
}

warning() {
    log "${YELLOW}⚠ $1${NC}"
}

error() {
    log "${RED}✗ $1${NC}"
    exit 1
}

info() {
    log "${BLUE}ℹ $1${NC}"
}

header() {
    log "\n${CYAN}=== $1 ===${NC}"
}

confirm() {
    read -p "$(echo -e "${YELLOW}$1 (y/N): ${NC}")" -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Cleanup function
cleanup() {
    log "\nCleaning up..."
    umount "$MOUNT_ROOT" 2>/dev/null || true
    umount "$MOUNT_BOOT" 2>/dev/null || true
    rmdir "$MOUNT_ROOT" 2>/dev/null || true
    rmdir "$MOUNT_BOOT" 2>/dev/null || true
}

# Set up cleanup trap
trap cleanup EXIT

# Initialize
echo "USB Boot Setup Log - $(date)" > "$LOG_FILE"

header "Raspberry Pi USB Boot Setup Tool"
warning "⚠ WARNING: This script will completely erase the target USB drive!"
warning "⚠ ALL DATA on the target device will be PERMANENTLY LOST!"

# Check prerequisites
check_root

# 1. System Analysis
header "1. System Analysis"

PI_MODEL=$(cat /proc/device-tree/model 2>/dev/null || echo "Unknown")
info "Pi Model: $PI_MODEL"

# Check USB boot capability
USB_BOOT_SUPPORTED=false
case "$PI_MODEL" in
    *"Pi 4"*|*"Pi 400"*|*"Pi 3"*)
        USB_BOOT_SUPPORTED=true
        ;;
    *"Pi 2"*)
        if [[ "$PI_MODEL" == *"v1.2"* ]]; then
            USB_BOOT_SUPPORTED=true
        fi
        ;;
esac

# Check OTP status
USB_BOOT_ENABLED=false
if command -v vcgencmd &> /dev/null; then
    OTP_STATUS=$(vcgencmd otp_dump | grep "17:" || echo "17:00000000")
    if [[ "$OTP_STATUS" == *"3020000a"* ]]; then
        USB_BOOT_ENABLED=true
        success "USB boot is enabled in hardware"
    else
        warning "USB boot is not enabled in hardware"
    fi
fi

# Determine boot strategy
if [[ "$USB_BOOT_SUPPORTED" == true && "$USB_BOOT_ENABLED" == true ]]; then
    info "Full USB boot is available"
    BOOT_STRATEGY="full"
else
    info "Will use hybrid boot (boot from SD, root from USB)"
    BOOT_STRATEGY="hybrid"
fi

# 2. Target Device Selection
header "2. Target Device Selection"

# List available USB devices
info "Available USB storage devices:"
lsblk -d -o NAME,SIZE,MODEL | grep -E "^sd" || error "No USB storage devices found"

echo ""
read -p "Enter target device (e.g., sda): " TARGET_DEVICE

if [[ ! "$TARGET_DEVICE" =~ ^sd[a-z]$ ]]; then
    error "Invalid device name. Use format like 'sda', 'sdb', etc."
fi

TARGET_PATH="/dev/$TARGET_DEVICE"

if [[ ! -b "$TARGET_PATH" ]]; then
    error "Device $TARGET_PATH not found"
fi

# Display device info
info "Target device: $TARGET_PATH"
lsblk "$TARGET_PATH"

# 3. Boot Strategy Confirmation
header "3. Boot Strategy Selection"

if [[ "$BOOT_STRATEGY" == "full" ]]; then
    info "Available boot strategies:"
    info "1. Full USB Boot (recommended) - Boot and root on USB, SD card not needed"
    info "2. Hybrid Boot - Boot on SD card, root on USB"
    echo ""
    read -p "Choose strategy (1 or 2): " STRATEGY_CHOICE
    
    case "$STRATEGY_CHOICE" in
        1)
            BOOT_STRATEGY="full"
            info "Selected: Full USB Boot"
            ;;
        2)
            BOOT_STRATEGY="hybrid"
            info "Selected: Hybrid Boot"
            ;;
        *)
            error "Invalid choice"
            ;;
    esac
else
    info "Using: Hybrid Boot (full USB boot not available)"
fi

# 4. Final Confirmation
header "4. Final Confirmation"

warning "⚠ FINAL WARNING ⚠"
warning "This will:"
warning "- Completely erase $TARGET_PATH"
warning "- Create new partitions on $TARGET_PATH"

if [[ "$BOOT_STRATEGY" == "full" ]]; then
    warning "- Copy entire system to USB drive"
    warning "- Configure for full USB boot"
    warning "- SD card will not be needed after setup"
else
    warning "- Copy root filesystem to USB drive"
    warning "- Configure hybrid boot (boot from SD, root from USB)"
    warning "- SD card must remain inserted"
fi

if ! confirm "Continue with USB boot setup?"; then
    info "Setup cancelled"
    exit 0
fi

# 5. Partition Setup
header "5. Setting Up Partitions"

info "Creating partition table on $TARGET_PATH..."

# Unmount any existing partitions
for part in ${TARGET_PATH}*; do
    if [[ -b "$part" && "$part" != "$TARGET_PATH" ]]; then
        umount "$part" 2>/dev/null || true
    fi
done

# Create GPT partition table
parted -s "$TARGET_PATH" mklabel gpt

if [[ "$BOOT_STRATEGY" == "full" ]]; then
    # Full USB boot: create boot + root partitions
    info "Creating boot partition (512MB, FAT32)..."
    parted -s "$TARGET_PATH" mkpart primary fat32 1MiB 513MiB
    parted -s "$TARGET_PATH" set 1 boot on
    
    info "Creating root partition (remaining space, ext4)..."
    parted -s "$TARGET_PATH" mkpart primary ext4 513MiB 100%
    
    BOOT_PARTITION="${TARGET_PATH}1"
    ROOT_PARTITION="${TARGET_PATH}2"
else
    # Hybrid boot: only create root partition
    info "Creating root partition (full device, ext4)..."
    parted -s "$TARGET_PATH" mkpart primary ext4 1MiB 100%
    
    BOOT_PARTITION=""
    ROOT_PARTITION="${TARGET_PATH}1"
fi

# Wait for partition table to be re-read
sleep 2
partprobe "$TARGET_PATH"
sleep 2

# 6. Format Partitions
header "6. Formatting Partitions"

if [[ -n "$BOOT_PARTITION" ]]; then
    info "Formatting boot partition as FAT32..."
    mkfs.vfat -F 32 -n "BOOT" "$BOOT_PARTITION"
fi

info "Formatting root partition as ext4..."
mkfs.ext4 -F -L "rootfs" "$ROOT_PARTITION"

# 7. Mount Partitions
header "7. Mounting Partitions"

mkdir -p "$MOUNT_ROOT"
mount "$ROOT_PARTITION" "$MOUNT_ROOT"
success "Mounted root partition"

if [[ -n "$BOOT_PARTITION" ]]; then
    mkdir -p "$MOUNT_BOOT"
    mount "$BOOT_PARTITION" "$MOUNT_BOOT"
    success "Mounted boot partition"
fi

# 8. Copy Files
header "8. Copying System Files"

info "This may take 10-20 minutes depending on your system size..."

# Copy root filesystem
info "Copying root filesystem..."
if [[ "$BOOT_STRATEGY" == "full" ]]; then
    # Full boot: exclude /boot/firmware from root copy
    rsync -axHAWX --numeric-ids --info=progress2 \
        --exclude=/boot/firmware \
        --exclude=/dev \
        --exclude=/proc \
        --exclude=/sys \
        --exclude=/tmp \
        --exclude=/run \
        --exclude=/mnt \
        --exclude=/media \
        / "$MOUNT_ROOT/"
else
    # Hybrid boot: exclude /boot from root copy
    rsync -axHAWX --numeric-ids --info=progress2 \
        --exclude=/boot \
        --exclude=/dev \
        --exclude=/proc \
        --exclude=/sys \
        --exclude=/tmp \
        --exclude=/run \
        --exclude=/mnt \
        --exclude=/media \
        / "$MOUNT_ROOT/"
fi

success "Root filesystem copied"

# Copy boot files if full USB boot
if [[ "$BOOT_STRATEGY" == "full" ]]; then
    info "Copying boot files..."
    BOOT_SOURCE="/boot/firmware"
    if [[ ! -d "$BOOT_SOURCE" ]]; then
        BOOT_SOURCE="/boot"
    fi
    
    rsync -axHAWX --numeric-ids --info=progress2 \
        "$BOOT_SOURCE/" "$MOUNT_BOOT/"
    
    success "Boot files copied"
fi

# 9. Get Partition UUIDs
header "9. Getting Partition Information"

ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_PARTITION")
success "Root PARTUUID: $ROOT_PARTUUID"

if [[ -n "$BOOT_PARTITION" ]]; then
    BOOT_PARTUUID=$(blkid -s PARTUUID -o value "$BOOT_PARTITION")
    success "Boot PARTUUID: $BOOT_PARTUUID"
fi

# 10. Update Configuration Files
header "10. Updating Configuration Files"

if [[ "$BOOT_STRATEGY" == "full" ]]; then
    # Full USB boot configuration
    
    # Update fstab on USB drive
    info "Updating fstab for full USB boot..."
    cat > "$MOUNT_ROOT/etc/fstab" << EOF
proc            /proc           proc    defaults          0       0
PARTUUID=$BOOT_PARTUUID  /boot/firmware  vfat    defaults          0       2
PARTUUID=$ROOT_PARTUUID  /               ext4    defaults,noatime  0       1
EOF
    
    # Update cmdline.txt on USB drive
    info "Updating cmdline.txt for full USB boot..."
    CMDLINE_FILE="$MOUNT_BOOT/cmdline.txt"
    if [[ -f "$CMDLINE_FILE" ]]; then
        # Update existing cmdline.txt
        sed -i "s/root=PARTUUID=[a-f0-9-]*/root=PARTUUID=$ROOT_PARTUUID/" "$CMDLINE_FILE"
    else
        # Create new cmdline.txt
        echo "console=serial0,115200 console=tty1 root=PARTUUID=$ROOT_PARTUUID rootfstype=ext4 fsck.repair=yes rootwait" > "$CMDLINE_FILE"
    fi
    
    # Update config.txt for USB boot order
    CONFIG_FILE="$MOUNT_BOOT/config.txt"
    if ! grep -q "boot_order" "$CONFIG_FILE"; then
        echo "" >> "$CONFIG_FILE"
        echo "# USB Boot Configuration" >> "$CONFIG_FILE"
        echo "boot_order=0xf15" >> "$CONFIG_FILE"
    fi
    
    success "Full USB boot configuration updated"
    
else
    # Hybrid boot configuration
    
    # Update fstab on USB drive (keep boot pointing to SD card)
    info "Updating fstab for hybrid boot..."
    
    # Get current boot PARTUUID from SD card
    CURRENT_BOOT_PARTUUID=$(blkid -s PARTUUID -o value /dev/mmcblk0p1)
    
    cat > "$MOUNT_ROOT/etc/fstab" << EOF
proc            /proc           proc    defaults          0       0
PARTUUID=$CURRENT_BOOT_PARTUUID  /boot/firmware  vfat    defaults          0       2
PARTUUID=$ROOT_PARTUUID  /               ext4    defaults,noatime  0       1
EOF
    
    # Update cmdline.txt on SD card
    info "Updating cmdline.txt on SD card for hybrid boot..."
    SD_CMDLINE="/boot/firmware/cmdline.txt"
    if [[ ! -f "$SD_CMDLINE" ]]; then
        SD_CMDLINE="/boot/cmdline.txt"
    fi
    
    if [[ -f "$SD_CMDLINE" ]]; then
        cp "$SD_CMDLINE" "$SD_CMDLINE.backup"
        sed -i "s/root=PARTUUID=[a-f0-9-]*/root=PARTUUID=$ROOT_PARTUUID/" "$SD_CMDLINE"
        success "SD card cmdline.txt updated"
    else
        error "Could not find cmdline.txt on SD card"
    fi
    
    success "Hybrid boot configuration updated"
fi

# 11. Create Required Directories
header "11. Creating System Directories"

for dir in dev proc sys tmp run mnt media; do
    mkdir -p "$MOUNT_ROOT/$dir"
done

success "System directories created"

# 12. Final Verification
header "12. Final Verification"

info "Verifying setup..."

# Check critical files exist
CRITICAL_FILES=("/etc/fstab" "/etc/passwd" "/bin/bash")
for file in "${CRITICAL_FILES[@]}"; do
    if [[ -f "$MOUNT_ROOT$file" ]]; then
        success "Found: $file"
    else
        error "Missing critical file: $file"
    fi
done

if [[ "$BOOT_STRATEGY" == "full" ]]; then
    BOOT_FILES=("config.txt" "cmdline.txt" "start.elf")
    for file in "${BOOT_FILES[@]}"; do
        if [[ -f "$MOUNT_BOOT/$file" ]]; then
            success "Found boot file: $file"
        else
            warning "Missing boot file: $file"
        fi
    done
fi

# Show final configuration
info "Final configuration:"
if [[ "$BOOT_STRATEGY" == "full" ]]; then
    log "  Boot: $BOOT_PARTITION (PARTUUID=$BOOT_PARTUUID)"
fi
log "  Root: $ROOT_PARTITION (PARTUUID=$ROOT_PARTUUID)"

# 13. Cleanup and Instructions
header "13. Setup Complete"

# Unmount partitions
umount "$MOUNT_ROOT"
if [[ -n "$BOOT_PARTITION" ]]; then
    umount "$MOUNT_BOOT"
fi

success "USB boot setup completed successfully!"

header "Next Steps"

if [[ "$BOOT_STRATEGY" == "full" ]]; then
    info "Full USB Boot Setup Complete:"
    info "1. Shutdown the Pi: sudo shutdown -h now"
    info "2. Remove the SD card"
    info "3. Power on the Pi - it will boot from USB"
    info "4. Verify with: lsblk"
    warning "Note: Keep the SD card as a backup!"
    
else
    info "Hybrid Boot Setup Complete:"
    info "1. Reboot the Pi: sudo reboot"
    info "2. Keep the SD card inserted"
    info "3. Verify with: lsblk"
    info "   - Boot should be on mmcblk0p1"
    info "   - Root should be on ${TARGET_DEVICE}1"
    warning "Note: SD card must remain inserted for boot!"
fi

info "Setup log saved to: $LOG_FILE"

success "🎉 USB boot setup completed successfully!"
