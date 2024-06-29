#!/bin/bash

# Target directory for symlinks
SYMLINK_DIR=~/.ollama/models/linked

# Function to create a symlink
create_symlink() {
    file_path=$1
    file_name=$(basename "$file_path")
    ln -s "$file_path" "$SYMLINK_DIR/$file_name"
    echo "Created symlink for: $file_path"
}

# Ensure target directory exists
mkdir -p "$SYMLINK_DIR"

# Main loop
while true; do
    echo -n "Paste file path (or type 'done' to finish): "
    read file_path

    # Check for exit condition
    if [ "$file_path" == "done" ]; then
        break
    fi

    # Validate file path
    if [ ! -f "$file_path" ]; then
        echo "Error: File not found: $file_path"
    else
        # Create symlink if file exists
        create_symlink "$file_path"
    fi
done

echo "All symlinks created."
