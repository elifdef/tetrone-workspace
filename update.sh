#!/bin/bash
set -e

echo "Starting Tetrone update..."

echo "Pulling tetrone-backend..."
cd tetrone-backend && git pull origin main && cd ..

echo "Pulling tetrone-frontend..."
cd tetrone-frontend && git pull origin main && cd ..

echo "Pulling tetrone-websockets..."
cd tetrone-websockets && git pull origin main && cd ..

echo "Rebuilding and starting Docker containers..."
docker compose -f docker-compose.prod.yml up -d --build --remove-orphans

echo "Running Laravel migrations and caching..."
docker exec tetrone_backend php artisan migrate --force
docker exec tetrone_backend php artisan config:cache
docker exec tetrone_backend php artisan route:cache
docker exec tetrone_backend php artisan view:cache

docker exec tetrone_backend php artisan storage:link || true

echo "Update successfully completed!"