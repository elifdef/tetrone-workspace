#!/bin/bash
set -e

# default - dev
MODE="${1:-dev}"

if [ "$MODE" = "prod" ]; then
    echo "RUNNING IN PRODUCTION MODE"
    COMPOSE_FILE="docker-compose.prod.yml"

    echo "Rebuilding and starting production containers..."
    docker compose -f "$COMPOSE_FILE" down --remove-orphans
    docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans

    echo "Waiting for PostgreSQL to initialize..."
    sleep 5

    echo "Running Laravel production optimizations..."
    docker exec tetrone_backend php artisan config:clear
    docker exec tetrone_backend php artisan migrate --force
    
    # cache for PROD
    docker exec tetrone_backend php artisan optimize
    docker exec tetrone_backend php artisan view:cache
    docker exec tetrone_backend php artisan storage:link || true

    echo "Production environment is up and optimized!"

elif [ "$MODE" = "dev" ]; then
    echo "RUNNING IN DEVELOPMENT MODE"
    COMPOSE_FILE="docker-compose.dev.yml"

    echo "Rebuilding and starting development containers..."
    docker compose -f "$COMPOSE_FILE" down --remove-orphans
    docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans

    echo "Waiting for PostgreSQL to initialize..."
    sleep 5

    echo "Running Laravel dev setup..."
    docker exec tetrone_backend php artisan optimize:clear
    docker exec tetrone_backend php artisan migrate
    docker exec tetrone_backend php artisan storage:link || true

    echo "Development environment is up! Caching is disabled."
else
    echo "Unknown mode: $MODE. Use './deploy.sh prod' or './deploy.sh dev'"
    exit 1
fi