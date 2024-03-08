#!/bin/sh
# Filename: find_git_repositories.sh

# Display the current directory
echo "Searching in: $(pwd)"

# Start the find command recursively using 'exec' flag for speeding up search times,
# then pipe its results into parallel tool which in turn executes `awk` commands against them.
find . -type d -name .git -exec bash -c 'echo "$(basename $(dirname "{}")): $(stat "$(dirname "{}")")"' \; | parallel --pipe "awk '{print \$0}'"
