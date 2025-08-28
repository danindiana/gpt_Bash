#!/bin/bash

# Clean Disk Speed Test Script - avoiding complex quoting issues
set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

TEST_SIZE_MB=1024
declare -a TEMP_FILES=()

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

select_mountpoint() {
    echo -e "${CYAN}Detecting available filesystems...${NC}"
    local -a mount_options=()
    local -a mount_points=()
    local -a device_names=()
    
    local lsblk_json
    if ! lsblk_json=$(lsblk -J -o NAME,MOUNTPOINT,SIZE,TYPE); then
        echo -e "${RED}Failed to execute lsblk.${NC}" >&2
        return 1
    fi
    
    # Create temp file for jq output
    local temp_file
    temp_file=$(mktemp)
    
    # Use jq to extract filesystem info - store filter in variable to avoid quote issues
    local filter_cmd
    filter_cmd='.. | select(type == "object" and has("mountpoint") and has("name") and has("size")) | select(.mountpoint != null and .mountpoint != "[SWAP]") | select(.type != "loop" or (.mountpoint | startswith("/snap/") | not)) | [.mountpoint, .name, .size] | @tsv'
    
    echo "$lsblk_json" | jq -r "$filter_cmd" | sort -u > "$temp_file"
    
    while IFS=$'\t' read -r mountpoint name size; do
        if [[ -z "$mountpoint" ]]; then
            continue
        fi
        mount_points+=("$mountpoint")
        device_names+=("$name")
        mount_options+=("'$mountpoint' ($name, $size)")
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    if [ ${#mount_options[@]} -eq 0 ]; then
        echo -e "${RED}No suitable filesystems found.${NC}" >&2
        return 1
    fi
    
    echo "Select a filesystem:"
    for i in "${!mount_options[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "${mount_options[$i]}"
    done
    echo "  q) Quit"
    
    local choice
    read -p "Enter choice [1-${#mount_options[@]}]: " choice
    
    case $choice in
        [qQ])
            echo "Exiting."
            exit 0
            ;;
        ''|*[!0-9]*)
            echo -e "${RED}Invalid input.${NC}" >&2
            return 1
            ;;
        *)
            if (( choice > 0 && choice <= ${#mount_options[@]} )); then
                MOUNT_POINT="${mount_points[$((choice-1))]}"
                DEVICE_NAME="${device_names[$((choice-1))]}"
            else
                echo -e "${RED}Invalid selection.${NC}" >&2
                return 1
            fi
            ;;
    esac
}

test_mountpoint() {
    local mountpoint="$1"
    local test_size="$2" 
    local device_name="$3"
    
    echo -e "\n${BLUE}--- Testing '$mountpoint' (on $device_name) ---${NC}"
    
    local sanitized_device_name
    sanitized_device_name="dev_$(echo "$device_name" | tr -c '[:alnum:]_.-' '_')"
    local test_file_path="$mountpoint/speedtest_${sanitized_device_name}.tmp"
    TEMP_FILES+=("$test_file_path")
    
    # Check space
    local available_space_kb
    available_space_kb=$(df -k --output=avail "$mountpoint" | tail -n 1)
    local available_space_mb=$((available_space_kb / 1024))
    
    if [ "$available_space_mb" -lt "$test_size" ]; then
        echo -e "${RED}Insufficient space: ${available_space_mb}MB available, ${test_size}MB needed${NC}" >&2
        return 1
    fi
    
    # Check permissions
    if [ ! -w "$mountpoint" ]; then
        echo -e "${RED}No write permission to '$mountpoint'${NC}" >&2
        echo "Try: sudo chown -R $USER:$USER '$mountpoint'" >&2
        return 1
    fi
    
    local test_touch_file="$mountpoint/.speedtest_permission_check.tmp"
    if ! touch "$test_touch_file" 2>/dev/null; then
        echo -e "${RED}Cannot create test file${NC}" >&2
        return 1
    fi
    rm -f "$test_touch_file"
    
    echo -e "${CYAN}Using test file: $test_file_path${NC}"
    
    # Write test
    echo -n "Sequential write: "
    local dd_output
    if ! dd_output=$(dd if=/dev/zero of="$test_file_path" bs=1M count=$test_size oflag=direct conv=fdatasync 2>&1); then
        echo -e "${RED}Write failed${NC}" >&2
        echo "$dd_output" >&2
        return 1
    fi
    local write_speed
    write_speed=$(echo "$dd_output" | grep 'bytes' | awk '{print $(NF-1) " " $NF}')
    if [[ -z "$write_speed" ]]; then
        echo -e "${RED}Failed to parse write speed${NC}" >&2
        return 1
    fi
    echo -e "${GREEN}${write_speed}${NC}"
    
    # Read test
    echo -n "Sequential read:  "
    if sudo -n true 2>/dev/null; then
        sync
        echo "3" | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1
        echo -e "${CYAN}(cache cleared)${NC}"
        echo -n "                  "
    else
        echo -e "${YELLOW}(no sudo - cache not cleared)${NC}"
        echo -n "                  "
    fi
    
    if ! dd_output=$(dd if="$test_file_path" of=/dev/null bs=1M count=$test_size iflag=direct 2>&1); then
        echo -e "${RED}Read failed${NC}" >&2
        echo "$dd_output" >&2
        return 1
    fi
    local read_speed
    read_speed=$(echo "$dd_output" | grep 'bytes' | awk '{print $(NF-1) " " $NF}')
    if [[ -z "$read_speed" ]]; then
        echo -e "${RED}Failed to parse read speed${NC}" >&2
        return 1
    fi
    echo -e "${GREEN}${read_speed}${NC}"
    
    # Random I/O test with fio
    local fio_test_file="${test_file_path}_fio"
    TEMP_FILES+=("$fio_test_file")
    
    echo -n "Random 4K writes: "
    
    # Try fio with JSON output first
    local fio_json
    if fio_json=$(fio --name=randwrite --filename="$fio_test_file" --size=256M --rw=randwrite --bs=4k --iodepth=64 --runtime=20 --direct=1 --group_reporting --output-format=json 2>/dev/null); then
        
        # Extract just the JSON object
        local json_line
        json_line=$(echo "$fio_json" | grep -E '^\{.*\}$' | head -n 1)
        
        if [[ -n "$json_line" ]] && echo "$json_line" | jq . >/dev/null 2>&1; then
            # JSON is valid - extract values using separate jq calls to avoid quoting issues
            local iops_raw
            local bw_raw
            iops_raw=$(echo "$json_line" | jq '.jobs[0].write.iops')
            bw_raw=$(echo "$json_line" | jq '.jobs[0].write.bw')
            
            # Check if we got valid numbers (not null)
            if [[ "$iops_raw" != "null" && "$bw_raw" != "null" ]]; then
                # Convert to integers
                local iops_int
                local bw_mb
                iops_int=$(echo "$iops_raw" | cut -d. -f1)
                bw_mb=$(( bw_raw / 1024 ))
                echo -e "${GREEN}${iops_int} IOPS, (${bw_mb} MB/s)${NC}"
            else
                echo -e "${YELLOW}JSON parsing failed - null values${NC}"
            fi
        else
            # JSON parsing failed, try human-readable output
            local fio_readable
            if fio_readable=$(fio --name=test --filename="$fio_test_file" --size=256M --rw=randwrite --bs=4k --iodepth=64 --runtime=20 --direct=1 2>/dev/null | grep 'write:'); then
                local iops_result
                iops_result=$(echo "$fio_readable" | grep -o 'IOPS=[0-9.]*[km]*' | sed 's/IOPS=//')
                echo -e "${GREEN}${iops_result} IOPS${NC}"
            else
                echo -e "${YELLOW}fio test failed${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}fio command failed${NC}"
    fi
}

main() {
    trap cleanup_on_exit EXIT
    check_dependencies
    
    echo -e "${GREEN}--- Disk Speed Test ---${NC}"
    echo "Host: $(hostname)"
    echo "Date: $(date)"
    echo
    
    if ! select_mountpoint; then
        exit 1
    fi
    
    if [ -n "$MOUNT_POINT" ]; then
        if test_mountpoint "$MOUNT_POINT" "$TEST_SIZE_MB" "$DEVICE_NAME"; then
            echo -e "\n${GREEN}--- Test Summary ---${NC}"
            echo -e "Test completed for '$MOUNT_POINT'"
        else
            echo -e "\n${RED}--- Test Summary ---${NC}"
            echo -e "Test failed for '$MOUNT_POINT'"
            exit 1
        fi
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
