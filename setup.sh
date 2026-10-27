#!/bin/bash
set -e

echo "Starting Tetrone setup..."

echo "Cloning repositories..."
[ ! -d "tetrone-backend" ] && git clone git@github.com:elifdef/tetrone-backend.git
[ ! -d "tetrone-frontend" ] && git clone git@github.com:elifdef/tetrone-frontend.git
[ ! -d "tetrone-websockets" ] && git clone git@github.com:elifdef/tetrone-websockets.git

echo "Setting up .env files..."
[ ! -f ".env" ] && [ -f ".env.example" ] && cp .env.example .env || touch .env
[ ! -f "tetrone-backend/.env" ] && cp tetrone-backend/.env.example tetrone-backend/.env
[ ! -f "tetrone-frontend/.env" ] && cp tetrone-frontend/.env.example tetrone-frontend/.env
[ ! -f "tetrone-websockets/.env" ] && cp tetrone-websockets/.env.example tetrone-websockets/.env

echo "Setup complete."
echo "IMPORTANT: Please configure the root '.env' file, then run './update.sh' to start the platform."