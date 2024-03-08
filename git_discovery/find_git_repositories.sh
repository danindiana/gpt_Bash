#!/bin/bash
# Filename: find_git_repositories.sh

echo "Searching in: $(pwd)"

git_count=0
file_count=0

# Find .git directories, count them, and count files within them
while IFS= read -r git_dir; do
  ((git_count++))
  repo_files=$(find "$git_dir"/.. -type f | wc -l)
  file_count=$((file_count + repo_files))
  repo_name=$(basename "$(dirname "$git_dir")")
  echo "$repo_name: $repo_files files"
done < <(find . -type d -name .git)

echo "Total Git repositories found: $git_count"
echo "Total files in Git repositories: $file_count"
