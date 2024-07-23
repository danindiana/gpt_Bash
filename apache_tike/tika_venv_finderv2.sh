#!/bin/bash

echo "Apache Tika & Python Venv Locator Script"
echo "-----------------------------------------"

find_tika() {
    local start_dir="$1"
    find "$start_dir" -type f \( -name "tika*" -o -name "tika-server*" \) 2>/dev/null
}

find_venvs() {
    local start_dir="$1"
    find "$start_dir" -type d -name "venv" -exec test -f {}/bin/activate \; -print 2>/dev/null
}

read -p "Enter the parent directory to search in: " parent_dir

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

# Find most recently used Tika installation and venv
newest_tika=""
newest_tika_time=0
for tika in $tika_installs; do
    tika_time=$(stat -c %Y "$tika")  
    if [[ $tika_time -gt $newest_tika_time ]]; then
        newest_tika=$tika
        newest_tika_time=$tika_time
    fi
done

if [[ -n "$newest_tika" ]]; then
    echo "Most recently used Tika installation:"
    echo "$newest_tika"

    # Find the venv in the same directory or a parent directory
    venv_dir=$(dirname "$newest_tika")
    while [[ $venv_dir != "/" ]]; do  
        if [[ -d "$venv_dir/venv" ]]; then
            echo "Associated virtual environment:"
            echo "$venv_dir/venv"
            break
        fi
        venv_dir=$(dirname "$venv_dir") 
    done
fi

echo "Done."
