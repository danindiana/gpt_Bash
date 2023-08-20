#!/bin/bash

input_directory="/mnt/your-drive-letterk/a-directory-or-top-level"  # Replace with the path to your input directory
interval=1000  # Output progress every 1000 files
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
output_dir="/mnt/k/PDF_Validation_Output_${timestamp}"
log_file="Validation_Log_${timestamp}.txt"

mkdir -p "$output_dir"  # Create the output directory

echo "Scanning directory: $input_directory"
echo "Logging details to: $output_dir/$log_file"
echo

count=0
total_invalid=0
deleted_count=0

start_time=$(date +%s)

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win"* ]]; then
    # Get a list of attached disks on Windows
    disks=($(wmic logicaldisk get caption | grep -E '^[A-Z]:' | awk '{print $1}'))
    echo "Attached disks on Windows:"
    for disk in "${disks[@]}"; do
        echo "$disk"
    done
    echo
fi

find "$input_directory" -type f -name "*.pdf" | while read -r pdf_file; do
    if [ $((count % interval)) -eq 0 ]; then
        if [ $count -gt 0 ]; then
            current_time=$(date +%s)
            elapsed_time=$((current_time - start_time))
            estimated_completion=$((elapsed_time * (total_files - count) / count))
        fi

        echo "Processed: $count files"
        echo "Invalid PDFs found: $total_invalid"
        echo "Files deleted: $deleted_count"
        echo "Last processed file: $pdf_file"
        if [ $count -gt 0 ]; then
            echo "Estimated time to completion: $estimated_completion seconds"
        fi
        echo
        echo "Processed: $count files" >> "$output_dir/$log_file"
        echo "Invalid PDFs found: $total_invalid" >> "$output_dir/$log_file"
        echo "Files deleted: $deleted_count" >> "$output_dir/$log_file"
        echo "Last processed file: $pdf_file" >> "$output_dir/$log_file"
        if [ $count -gt 0 ]; then
            echo "Estimated time to completion: $estimated_completion seconds" >> "$output_dir/$log_file"
        fi
    fi

    echo "Examining file: $pdf_file"
    pdfinfo "$pdf_file" &> /dev/null
    if [ $? -ne 0 ]; then
        rm "$pdf_file"
        echo "Deleted corrupted or invalid PDF: $pdf_file"
        echo "Deleted corrupted or invalid PDF: $pdf_file" >> "$output_dir/$log_file"
        total_invalid=$((total_invalid + 1))
        deleted_count=$((deleted_count + 1))
    fi

    count=$((count + 1))
done

end_time=$(date +%s)
total_files=$((count))

echo
echo "Scan complete."
echo "Processed: $count files"
echo "Invalid PDFs found: $total_invalid"
echo "Files deleted: $deleted_count"
echo "Time taken: $((end_time - start_time)) seconds"
echo "Output saved to: $output_dir"
