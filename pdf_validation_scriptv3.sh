#!/bin/bash

read -p "Enter the path to the drive/directory you want to scan: " windows_path
input_directory=$(wslpath -u "$windows_path")

interval=1000  # Output progress every 1000 files
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
output_dir="${input_directory}/PDF_Validation_Output_${timestamp}"
log_file="Validation_Log_${timestamp}.txt"

mkdir -p "$output_dir"  # Create the output directory

echo "Scanning directory: $input_directory"
echo "Logging details to: $output_dir/$log_file"
echo

count=0
total_invalid=0
deleted_count=0

start_time=$(date +%s)

# Enable recursive globbing
shopt -s globstar 2>/dev/null

for pdf_file in "$input_directory"/**/*.pdf; do
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
