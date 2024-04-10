#!/bin/bash

# Function to process a single script
process_script() {
  echo "------------------------------------"
  echo "Analyzing script: $1"
  echo "------------------------------------"

  # Chunk size (adjust as needed)
  CHUNK_SIZE=10 

  # Break the script into chunks
  cat $1 | split -l $CHUNK_SIZE - chunk_

  # Analyze each chunk
  for chunk_file in chunk_*; do
    echo "\n--- Chunk Start ---"
    cat $chunk_file
    echo "--- Chunk End ---\n"

    # Ask for insights
    read -p "Summarize the purpose of this chunk (one sentence): " summary
    echo "Noted: $summary" 

    rm $chunk_file  # Clean up the chunk file
  done

  # Suggest a new name (very basic for now)
  echo "\nBased on your input, a possible new name: combined_purpose.sh" 
  read -p "Enter a better name, or press Enter to keep the original: " new_name

  if [ ! -z "$new_name" ]; then
    mv $1 $new_name
    echo "Script renamed to $new_name"
  fi
}

# Check for script arguments
if [ $# -eq 0 ]; then
    echo "Please provide one or more script files as arguments."
    exit 1
fi

# Process each script
for script_file in "$@"; do
  process_script $script_file
done
