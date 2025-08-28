# Disk Speed Test Script

A robust, safe, and user-friendly Bash script to test disk read/write performance with automatic cleanup of temporary files.

## Features

- ✅ **Interactive device selection** via mount point menu
- 📏 Tests:
  - Sequential write speed
  - Sequential read speed (uncached if `sudo` available)
  - Random 4K write IOPS using `fio`
- 🧹 **Automatic cleanup** of all test files on exit (even on `Ctrl+C`)
- 🔍 Pre-flight checks:
  - Available disk space
  - Write permissions
  - Required dependencies
- 🎨 Color-coded output for clarity
- 💾 Uses `direct` I/O to bypass cache and measure real disk performance

---

## Usage

Make the script executable and run it:

```bash
chmod +x disk_speed_test.sh
./disk_speed_test.sh


You'll be prompted to:

Select a mounted filesystem from a list.
Confirm the test (size: 1GB by default).
View results.

All temporary files are automatically deleted after testing.

How It Works
1. Safety & Setup
#!/bin/bash
set -o pipefail

Ensures the script runs in Bash.
set -o pipefail improves error detection in pipelines.
2. Color Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'  # No Color


Used for clear visual feedback in the terminal.

3. Configuration
TEST_SIZE_MB=1024
declare -a TEMP_FILES=()

Test file size: 1GB.
TEMP_FILES: Tracks all temporary files for cleanup.
Core Functions
cleanup_on_exit()

Ensures no test files are left behind, even if the script is interrupted.

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -gt 128 ]]; then
        echo -e "\n\n${YELLOW}--- Interruption detected, cleaning up ---${NC}"
    fi
    if [ ${#TEMP_FILES[@]} -gt 0 ]; then
        echo -e "${CYAN}Cleaning up temporary files...${NC}"
        for file in "${TEMP_FILES[@]}"; do
            echo -e "Deleting: ${file}"
            rm -f "$file"
        done
    fi
}


Installed via trap in main().

check_dependencies()

Verifies required tools are installed:

dd: For sequential I/O
fio: For random IOPS
lsblk: To list block devices
jq: To parse JSON output
check_dependencies() {
    local missing_deps=()
    local dependencies=("dd" "fio" "lsblk" "jq")
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required dependencies.${NC}" >&2
        echo "Please install: ${missing_deps[*]}" >&2
        exit 1
    fi
}

select_mountpoint()

Interactive menu to select a mounted filesystem:

Runs lsblk -J to get device info in JSON.
Uses jq to filter:
Mounted filesystems only
Excludes swap, loop, and /snap mounts
Builds a numbered menu.
Sets MOUNT_POINT and DEVICE_NAME.

Example output:

Select a filesystem:
  1) '/mnt/data' (sda1, 1T)
  2) '/home' (nvme0n1p2, 500G)
  q) Quit

test_mountpoint()

Performs the actual speed tests.

a. Test File Setup
sanitized_device_name="dev_$(echo "$device_name" | tr -c '[:alnum:]_.-' '_')"
test_file_path="$mountpoint/speedtest_${sanitized_device_name}.tmp"
TEMP_FILES+=("$test_file_path")

Sanitizes device name for safe filenames.
Adds to cleanup list.
b. Pre-Checks
Checks available space with df.
Tests write permission using touch.
c. Sequential Write Test
dd if=/dev/zero of="$test_file_path" bs=1M count=$test_size oflag=direct conv=fdatasync

oflag=direct: Bypasses cache.
conv=fdatasync: Ensures data is flushed to disk.

Parses output to extract speed (e.g., 113 MB/s).

d. Sequential Read Test
dd if="$test_file_path" of=/dev/null bs=1M count=$test_size iflag=direct

If sudo is available, clears cache first:
echo 3 | sudo tee /proc/sys/vm/drop_caches

→ Ensures uncached, real-world read speed.
e. Random 4K IOPS Test

Uses fio to simulate database-like workloads:

fio --name=randwrite --filename="$fio_test_file" --size=256M --rw=randwrite --bs=4k --iodepth=64 --runtime=20 --direct=1 --output-format=json

Falls back to human-readable output if JSON fails.
Parses IOPS and bandwidth using jq.

Example output: 2450 IOPS, (9 MB/s)

main() — Entry Point
main() {
    trap cleanup_on_exit EXIT
    check_dependencies
    echo -e "${GREEN}--- Disk Speed Test ---${NC}"
    echo "Host: $(hostname)"
    echo "Date: $(date)"
    echo
    select_mountpoint
    test_mountpoint "$MOUNT_POINT" "$TEST_SIZE_MB" "$DEVICE_NAME"
}


Only runs if script is executed directly:

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

Requirements

Install dependencies on Debian/Ubuntu:

sudo apt install fio jq


On CentOS/RHEL:

sudo yum install fio jq
# or
sudo dnf install fio jq
```
License: MIT. Feel free to use, modify, and distribute.
---

*Note: The key lessons learned were the importance of proper input validation, avoiding complex nested quoting in bash, and building in fallback mechanisms for tools that behave differently across systems.
