#!/bin/bash
set -e

MODE="${1:-prod}"

setup_storage_links() {
    echo "Configuring storage permissions and links..."
    docker exec tetrone_backend chown -R www-data:www-data /var/www/storage
    docker exec tetrone_backend chmod -R 775 /var/www/storage
    docker exec tetrone_backend php artisan storage:unlink || true
    docker exec tetrone_backend php artisan storage:link
}

if [ "$MODE" = "prod" ]; then
    echo "RUNNING IN PRODUCTION MODE"
    COMPOSE_FILE="docker-compose.prod.yml"

    echo "Rebuilding and starting production containers..."
    docker compose -f "$COMPOSE_FILE" down --remove-orphans
    docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans

    echo "Waiting for services to initialize..."
    sleep 8

    echo "Running Laravel production optimizations..."
    docker exec tetrone_backend php artisan config:clear
    docker exec tetrone_backend php artisan migrate --force    
    docker exec tetrone_backend php artisan optimize

    # Налаштування сховища
    setup_storage_links

    echo "Production deployment completed successfully!"

elif [ "$MODE" = "dev" ]; then
    echo "RUNNING IN DEVELOPMENT MODE"
    if [ -f "docker-compose.dev.yml" ]; then
        COMPOSE_FILE="docker-compose.dev.yml"
    else
        COMPOSE_FILE="docker-compose.yml"
    fi

    echo "Rebuilding and starting development containers using $COMPOSE_FILE..."
    docker compose -f "$COMPOSE_FILE" down --remove-orphans
    docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans

    echo "Waiting for services to initialize..."
    sleep 8

    if ! docker exec tetrone_backend test -f /var/www/vendor/autoload.php; then
        echo "Installing Composer dependencies for dev..."
        docker exec tetrone_backend composer install
    fi

    echo "Running Laravel dev setup..."
    docker exec tetrone_backend php artisan optimize:clear
    docker exec tetrone_backend php artisan migrate

    # Налаштування сховища
    setup_storage_links

    echo "Development environment is ready! Caching is disabled."
else
    echo "Unknown mode: '$MODE'. Usage: ./deploy.sh [prod|dev] (default: prod)"
    exit 1
fi