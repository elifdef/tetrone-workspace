#!/bin/bash
set -e

export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

MODE=""
FORCE=false

print_usage() {
    echo "Usage: $0 <mode> [options]"
    echo ""
    echo "Required mode (choose one):"
    echo "  prod          Deploy in production mode (docker-compose.prod.yml)"
    echo "  dev           Deploy in development mode (docker-compose.dev.yml)"
    echo ""
    echo "Optional flags:"
    echo "  --force, -f   Full reset: wipe all Docker volumes (DB, Redis, Storage) and run migrate:fresh"
    echo "  --help, -h    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dev"
    echo "  $0 prod --force"
}

if [ $# -eq 0 ]; then
    echo "Error: deployment mode is required."
    echo ""
    print_usage
    exit 1
fi

for arg in "$@"; do
    case "$arg" in
        prod|dev)
            if [ -n "$MODE" ] && [ "$MODE" != "$arg" ]; then
                echo "Error: cannot specify both 'prod' and 'dev' modes."
                echo ""
                print_usage
                exit 1
            fi
            MODE="$arg"
            ;;
        --force|-f)
            FORCE=true
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            echo "Error: unknown argument '$arg'."
            echo ""
            print_usage
            exit 1
            ;;
    esac
done

if [ -z "$MODE" ]; then
    echo "Error: required deployment mode ('prod' or 'dev') was not specified."
    echo ""
    print_usage
    exit 1
fi

ensure_app_key() {
    local env_file=".env"

    if [ ! -f "$env_file" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example "$env_file"
            echo "Created .env from .env.example"
        else
            touch "$env_file"
        fi
    fi

    # Remove existing APP_KEY when --force is passed
    if [ "$FORCE" = true ]; then
        echo "Force wipe: generating brand new APP_KEY..."
        sed -i '/^APP_KEY=/d' "$env_file"
    fi

    # Generate a new key if APP_KEY is missing or empty
    if ! grep -qE '^APP_KEY=.+' "$env_file" 2>/dev/null; then
        echo "APP_KEY is missing or empty. Generating secure 256-bit key..."
        local new_key="base64:$(openssl rand -base64 32)"

        if grep -q '^APP_KEY=' "$env_file" 2>/dev/null; then
            sed -i "s|^APP_KEY=.*|APP_KEY=${new_key}\vert{}" "$env_file"
        else
            echo "APP_KEY=${new_key}" >> "$env_file"
        fi
        echo "APP_KEY generated and saved to root .env!"
    fi
}

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

# Generate APP_KEY before starting containers so Docker Compose picks it up
ensure_app_key

setup_storage_links() {
    echo "Configuring storage permissions, directories, and links..."

    if [ "$MODE" = "dev" ]; then
        docker exec -u 0 tetrone_backend sh -c "
            mkdir -p \
                /var/www/storage/app/public \
                /var/www/storage/app/private \
                /var/www/storage/framework/views \
                /var/www/storage/framework/cache \
                /var/www/storage/framework/sessions \
                /var/www/storage/logs \
                /var/www/bootstrap/cache && \
            rm -f /var/www/bootstrap/cache/*.php && \
            chmod -R 777 /var/www/storage /var/www/bootstrap/cache && \
            rm -rf /var/www/public/storage && \
            php artisan storage:link --force
        "
    else
        docker exec -u 0 tetrone_backend sh -c "
            mkdir -p \
                /var/www/storage/app/public \
                /var/www/storage/app/private \
                /var/www/storage/framework/views \
                /var/www/storage/framework/cache \
                /var/www/storage/framework/sessions \
                /var/www/storage/logs \
                /var/www/bootstrap/cache && \
            chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache && \
            chmod -R 775 /var/www/storage /var/www/bootstrap/cache && \
            rm -rf /var/www/public/storage && \
            php artisan storage:link --force
        "
    fi
}

# ================= PRODUCTION =================
if [ "$MODE" = "prod" ]; then
    echo "RUNNING IN PRODUCTION MODE"
    COMPOSE_FILE="docker-compose.prod.yml"

    if [ "$FORCE" = true ]; then
        echo "Destroying production containers and wiping volumes..."
        docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
        docker compose -f "$COMPOSE_FILE" build --no-cache --parallel
    else
        echo "Building production images in parallel..."
        docker compose -f "$COMPOSE_FILE" build --parallel
    fi

    echo "Starting production containers..."
    docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

    echo "Waiting for backend container to become ready..."
    until docker exec tetrone_backend php -v >/dev/null 2>&1; do
        sleep 1
    done

    setup_storage_links

    if [ "$FORCE" = true ]; then
        MIGRATE_CMD="migrate:fresh --force"
    else
        MIGRATE_CMD="migrate --force"
    fi

    echo "Running migrations and caching in single batch..."
    docker exec tetrone_backend sh -c "
        php artisan ${MIGRATE_CMD} && \
        php artisan optimize:clear && \
        php artisan optimize
    "
    docker exec tetrone_queue php artisan queue:restart

    echo "Cleaning up unused Docker images..."
    docker image prune -f >/dev/null 2>&1 || true

    echo "Production deployment completed successfully!"

# ================= DEVELOPMENT =================
elif [ "$MODE" = "dev" ]; then
    echo "RUNNING IN DEVELOPMENT MODE"
    if [ -f "docker-compose.dev.yml" ]; then
        COMPOSE_FILE="docker-compose.dev.yml"
    else
        COMPOSE_FILE="docker-compose.yml"
    fi

    # Clear stale host bootstrap cache files
    rm -f tetrone-backend/bootstrap/cache/*.php 2>/dev/null || true

    if [ "$FORCE" = true ]; then
        echo "Destroying development containers and wiping volumes..."
        docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
        docker compose -f "$COMPOSE_FILE" build --no-cache --parallel
    else
        echo "Stopping development containers..."
        docker compose -f "$COMPOSE_FILE" down --remove-orphans
    fi

    # Install Composer dependencies on host if vendor is missing
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
    docker compose -f "$COMPOSE_FILE" up -d --build --renew-anon-volumes --remove-orphans

    echo "Waiting for backend container to become ready..."
    until docker exec tetrone_backend php -v >/dev/null 2>&1; do
        sleep 1
    done

    setup_storage_links

    echo "Discovering packages and clearing dev caches..."
    docker exec tetrone_backend sh -c "
        php artisan package:discover --ansi && \
        php artisan optimize:clear
    "

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