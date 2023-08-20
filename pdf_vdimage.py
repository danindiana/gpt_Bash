#!/usr/bin/env python3

import os
import subprocess
import glob
from PIL import Image

# Function to process files (PDF or images)
def process_file(file_path):
    _, file_extension = os.path.splitext(file_path)
    
    if file_extension.lower() == ".pdf":
        process_command = ["pdfinfo", file_path]
        stdout = subprocess.DEVNULL
    else:
        try:
            Image.open(file_path).verify()
        except Exception:
            os.remove(file_path)
            print(f"Deleted corrupted or invalid image: {file_path}")
            return False
        return True

    process = subprocess.run(process_command, stdout=stdout, stderr=subprocess.DEVNULL)
    return process.returncode == 0

# Function to recursively scan for files (PDF or images) and process them
def scan_and_process(directory):
    count = 0
    total_invalid = 0
    deleted_count = 0
    
    print(f"Scanning directory: {directory}\n")
    
    for file_path in glob.iglob(os.path.join(directory, "**", "*.*"), recursive=True):
        if os.path.isfile(file_path):
            count += 1
            if process_file(file_path):
                print(f"Validated: {file_path}")
            else:
                total_invalid += 1
                deleted_count += 1

            if count % 1000 == 0:
                print(f"Processed: {count} files | Invalid files found: {total_invalid} | Files deleted: {deleted_count}")

    print("\nScan complete.")
    print(f"Processed: {count} files | Invalid files found: {total_invalid} | Files deleted: {deleted_count}")

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
