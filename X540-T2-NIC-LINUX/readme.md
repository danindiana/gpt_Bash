# Intel X540-T2 NIC Setup Guide - ixgbe Driver

## Command History Overview

The following bash commands were used to successfully configure the Intel X540-T2 NIC:

```bash
# Initial system checks
lspci
ip link show
sudo apt update
sudo apt upgrade
lspci -k -v
ethtool
sudo ethtool
sudo ethtool -h
ifconfig

# Check kernel messages for network interfaces
dmesg | grep -i "eth"
dmesg | grep -i ""
sudo dmesg | grep -i ""
htop
lspci
dmesg | grep -i "intel"
sudo dmesg | grep -i "intel"

# Network hardware detection
sudo lshw -C network
lsmod | grep ixgbe
dmesg | grep ixgbe
sudo dmesg | grep ixgbe
sudo modprobe ixgbe

# Driver compilation and installation
cd Downloads/
ls
tar zxf ixgbe-5.21.5.tar.gz
cd ixgbe-5.21.5/src/
make
sudo make install
sudo modprobe ixgbe
lsmod | grep ixgbe
ip link show

# System information gathering
sudo dmidecode -t bios
sudo dmidecode -t baseboard

# GRUB configuration
sudo subl /etc/default/grub
sudo update-grub
sudo reboot

# Post-reboot network configuration
ip link show
nmcli device
sudo systemctl restart networking
sudo systemctl status networking
ip route
ping 192.168.1.1

# Hardware probe and driver management
sudo -E hw-probe -all -upload
modprobe ixgbe
sudo modprobe ixgbe
lsmod | grep ixgbe
ip a

# Secure Boot key management
cd Downloads/
unzip intel-public-key-ixgbe-ko.zip
sudo cp intel-public-key-ixgbe-ko.rsa /usr/share/keys/ixgbe/
mv intel-public-key-ixgbe-ko.rsa intel_pubkey.pem
sudo cp intel_pubkey.pem /usr/share/keys/ixgbe/
sudo mkdir -p /usr/share/keys/ixgbe/
sudo cp intel_pubkey.pem /usr/share/keys/ixgbe/
sudo mokutil --import /usr/share/keys/ixgbe/intel_pubkey.pem
sudo reboot

# Final testing and verification
ip link show
speedtest
lsmod | grep ixgbe
ping 192.168.1.1
ip route
sudo systemctl status networking
nmcli device
dmesg | grep ixgbe
sudo dmesg | grep ixgbe
history
ip -s link
```

## Step-by-Step Setup Process

### 1. Initial System Checks and Updates

```bash
# Check PCI devices to identify the NIC
lspci

# Check network interfaces
ip link show

# Update system packages
sudo apt update
sudo apt upgrade

# Check kernel drivers in use
lspci -k -v
```

### 2. Identifying the NIC and Kernel Messages

```bash
# Check kernel messages for ethernet interfaces
dmesg | grep -i "eth"

# Look for Intel-specific messages
dmesg | grep -i "intel"

# Get detailed network hardware information
sudo lshw -C network
```

### 3. Loading the ixgbe Driver

```bash
# Check if ixgbe driver is loaded
lsmod | grep ixgbe

# Check kernel messages for ixgbe
dmesg | grep ixgbe

# Attempt to load the driver
sudo modprobe ixgbe
```

### 4. Compiling and Installing the ixgbe Driver

```bash
# Navigate to downloads directory
cd Downloads/

# Extract driver source code
tar zxf ixgbe-5.21.5.tar.gz

# Navigate to source directory
cd ixgbe-5.21.5/src/

# Compile the driver
make

# Install the compiled driver
sudo make install

# Load the newly installed driver
sudo modprobe ixgbe
```

### 5. Configuring the System

```bash
# Retrieve system information
sudo dmidecode -t bios
sudo dmidecode -t baseboard

# Edit GRUB configuration (if needed)
sudo nano /etc/default/grub

# Update GRUB configuration
sudo update-grub

# Reboot to apply changes
sudo reboot
```

### 6. Post-Reboot Network Configuration

```bash
# Check network interfaces after reboot
ip link show

# Restart networking service
sudo systemctl restart networking

# Check networking service status
sudo systemctl status networking

# Test network connectivity
ping 192.168.1.1
```

### 7. Handling Secure Boot

```bash
# Extract Intel public key
unzip intel-public-key-ixgbe-ko.zip

# Create directory for keys
sudo mkdir -p /usr/share/keys/ixgbe/

# Copy public key to appropriate location
sudo cp intel_pubkey.pem /usr/share/keys/ixgbe/

# Import key to Machine Owner Key (MOK) list
sudo mokutil --import /usr/share/keys/ixgbe/intel_pubkey.pem

# Reboot to enroll the new key
sudo reboot
```

### 8. Final Verification and Testing

```bash
# Check network interfaces
ip link show

# Test network speed
speedtest

# Check network statistics
ip -s link

# Verify driver is loaded
lsmod | grep ixgbe
```

## Driver Information

### modinfo ixgbe Output

```
filename:       /lib/modules/6.8.0-47-generic/updates/drivers/net/ethernet/intel/ixgbe/ixgbe.ko
version:        5.21.5
license:        GPL
description:    Intel(R) 10GbE PCI Express Linux Network Driver
author:         Intel Corporation, linux.nics@intel.com
srcversion:     BCFDD3C367E2C550724E8DA
alias:          pci:v00008086d000057B2sv*sd*bc*sc*i*
depends:        dca
retpoline:      Y
name:           ixgbe
vermagic:       6.8.0-47-generic SMP preempt mod_unload modversions
```

### Key Driver Parameters

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `IntMode` | Change Interrupt Mode | 2 | 0=Legacy, 1=MSI, 2=MSI-X |
| `InterruptType` | Change Interrupt Mode (deprecated) | IntMode | 0=Legacy, 1=MSI, 2=MSI-X |
| `MQ` | Multiple Queues | 1 | 0=disabled, 1=enabled |
| `DCA` | Direct Cache Access | 0 | 0=disabled, 1=descriptor only, 2=descriptor and data |
| `RSS` | Receive-Side Scaling Queues | 0 | 0=number of CPUs |
| `VMDQ` | Virtual Machine Device Queues | 8 | 0/1=disable, 2-16=enable |
| `max_vfs` | Virtual Functions | 0 | 0=disable, 1-63=enable |
| `VEPA` | VEPA Bridge Mode | 0 | 0=VEB, 1=VEPA |
| `InterruptThrottleRate` | Max interrupts per second | 1 | 0,1,956-488281 |
| `LRO` | Large Receive Offload | 0 | 0=off, 1=on |
| `allow_unsupported_sfp` | Allow unsupported SFP+ modules | 0 | 0=Disable, 1=Enable |
| `FCoE` | FCoE Offload | 1 | 0=disabled, 1=enabled |
| `MDD` | Malicious Driver Detection | 1 | 0=off, 1=on |
| `vxlan_rx` | VXLAN receive checksum offload | 1 | 0=disabled, 1=enabled |

## Driver Configuration

### Option 1: Permanent Settings via modprobe Configuration

```bash
# Create or edit the configuration file
sudo nano /etc/modprobe.d/ixgbe.conf

# Add desired options (example)
options ixgbe IntMode=2 InterruptType=2 MQ=1 DCA=1 LRO=1 allow_unsupported_sfp=1

# Reload the driver
sudo modprobe -r ixgbe
sudo modprobe ixgbe
```

### Option 2: Boot-time Configuration via GRUB

```bash
# Edit GRUB configuration
sudo nano /etc/default/grub

# Add parameters to GRUB_CMDLINE_LINUX_DEFAULT
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash ixgbe.IntMode=2 ixgbe.InterruptType=2 ixgbe.MQ=1 ixgbe.DCA=1 ixgbe.LRO=1 ixgbe.allow_unsupported_sfp=1"

# Update GRUB and reboot
sudo update-grub
sudo reboot
```

### Verifying Configuration

```bash
# Check applied parameters
cat /sys/module/ixgbe/parameters/<parameter_name>

# Example: Check interrupt mode
cat /sys/module/ixgbe/parameters/IntMode
```

## Manual Module Signing for Secure Boot

### 1. Generate Signing Key Pair

```bash
# Navigate to secure location
cd /root

# Generate key pair
openssl req -new -x509 -newkey rsa:2048 -keyout MOK.priv -outform DER -out MOK.der -nodes -days 36500 -subj "/CN=Module Signing Key"
```

### 2. Enroll Public Key

```bash
# Import public key
sudo mokutil --import MOK.der

# Reboot and complete enrollment through MOK Manager
sudo reboot
```

### 3. Sign the Module

```bash
# Sign the ixgbe module
sudo /usr/src/linux-headers-$(uname -r)/scripts/sign-file sha256 /root/MOK.priv /root/MOK.der /lib/modules/$(uname -r)/updates/drivers/net/ethernet/intel/ixgbe/ixgbe.ko
```

### 4. Verify Signature

```bash
# Check module signature
sudo modinfo ixgbe | grep sig
```

### 5. Load Signed Module

```bash
# Load the signed module
sudo modprobe ixgbe
```

## Performance Optimization Recommendations

### High-Performance Settings

```bash
# Recommended settings for high-performance workloads
echo "options ixgbe IntMode=2 MQ=1 RSS=0 DCA=1 InterruptThrottleRate=1" | sudo tee /etc/modprobe.d/ixgbe-performance.conf
```

### Low-Latency Settings

```bash
# Recommended settings for low-latency applications
echo "options ixgbe IntMode=2 MQ=1 RSS=0 InterruptThrottleRate=956 LLIPort=80 LLIPush=1" | sudo tee /etc/modprobe.d/ixgbe-latency.conf
```

## Troubleshooting

### Common Issues and Solutions

1. **Driver not loading**: Check if Secure Boot is enabled and sign the module
2. **Performance issues**: Adjust RSS, MQ, and interrupt throttling parameters
3. **SFP+ module not recognized**: Set `allow_unsupported_sfp=1`
4. **Virtual machine issues**: Configure VMDQ and max_vfs parameters

### Diagnostic Commands

```bash
# Check driver status
lsmod | grep ixgbe

# Check network interface status
ip link show

# Check kernel messages
dmesg | grep ixgbe

# Check network statistics
ip -s link

# Test network connectivity
ping -c 4 8.8.8.8

# Run network speed test
speedtest-cli
```

## Summary

This guide documents the successful installation and configuration of the Intel X540-T2 NIC using the ixgbe driver version 5.21.5 on Ubuntu 22.04. The process involves:

1. System identification and updates
2. Driver compilation and installation
3. Secure Boot key management
4. Performance optimization
5. Verification and testing

The Intel X540-T2 is now fully functional with optimized settings for high-performance networking.
