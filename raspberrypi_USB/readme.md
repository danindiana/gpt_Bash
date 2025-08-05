 two comprehensive scripts based on our troubleshooting experience:
Script 1: USB Boot Diagnostic Script
This script gathers all necessary information for USB boot setup:

System Analysis: Pi model, bootloader version, OTP status
Storage Layout: Current disk configuration and available USB devices
Boot Configuration: Analyzes config.txt and cmdline.txt files
Compatibility Check: Determines if full USB boot or hybrid boot is possible
Recommendations: Suggests the best approach based on your hardware

Key Features:

Detects USB boot capability and OTP status
Identifies suitable USB storage devices
Analyzes current boot configuration
Creates detailed report with recommendations
Handles both modern (/boot/firmware) and legacy (/boot) paths

Script 2: USB Boot Setup Script
This script performs the actual copying and configuration:

Strategy Selection: Chooses between full USB boot and hybrid boot
Automatic Partitioning: Creates appropriate partition layout
File Transfer: Copies all system files with proper exclusions
Configuration Updates: Updates fstab, cmdline.txt, and config.txt
Verification: Checks setup integrity before completion

Key Features:

Supports both full USB boot and hybrid boot strategies
Handles the OTP programming issue we encountered (falls back to hybrid)
Proper error handling and cleanup
Safety confirmations before destructive operations
Clear next steps based on chosen strategy

Usage

Run the diagnostic first:

bashsudo chmod +x usb_boot_diagnostic.sh
sudo ./usb_boot_diagnostic.sh

Review the report and then run setup:

bashsudo chmod +x usb_boot_setup.sh
sudo ./usb_boot_setup.sh
These scripts are designed to handle the real-world issues we encountered, including:

OTP programming failures (automatic fallback to hybrid boot)
Different config.txt locations
Proper PARTUUID handling
Both Pi 4 full USB boot and older model limitations

The scripts will guide you through the entire process safely, with multiple confirmation steps and detailed logging for troubleshooting if needed.
