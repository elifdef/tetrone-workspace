#!/bin/bash

set -e

echo "starting update Tetrone..."

echo "tetrone-backend"
cd tetrone-backend && git pull origin main && cd ..

echo "tetrone-frontend..."
cd tetrone-frontend && git pull origin main && cd ..

echo "tetrone-websockets..."
cd tetrone-websockets && git pull origin main && cd ..

echo "rebuild docker ..."
docker compose -f docker-compose.prod.yml up -d --build --remove-orphans

echo "migration Laravel..."
docker exec tetrone_backend php artisan migrate --force
docker exec tetrone_backend php artisan config:cache
docker exec tetrone_backend php artisan route:cache
docker exec tetrone_backend php artisan view:cache

echo "done."