#!/bin/bash

# Function to execute the ss command with each option and store the output
execute_ss_commands() {
    local options=("$@")
    for opt in "${options[@]}"; do
        echo "Executing: ss $opt"
        ss $opt
        echo "---------------------"
    done
}

# Function to sort the options using bubble sort
bubble_sort() {
    local array=("$@")
    local n=${#array[@]}
    for (( i = 0; i < n-1; i++ )); do
        for (( j = 0; j < n-i-1; j++ )); do
            if [[ "${array[j]}" > "${array[$((j+1))]}" ]]; then
                # Swap
                temp=${array[j]}
                array[j]=${array[$((j+1))]}
                array[$((j+1))]=$temp
            fi
        done
    done
    echo "${array[@]}"
}

# Extract options from the ss command's help output
mapfile -t options < <(ss -h | grep -E '^\s+-' | awk '{print $1}' | tr -d ',')

# Sort the options
sorted_options=($(bubble_sort "${options[@]}"))

# Execute ss with each option
execute_ss_commands "${sorted_options[@]}"
