#!/bin/bash

# Raspberry Pi USB Boot Diagnostic Script
# Gathers all necessary information for USB boot setup
# Version: 1.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output files
LOG_FILE="/tmp/usb_boot_diagnostic.log"
REPORT_FILE="/tmp/usb_boot_report.txt"

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
}

info() {
    log "${BLUE}ℹ $1${NC}"
}

header() {
    log "\n${BLUE}=== $1 ===${NC}"
}

# Initialize log files
echo "USB Boot Diagnostic Report - $(date)" > "$REPORT_FILE"
echo "USB Boot Diagnostic Log - $(date)" > "$LOG_FILE"

header "Raspberry Pi USB Boot Diagnostic Tool"
info "This script analyzes your system for USB boot compatibility and setup"
info "Report will be saved to: $REPORT_FILE"
info "Detailed log will be saved to: $LOG_FILE"

# 1. System Information
header "1. System Information"

PI_MODEL=$(cat /proc/device-tree/model 2>/dev/null || echo "Unknown")
KERNEL_VERSION=$(uname -r)
OS_VERSION=$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)

log "Pi Model: $PI_MODEL"
log "Kernel: $KERNEL_VERSION"
log "OS: $OS_VERSION"

echo "Pi Model: $PI_MODEL" >> "$REPORT_FILE"
echo "Kernel: $KERNEL_VERSION" >> "$REPORT_FILE"
echo "OS: $OS_VERSION" >> "$REPORT_FILE"

# Determine USB boot compatibility
USB_BOOT_COMPATIBLE=false
case "$PI_MODEL" in
    *"Pi 4"*|*"Pi 400"*|*"Pi 3"*)
        USB_BOOT_COMPATIBLE=true
        success "Model supports USB booting"
        ;;
    *"Pi 2"*)
        if [[ "$PI_MODEL" == *"v1.2"* ]]; then
            USB_BOOT_COMPATIBLE=true
            success "Model supports USB booting (Pi 2 v1.2)"
        else
            warning "Model has limited USB boot support (Pi 2 v1.1 or earlier)"
        fi
        ;;
    *)
        error "Model does not support USB booting"
        ;;
esac

# 2. Bootloader Information
header "2. Bootloader Information"

if command -v vcgencmd &> /dev/null; then
    BOOTLOADER_VERSION=$(sudo rpi-eeprom-update 2>/dev/null | grep "CURRENT:" | head -1 | awk '{print $2, $3, $4, $5, $6, $7}')
    log "Bootloader Version: $BOOTLOADER_VERSION"
    echo "Bootloader Version: $BOOTLOADER_VERSION" >> "$REPORT_FILE"
    
    # Check OTP status
    OTP_STATUS=$(vcgencmd otp_dump | grep "17:" || echo "17:00000000")
    log "OTP Status: $OTP_STATUS"
    echo "OTP Status: $OTP_STATUS" >> "$REPORT_FILE"
    
    if [[ "$OTP_STATUS" == *"3020000a"* ]]; then
        success "USB boot is enabled in OTP"
        USB_BOOT_ENABLED=true
    else
        warning "USB boot is NOT enabled in OTP"
        USB_BOOT_ENABLED=false
    fi
else
    error "vcgencmd not available"
    USB_BOOT_ENABLED=false
fi

# 3. Current Storage Layout
header "3. Current Storage Layout"

log "Current disk layout:"
lsblk | tee -a "$LOG_FILE"

echo "" >> "$REPORT_FILE"
echo "=== Current Storage Layout ===" >> "$REPORT_FILE"
lsblk >> "$REPORT_FILE"

# Identify current boot and root devices
CURRENT_ROOT=$(findmnt -n -o SOURCE /)
CURRENT_BOOT=$(findmnt -n -o SOURCE /boot/firmware 2>/dev/null || findmnt -n -o SOURCE /boot)

log "Current root device: $CURRENT_ROOT"
log "Current boot device: $CURRENT_BOOT"

echo "Current root device: $CURRENT_ROOT" >> "$REPORT_FILE"
echo "Current boot device: $CURRENT_BOOT" >> "$REPORT_FILE"

# 4. Available USB Devices
header "4. Available USB Devices"

USB_DEVICES=$(lsblk -d -o NAME,SIZE,MODEL | grep -E "^sd" || echo "No USB storage devices found")
log "USB storage devices:"
log "$USB_DEVICES"

echo "" >> "$REPORT_FILE"
echo "=== Available USB Devices ===" >> "$REPORT_FILE"
echo "$USB_DEVICES" >> "$REPORT_FILE"

# Check for USB drives suitable for booting
SUITABLE_USB=""
while read -r line; do
    if [[ $line == sd* ]]; then
        DEVICE="/dev/$(echo $line | awk '{print $1}')"
        SIZE=$(echo $line | awk '{print $2}')
        if [[ -b "$DEVICE" ]]; then
            # Check if device is large enough (at least 4GB)
            SIZE_BYTES=$(blockdev --getsize64 "$DEVICE" 2>/dev/null || echo "0")
            SIZE_GB=$((SIZE_BYTES / 1024 / 1024 / 1024))
            if [[ $SIZE_GB -ge 4 ]]; then
                SUITABLE_USB="$SUITABLE_USB $DEVICE"
                success "Found suitable USB device: $DEVICE ($SIZE)"
            else
                warning "USB device too small: $DEVICE ($SIZE)"
            fi
        fi
    fi
done <<< "$USB_DEVICES"

if [[ -z "$SUITABLE_USB" ]]; then
    error "No suitable USB devices found (need at least 4GB)"
else
    log "Suitable USB devices:$SUITABLE_USB"
    echo "Suitable USB devices:$SUITABLE_USB" >> "$REPORT_FILE"
fi

# 5. Boot Configuration Analysis
header "5. Boot Configuration Analysis"

# Check for config.txt locations
CONFIG_LOCATIONS=("/boot/firmware/config.txt" "/boot/config.txt")
ACTIVE_CONFIG=""

for config in "${CONFIG_LOCATIONS[@]}"; do
    if [[ -f "$config" ]]; then
        SIZE=$(stat -c%s "$config")
        log "Found config.txt: $config (${SIZE} bytes)"
        if [[ $SIZE -gt 100 ]]; then
            ACTIVE_CONFIG="$config"
            success "Active config.txt: $config"
        fi
    fi
done

if [[ -n "$ACTIVE_CONFIG" ]]; then
    echo "" >> "$REPORT_FILE"
    echo "=== Active Config.txt ===" >> "$REPORT_FILE"
    echo "Location: $ACTIVE_CONFIG" >> "$REPORT_FILE"
    
    # Check for USB boot related settings
    if grep -q "program_usb_boot_mode" "$ACTIVE_CONFIG"; then
        warning "Found program_usb_boot_mode in config.txt"
        grep "program_usb_boot_mode" "$ACTIVE_CONFIG" | tee -a "$LOG_FILE"
    fi
    
    if grep -q "boot_order" "$ACTIVE_CONFIG"; then
        info "Found boot_order in config.txt"
        grep "boot_order" "$ACTIVE_CONFIG" | tee -a "$LOG_FILE"
    fi
else
    error "No active config.txt found"
fi

# Check cmdline.txt
CMDLINE_LOCATIONS=("/boot/firmware/cmdline.txt" "/boot/cmdline.txt")
ACTIVE_CMDLINE=""

for cmdline in "${CMDLINE_LOCATIONS[@]}"; do
    if [[ -f "$cmdline" ]]; then
        ACTIVE_CMDLINE="$cmdline"
        success "Found cmdline.txt: $cmdline"
        break
    fi
done

if [[ -n "$ACTIVE_CMDLINE" ]]; then
    log "Current cmdline.txt:"
    cat "$ACTIVE_CMDLINE" | tee -a "$LOG_FILE"
    echo "" >> "$REPORT_FILE"
    echo "=== Current cmdline.txt ===" >> "$REPORT_FILE"
    cat "$ACTIVE_CMDLINE" >> "$REPORT_FILE"
    
    # Extract current root PARTUUID
    CURRENT_ROOT_PARTUUID=$(grep -o "root=PARTUUID=[a-f0-9-]*" "$ACTIVE_CMDLINE" | cut -d'=' -f3)
    if [[ -n "$CURRENT_ROOT_PARTUUID" ]]; then
        log "Current root PARTUUID: $CURRENT_ROOT_PARTUUID"
        echo "Current root PARTUUID: $CURRENT_ROOT_PARTUUID" >> "$REPORT_FILE"
    fi
fi

# 6. PARTUUID Information
header "6. PARTUUID Information"

log "Current partition UUIDs:"
blkid | tee -a "$LOG_FILE"

echo "" >> "$REPORT_FILE"
echo "=== Partition UUIDs ===" >> "$REPORT_FILE"
blkid >> "$REPORT_FILE"

# 7. Free Space Analysis
header "7. Free Space Analysis"

log "Current filesystem usage:"
df -h | tee -a "$LOG_FILE"

echo "" >> "$REPORT_FILE"
echo "=== Filesystem Usage ===" >> "$REPORT_FILE"
df -h >> "$REPORT_FILE"

# Calculate space needed for transfer
ROOT_USAGE=$(df / | tail -1 | awk '{print $3}')
BOOT_USAGE=$(df /boot/firmware 2>/dev/null || df /boot | tail -1 | awk '{print $3}')

log "Space needed - Root: ${ROOT_USAGE}K, Boot: ${BOOT_USAGE}K"
echo "Space needed - Root: ${ROOT_USAGE}K, Boot: ${BOOT_USAGE}K" >> "$REPORT_FILE"

# 8. Recommendations
header "8. Recommendations"

echo "" >> "$REPORT_FILE"
echo "=== Recommendations ===" >> "$REPORT_FILE"

if [[ "$USB_BOOT_COMPATIBLE" == true ]]; then
    if [[ "$USB_BOOT_ENABLED" == true ]]; then
        success "Full USB boot is possible"
        echo "✓ Full USB boot is possible" >> "$REPORT_FILE"
        info "You can use full USB boot (remove SD card after setup)"
    else
        warning "USB boot hardware support available but not enabled"
        echo "⚠ USB boot hardware support available but not enabled" >> "$REPORT_FILE"
        info "Options:"
        info "1. Enable USB boot and use full USB boot"
        info "2. Use hybrid boot (boot from SD, root from USB)"
        echo "Options:" >> "$REPORT_FILE"
        echo "1. Enable USB boot and use full USB boot" >> "$REPORT_FILE"
        echo "2. Use hybrid boot (boot from SD, root from USB)" >> "$REPORT_FILE"
    fi
else
    warning "Full USB boot not supported on this model"
    echo "⚠ Full USB boot not supported on this model" >> "$REPORT_FILE"
    info "Recommendation: Use hybrid boot (boot from SD, root from USB)"
    echo "Recommendation: Use hybrid boot (boot from SD, root from USB)" >> "$REPORT_FILE"
fi

if [[ -n "$SUITABLE_USB" ]]; then
    success "Suitable USB storage devices found"
    echo "✓ Suitable USB storage devices found" >> "$REPORT_FILE"
else
    error "No suitable USB storage devices found"
    echo "✗ No suitable USB storage devices found" >> "$REPORT_FILE"
    info "Please connect a USB drive with at least 4GB capacity"
    echo "Please connect a USB drive with at least 4GB capacity" >> "$REPORT_FILE"
fi

# 9. Summary
header "9. Summary"

echo "" >> "$REPORT_FILE"
echo "=== Summary ===" >> "$REPORT_FILE"

if [[ "$USB_BOOT_COMPATIBLE" == true && "$USB_BOOT_ENABLED" == true && -n "$SUITABLE_USB" ]]; then
    success "System is ready for full USB boot setup"
    echo "✓ System is ready for full USB boot setup" >> "$REPORT_FILE"
elif [[ -n "$SUITABLE_USB" ]]; then
    success "System is ready for hybrid USB boot setup"
    echo "✓ System is ready for hybrid USB boot setup" >> "$REPORT_FILE"
else
    error "System is not ready for USB boot setup"
    echo "✗ System is not ready for USB boot setup" >> "$REPORT_FILE"
fi

# 10. Next Steps
header "10. Next Steps"

echo "" >> "$REPORT_FILE"
echo "=== Next Steps ===" >> "$REPORT_FILE"

if [[ -n "$SUITABLE_USB" ]]; then
    info "1. Review the diagnostic report: $REPORT_FILE"
    info "2. Run the USB boot setup script with your chosen target device"
    info "3. Available target devices:$SUITABLE_USB"
    
    echo "1. Review the diagnostic report: $REPORT_FILE" >> "$REPORT_FILE"
    echo "2. Run the USB boot setup script with your chosen target device" >> "$REPORT_FILE"
    echo "3. Available target devices:$SUITABLE_USB" >> "$REPORT_FILE"
    
    if [[ "$USB_BOOT_COMPATIBLE" == true && "$USB_BOOT_ENABLED" == false ]]; then
        info "4. Optional: Enable USB boot OTP for full USB boot capability"
        echo "4. Optional: Enable USB boot OTP for full USB boot capability" >> "$REPORT_FILE"
    fi
else
    info "1. Connect a suitable USB storage device (4GB or larger)"
    info "2. Run this diagnostic script again"
    echo "1. Connect a suitable USB storage device (4GB or larger)" >> "$REPORT_FILE"
    echo "2. Run this diagnostic script again" >> "$REPORT_FILE"
fi

header "Diagnostic Complete"
success "Report saved to: $REPORT_FILE"
success "Detailed log saved to: $LOG_FILE"

# Display report location for easy access
echo ""
info "To view the full report: cat $REPORT_FILE"
info "To view the detailed log: cat $LOG_FILE"
