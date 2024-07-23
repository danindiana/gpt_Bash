#!/bin/bash

echo "Virtual Environment Activator Script"
echo "-------------------------------------"

# Set default parent directory 
default_dir=""
read -p "Enter the parent directory to search in (default: $default_dir): " parent_dir
parent_dir="${parent_dir:-$default_dir}" # Use default if empty

if [[ ! -d "$parent_dir" || ! -r "$parent_dir" ]]; then
    echo "Error: Invalid or inaccessible directory."
    exit 1
fi

# Find all virtual environment bin directories recursively
venv_bins=($(find "$parent_dir" -type d -name "bin" -path "*/venv/*" 2>/dev/null))

if [[ ${#venv_bins[@]} -eq 0 ]]; then
    echo "No virtual environments found."
    exit 0
fi

echo "Found the following virtual environments:"
PS3='Select a virtual environment to activate: '
select venv_bin in "${venv_bins[@]}" "None"; do
    if [[ $venv_bin == "None" ]]; then
        echo "No virtual environment selected."
        break  # Exit the script
    fi
    if [[ -f "$venv_bin/activate" ]]; then
        source "$venv_bin/activate"  # Activate the chosen environment
        echo "Activated virtual environment: $venv_bin"
        break  # Exit the script
    else
        echo "Invalid virtual environment."
    fi
done
