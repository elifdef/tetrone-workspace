#!/bin/bash
set -e

echo "Starting Tetrone workspace setup..."

clone_or_pull() {
    local repo_url=$1
    local dir_name=$2
    if [ ! -d "$dir_name" ]; then
        echo "Cloning $dir_name..."
        git clone "$repo_url" "$dir_name"
    else
        echo "Updating $dir_name..."
        git -C "$dir_name" pull || echo "Failed to pull $dir_name, skipping..."
    fi
}

clone_or_pull "git@github.com:elifdef/tetrone-backend.git" "tetrone-backend"
clone_or_pull "git@github.com:elifdef/tetrone-frontend.git" "tetrone-frontend"
clone_or_pull "git@github.com:elifdef/tetrone-websockets.git" "tetrone-websockets"

echo "Configuring environment files..."
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        echo "Created root .env from .env.example"
    else
        touch .env
        echo "Created empty root .env"
    fi
fi

[ ! -f "tetrone-backend/.env" ] && touch tetrone-backend/.env
[ ! -f "tetrone-frontend/.env" ] && touch tetrone-frontend/.env
[ ! -f "tetrone-websockets/.env" ] && touch tetrone-websockets/.env

echo "Setup complete! Fill out root '.env', then run './deploy.sh prod' or './deploy.sh dev'."