#!/bin/bash
set -e

echo "Synchronizing repositories with remote"

pull_repo() {
    local dir_name=$1
    if [ -d "$dir_name/.git" ]; then
        echo "Updating $dir_name..."
        git -C "$dir_name" pull --rebase || git -C "$dir_name" pull
    else
        echo "Warning: $dir_name is not a git repository. Skipping."
    fi
}

pull_repo "tetrone-backend"
pull_repo "tetrone-frontend"
pull_repo "tetrone-websockets"

echo "All repositories are up to date"