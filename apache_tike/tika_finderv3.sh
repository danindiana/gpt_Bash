#!/bin/bash

echo "Tika Directory Locator Script"
echo "-----------------------------"

# Get the parent directory from the user (the mounted drive)
read -p "Enter the parent directory (mounted drive) to search in: " parent_dir

# Check if directory exists and is readable
if [[ ! -d "$parent_dir" || ! -r "$parent_dir" ]]; then
    echo "Error: Invalid or inaccessible directory."
    exit 1
fi

echo "Searching for Tika-related directories in $parent_dir..."

# Find all directories containing "tika" (case-insensitive) in their name or content
find "$parent_dir" -type d \( -iname "*tika*" \) -o \
    -exec grep -q -i "tika" {} \; -print 2>/dev/null 
    
echo "Done."
