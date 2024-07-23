#!/bin/bash

echo "Apache Tika & Python Venv Locator Script"
echo "-----------------------------------------"

# Function to recursively search for Apache Tika installations
find_tika() {
    local start_dir="$1"
    find "$start_dir" -type f \( -name "tika*" -o -name "tika-server*" \) 2>/dev/null
}

# Function to search for Python virtual environments related to Tika
find_venvs() {
    local start_dir="$1"
    find "$start_dir" -type d -name "venv" -exec test -f {}/bin/activate \; -print 2>/dev/null
}

# Get the parent directory from the user
read -p "Enter the parent directory to search in: " parent_dir

# Check if directory exists and is readable
if [[ ! -d "$parent_dir" || ! -r "$parent_dir" ]]; then
    echo "Error: Invalid or inaccessible directory."
    exit 1
fi

echo "Searching for Apache Tika installations in $parent_dir..."
tika_installs=$(find_tika "$parent_dir")

if [[ -z "$tika_installs" ]]; then
    echo "No Apache Tika installations found."
else
    echo "Found Apache Tika installations:"
    echo "$tika_installs"
fi

echo "Searching for related Python virtual environments in $parent_dir..."
venvs=$(find_venvs "$parent_dir")

if [[ -z "$venvs" ]]; then
    echo "No related Python virtual environments found."
else
    echo "Found related Python virtual environments:"
    echo "$venvs"
fi

echo "Done."
