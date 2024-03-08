#!/bin/bash
# Filename: find_git_repositories.sh

echo "Searching in: $(pwd)"

git_count=0
file_count=0

# Find .git directories, count them, and count files within them
while IFS= read -r git_dir; do
  # Increase git repository count
  ((git_count++))
  
  # Find the parent directory of the .git directory
  repo_path=$(dirname "$git_dir")
  
  # Get the name of the repository directory
  repo_name=$(basename "$repo_path")
  
  # Count the files in the repository excluding the .git directory
  repo_files=$(find "$repo_path" -type f | grep -v '.git' | wc -l)
  
  # Add to the total file count
  file_count=$((file_count + repo_files))
  
  # Capture a summarized git status
  pushd "$repo_path" > /dev/null # Navigate into repository directory quietly
  git_status=$(git status -s) # Get the short status
  popd > /dev/null # Return to the original directory quietly
  
  # Print the repository name, its path, the file count, and git status
  echo "Repo Name: $repo_name"
  echo "Path: $repo_path"
  echo "Files: $repo_files"
  if [ -z "$git_status" ]; then
    echo "Git Status: Clean"
  else
    echo "Git Status: Changes Pending"
    echo "$git_status"
  fi
  echo "" # for better readability
done < <(find . -type d -name .git)

echo "Total Git repositories found: $git_count"
echo "Total files in Git repositories: $file_count"
