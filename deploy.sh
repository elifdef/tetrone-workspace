#!/bin/bash
set -e

MODE="prod"
FORCE=false

for arg in "$@"; do
    case "$arg" in
        prod)
            MODE="prod"
            ;;
        dev)
            MODE="dev"
            ;;
        --force|-f)
            FORCE=true
            ;;
        *)
            echo "Unknown argument: '$arg'"
            echo "Usage: ./deploy.sh [prod|dev] [--force|-f]"
            exit 1
            ;;
    esac
done

if [ "$FORCE" = true ]; then
    echo "=============================================================="
    echo "  [WARNING] FORCE MODE ACTIVATED ($MODE)!"
    echo "  This action will:"
    echo "    - Stop and remove all containers"
    echo "    - DELETE ALL DOCKER VOLUMES (Database, Storage, Redis data will be WIPED)"
    echo "    - Wipe and recreate the database schema (migrate:fresh)"
    echo "=============================================================="
    read -rp "Are you absolutely sure you want to proceed? [y/N]: " CONFIRMATION
    case "$CONFIRMATION" in
        [yY][eE][sS]|[yY])
            echo "Confirmation received. Proceeding with clean reset..."
            ;;
        *)
            echo "Operation cancelled by user."
            exit 0
            ;;
    esac
fi

setup_storage_links() {
    echo "Configuring storage permissions, directories, and links..."

    docker exec -u 0 tetrone_backend mkdir -p \
        /var/www/storage/app/public \
        /var/www/storage/framework/views \
        /var/www/storage/framework/cache \
        /var/www/storage/framework/sessions \
        /var/www/storage/logs

    docker exec -u 0 tetrone_backend rm -rf /var/www/public/storage
    docker exec -u 0 tetrone_backend php artisan storage:link || true

    docker exec -u 0 tetrone_backend chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache
    docker exec -u 0 tetrone_backend chmod -R 775 /var/www/storage /var/www/bootstrap/cache
}

# ================= PRODUCTION =================
if [ "$MODE" = "prod" ]; then
    echo "RUNNING IN PRODUCTION MODE"
    COMPOSE_FILE="docker-compose.prod.yml"

    if [ "$FORCE" = true ]; then
        echo "Destroying production containers and wiping volumes..."
        docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
        docker compose -f "$COMPOSE_FILE" build --no-cache
    else
        echo "Stopping production containers..."
        docker compose -f "$COMPOSE_FILE" down --remove-orphans
    fi

    echo "Starting production containers..."
    docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans

    echo "Waiting for services to initialize..."
    sleep 8

    setup_storage_links

    echo "Running database setup..."
    if [ "$FORCE" = true ]; then
        echo "Running migrate:fresh for clean production database..."
        docker exec tetrone_backend php artisan migrate:fresh --force
    else
        echo "Running standard migrations..."
        docker exec tetrone_backend php artisan migrate --force
    fi

    echo "Running Laravel production optimizations..."
    docker exec tetrone_backend php artisan config:clear
    docker exec tetrone_backend php artisan optimize

    echo "Production deployment completed successfully!"

# ================= DEVELOPMENT =================
elif [ "$MODE" = "dev" ]; then
    echo "RUNNING IN DEVELOPMENT MODE"
    if [ -f "docker-compose.dev.yml" ]; then
        COMPOSE_FILE="docker-compose.dev.yml"
    else
        COMPOSE_FILE="docker-compose.yml"
    fi

    # Автоматично очищаємо старий кеш bootstrap на хості
    rm -f tetrone-backend/bootstrap/cache/*.php 2>/dev/null || true

    if [ "$FORCE" = true ]; then
        echo "Destroying development containers and wiping volumes..."
        docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
        docker compose -f "$COMPOSE_FILE" build --no-cache
    else
        echo "Stopping development containers..."
        docker compose -f "$COMPOSE_FILE" down --remove-orphans
    fi

    # Встановлення vendor, якщо його немає
    if [ ! -f "tetrone-backend/vendor/autoload.php" ]; then
        echo "Vendor not found. Installing Composer dependencies for dev..."
        rm -rf tetrone-backend/public/storage

        docker compose -f "$COMPOSE_FILE" run --rm --no-deps backend sh -c "
            git config --global --add safe.directory /var/www && \
            composer install --prefer-dist --no-interaction --no-scripts && \
            composer dump-autoload --optimize --no-scripts
        "
    fi

    echo "Starting development containers..."
    docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

    echo "Waiting for services to initialize..."
    sleep 8

    # Налаштування лінків
    setup_storage_links

    # Перевірка наявності APP_KEY та генерація, якщо він порожній
    if grep -qE '^APP_KEY=(["'\'']{2})?$' tetrone-backend/.env 2>/dev/null; then
        echo "APP_KEY is missing or empty. Generating encryption key..."
        docker exec tetrone_backend php artisan key:generate --force
    fi

    # Запуск оптимізації та дискавері
    echo "Discovering packages and clearing dev caches..."
    docker exec tetrone_backend php artisan package:discover --ansi
    docker exec tetrone_backend php artisan optimize:clear

    echo "Running database setup..."
    if [ "$FORCE" = true ]; then
        echo "Running migrate:fresh for clean development database..."
        docker exec tetrone_backend php artisan migrate:fresh
    else
        echo "Running standard migrations..."
        docker exec tetrone_backend php artisan migrate
    fi

    echo "Development environment is ready! Caching is disabled."
fi