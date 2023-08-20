#!/usr/bin/env python3

import os
import subprocess
import glob

# Function to process PDF files
def process_pdf(pdf_file):
    pdfinfo_process = subprocess.run(["pdfinfo", pdf_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return pdfinfo_process.returncode != 0

# Function to recursively scan for PDF files and process them
def scan_and_process(directory):
    count = 0
    total_invalid = 0
    deleted_count = 0
    
    print(f"Scanning directory: {directory}\n")
    
    for pdf_file in glob.iglob(os.path.join(directory, "**", "*.pdf"), recursive=True):
        count += 1
        if process_pdf(pdf_file):
            os.remove(pdf_file)
            print(f"Deleted corrupted or invalid PDF: {pdf_file}")
            total_invalid += 1
            deleted_count += 1
        else:
            print(f"Validated PDF: {pdf_file}")

        if count % 1000 == 0:
            print(f"Processed: {count} files | Invalid PDFs found: {total_invalid} | Files deleted: {deleted_count}")

    print("\nScan complete.")
    print(f"Processed: {count} files | Invalid PDFs found: {total_invalid} | Files deleted: {deleted_count}")

# Main function
def main():
    drive_menu = [
        "C:",
        "D:",
        "E:",
        "Custom Directory",
        "Quit"
    ]
    
    print("Select a drive or directory to scan:")
    for index, option in enumerate(drive_menu, start=1):
        print(f"{index}) {option}")
    
    choice = int(input())
    
    if choice == 5:
        print("Quitting.")
        return
    
    if choice == 4:
        custom_path = input("Enter the path to the custom directory (e.g., C:/path/to/directory): ")
        directory = os.path.normpath(custom_path)
    else:
        drive = drive_menu[choice - 1]
        directory = os.path.join("/mnt", drive)
    
    scan_and_process(directory)
    print("\nScript execution finished.")

if __name__ == "__main__":
    main()
