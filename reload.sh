#!/bin/bash
set -e

# Перевірка чи бекенд взагалі запущений
if ! docker ps --format '{{.Names}}' | grep -q "^tetrone_backend$"; then
    echo "[ERROR] Container 'tetrone_backend' is not running."
    echo "Start the project first with ./deploy.sh [dev|prod]"
    exit 1
fi

# Автоматичне визначення режиму через конфіг працюючого Laravel
APP_ENV=$(docker exec tetrone_backend php -r "echo config('app.env');" 2>/dev/null || echo "local")

if [ "$APP_ENV" = "production" ] || [ "$APP_ENV" = "prod" ]; then
    MODE="prod"
    COMPOSE_FILE="docker-compose.prod.yml"
else
    MODE="dev"
    if [ -f "docker-compose.dev.yml" ]; then
        COMPOSE_FILE="docker-compose.dev.yml"
    else
        COMPOSE_FILE="docker-compose.yml"
    fi
fi

echo "  Reloading services in [$MODE] mode ($COMPOSE_FILE)..."

# 1. Перезапуск сервісів для зчитування нових змінних .env
echo "Restarting PHP containers & sockets to apply .env changes..."
docker compose -f "$COMPOSE_FILE" restart backend queue schedule socket

# Коротка пауза для ініціалізації процесів
sleep 2

# 2. Робота з кешами та міграціями згідно з режимом
if [ "$MODE" = "prod" ]; then
    echo "Clearing and compiling production caches..."
    docker exec tetrone_backend php artisan optimize:clear
    docker exec tetrone_backend php artisan optimize

    echo "Running pending migrations (force)..."
    docker exec tetrone_backend php artisan migrate --force
else
    echo "Clearing dev caches (caching remains disabled)..."
    docker exec tetrone_backend php artisan optimize:clear

    echo "Running pending migrations..."
    docker exec tetrone_backend php artisan migrate
fi

# 3. Перезапуск черг (воркери перечитують оновлений PHP-код)
echo "Restarting queue workers..."
docker exec tetrone_backend php artisan queue:restart

echo "Reload completed successfully in ~3 seconds!"