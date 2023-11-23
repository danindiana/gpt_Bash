#!/bin/bash

# Define the source and target directories
SOURCE_DIR="/media/walter/7514e32b-65c9-4a64-a233-5db2311455f4/apache_org"
TARGET_DIR="/home/walter/Bsh_PostProcpdf_pdfmine_buk_QAULTITY"

# Ensure the target directory exists
mkdir -p "$TARGET_DIR"

# Get the total number of PDF files in the source directory
total_files=$(ls -1 "$SOURCE_DIR"/*.pdf | wc -l)
processed_files=0

# Iterate over each PDF in the source directory
for file in "$SOURCE_DIR"/*.pdf; do
    # Increment the processed files counter
    ((processed_files++))

    # Extract the filename without the extension
    filename=$(basename "$file" .pdf)

    # Use curl to send the file to Tika server and save the output
    curl -T "$file" http://localhost:9998/tika --header "Accept: text/plain" > "$TARGET_DIR/$filename.txt"

    # Display the progress
    echo "Processed $processed_files of $total_files files."
done

echo "Processing complete. $processed_files files processed."
