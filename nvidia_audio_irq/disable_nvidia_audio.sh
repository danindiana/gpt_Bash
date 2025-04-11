#!/bin/bash

# NVIDIA Audio Disabler Script
# Purpose: Disables NVIDIA GPU audio controllers while preserving AMD audio
# Run with sudo or as root

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Try using sudo."
    exit 1
fi

echo "=== NVIDIA Audio Controller Disabler ==="
echo "This script will:"
echo "1. Stop PulseAudio services"
echo "2. Blacklist NVIDIA audio modules"
echo "3. Configure system to skip NVIDIA audio devices"
echo "4. Update initramfs"
echo "5. Reboot the system (optional)"
echo ""

# Step 1: Stop audio services
echo "[1/5] Stopping audio services..."
systemctl --user stop pulseaudio.socket 2>/dev/null
systemctl --user stop pulseaudio.service 2>/dev/null
pkill -9 pulseaudio 2>/dev/null

# Step 2: Create blacklist file
echo "[2/5] Creating blacklist configuration..."
cat > /etc/modprobe.d/blacklist-nvidia-audio.conf <<EOF
# Disable NVIDIA HDMI audio controllers
blacklist snd_hda_codec_nvidia
options snd-hda-intel enable=0,0 index=-2
EOF

# Step 3: Prevent module loading
echo "[3/5] Preventing module auto-load..."
echo "snd_hda_codec_nvidia" > /etc/modules-load.d/disable-nvidia-audio.conf

# Step 4: Update initramfs
echo "[4/5] Updating initramfs (ignore AMD firmware warnings)..."
update-initramfs -u

# Verification
echo ""
echo "=== Verification ==="
echo "NVIDIA audio devices should show no driver after reboot:"
lspci -nn | grep -i "nvidia.*audio"

# Step 5: Reboot prompt
echo ""
read -p "[5/5] Reboot now to apply changes? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Rebooting system..."
    reboot
else
    echo "Please reboot manually for changes to take effect."
fi

echo "Script complete."
