#!/bin/bash

# Get the current date and time in YYYY-MM-DD_HH-MM-SS format
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")

# Create the filename using the timestamp
filename="bash_history_${timestamp}.txt"

# Copy the contents of ~/.bash_history to the new file
cp ~/.bash_history "$filename"

# Open the file in Sublime Text
subl "$filename"
