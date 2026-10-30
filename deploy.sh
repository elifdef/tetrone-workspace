#!/bin/bash
set -e

MODE="prod"
FORCE=false

# (prod, dev, --force, -f)
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

# --force
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
    echo "Configuring storage permissions and links..."

    docker exec -u 0 tetrone_backend mkdir -p /var/www/storage/app/public
    docker exec -u 0 tetrone_backend rm -rf /var/www/public/storage
    docker exec -u 0 tetrone_backend ln -sfn /var/www/storage/app/public /var/www/public/storage
    docker exec -u 0 tetrone_backend chown -R www-data:www-data /var/www/storage /var/www/public
    docker exec -u 0 tetrone_backend chmod -R 775 /var/www/storage
}

# PRODUCTION
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
        docker exec tetrone_backend php artisan migrate --force
    fi

    echo "Running Laravel production optimizations..."
    docker exec tetrone_backend php artisan config:clear
    docker exec tetrone_backend php artisan optimize

    echo "Production deployment completed successfully!"

# DEVELOPMENT
elif [ "$MODE" = "dev" ]; then
    echo "RUNNING IN DEVELOPMENT MODE"
    if [ -f "docker-compose.dev.yml" ]; then
        COMPOSE_FILE="docker-compose.dev.yml"
    else
        COMPOSE_FILE="docker-compose.yml"
    fi

    if [ "$FORCE" = true ]; then
        echo "Destroying development containers and wiping volumes..."
        docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
        docker compose -f "$COMPOSE_FILE" build --no-cache
    else
        echo "Stopping development containers..."
        docker compose -f "$COMPOSE_FILE" down --remove-orphans
    fi

    echo "Starting development containers..."
    docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans

    echo "Waiting for services to initialize..."
    sleep 8

    if ! docker exec tetrone_backend test -f /var/www/vendor/autoload.php; then
        echo "Installing Composer dependencies for dev..."
        docker exec tetrone_backend composer install
    fi

    setup_storage_links

    echo "Running database setup..."
    if [ "$FORCE" = true ]; then
        echo "Running migrate:fresh for clean development database..."
        docker exec tetrone_backend php artisan migrate:fresh
    else
        docker exec tetrone_backend php artisan migrate
    fi

    echo "Running Laravel dev setup..."
    docker exec tetrone_backend php artisan optimize:clear

    echo "Development environment is ready! Caching is disabled."
fi