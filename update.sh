echo "Rebuilding and starting Docker containers..."
docker compose -f docker-compose.prod.yml up -d --build --remove-orphans

echo "Waiting for PostgreSQL to initialize..."
sleep 5

echo "Running Laravel migrations and caching..."

docker exec tetrone_backend php artisan config:clear
docker exec tetrone_backend php artisan migrate --force
docker exec tetrone_backend php artisan config:cache
docker exec tetrone_backend php artisan route:cache
docker exec tetrone_backend php artisan view:cache
docker exec tetrone_backend php artisan storage:link || true

echo "Update successfully completed!"