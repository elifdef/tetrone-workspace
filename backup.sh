#!/usr/bin/env bash
set -e

BACKUP_ROOT="./backups"
DB_CONTAINER="tetrone_postgres"
BACKEND_CONTAINER="tetrone_backend"
LOGS_PATH="./tetrone-backend/storage/logs"
ENV_PATH="./.env"

print_usage() {
    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Available commands:"
    echo "  backup                   Create a full backup (Database, storage/app media, logs, .env)"
    echo "  restore <backup_dir>     Restore data from the specified backup directory"
    echo "  --help, -h               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 backup"
    echo "  $0 restore ./backups/2026-11-10_15-30-00"
}

if [ $# -eq 0 ]; then
    echo "Error: command is required."
    echo ""
    print_usage
    exit 1
fi

load_env() {
    if [ -f "$ENV_PATH" ]; then
        set -a
        # shellcheck disable=SC1090
        source "$ENV_PATH"
        set +a
    fi
}

do_backup() {
    load_env
    local db_user="${DB_USERNAME:-postgres}"
    local db_name="${DB_DATABASE:-tetrone}"
    local timestamp
    timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    local target_dir="${BACKUP_ROOT}/${timestamp}"

    mkdir -p "${target_dir}"

    echo "=== Starting backup [${timestamp}] ==="

    # 1. Database dump (without -t to preserve binary gzip stream)
    echo "[1/4] Creating PostgreSQL database dump..."
    docker exec "${DB_CONTAINER}" pg_dump --clean --if-exists -U "${db_user}" -d "${db_name}" | gzip > "${target_dir}/db_backup.sql.gz"

    # 2. User media files from Docker volume backend-storage
    echo "[2/4] Archiving user media files (storage/app)..."
    docker exec "${BACKEND_CONTAINER}" tar -czf - -C /var/www/storage app > "${target_dir}/storage_app.tar.gz"

    # 3. Application logs from host
    echo "[3/4] Archiving logs..."
    if [ -d "$LOGS_PATH" ]; then
        tar -czf "${target_dir}/storage_logs.tar.gz" -C "$(dirname "$LOGS_PATH")" "$(basename "$LOGS_PATH")"
    fi

    # 4. Environment configuration file
    echo "[4/4] Saving .env file..."
    if [ -f "$ENV_PATH" ]; then
        cp "${ENV_PATH}" "${target_dir}/.env"
    fi

    echo "=== Backup successfully saved to: ${target_dir} ==="
}

do_restore() {
    local restore_dir="$1"

    if [ ! -d "$restore_dir" ]; then
        echo "Error: backup directory '${restore_dir}' does not exist."
        exit 1
    fi

    echo "=== Starting restore from: ${restore_dir} ==="

    # 1. Restore .env file
    if [ -f "${restore_dir}/.env" ]; then
        echo "[1/3] Restoring .env file..."
        cp "${restore_dir}/.env" "${ENV_PATH}"
    fi

    load_env
    local db_user="${DB_USERNAME:-postgres}"
    local db_name="${DB_DATABASE:-tetrone}"

    # 2. Restore user media files into Docker volume backend-storage
    if [ -f "${restore_dir}/storage_app.tar.gz" ]; then
        echo "[2/3] Restoring user media files (storage/app)..."
        docker exec -u 0 "${BACKEND_CONTAINER}" sh -c "rm -rf /var/www/storage/app/*"
        docker exec -i -u 0 "${BACKEND_CONTAINER}" tar -xzf - -C /var/www/storage < "${restore_dir}/storage_app.tar.gz"
        docker exec -u 0 "${BACKEND_CONTAINER}" chown -R www-data:www-data /var/www/storage/app
    fi

    # 3. Restore PostgreSQL database
    if [ -f "${restore_dir}/db_backup.sql.gz" ]; then
        echo "[3/3] Restoring PostgreSQL schema and data..."
        docker exec -i "${DB_CONTAINER}" psql -U "${db_user}" -d "${db_name}" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" > /dev/null
        gunzip -c "${restore_dir}/db_backup.sql.gz" | docker exec -i "${DB_CONTAINER}" psql -U "${db_user}" -d "${db_name}" > /dev/null
    fi

    echo "=== Restore completed successfully ==="
}

case "$1" in
    backup)
        if [ $# -gt 1 ]; then
            echo "Error: 'backup' command does not accept extra arguments ('$2')."
            echo ""
            print_usage
            exit 1
        fi
        do_backup
        ;;
    restore)
        if [ -z "$2" ]; then
            echo "Error: 'restore' command requires a backup directory path."
            echo ""
            print_usage
            exit 1
        fi
        if [ $# -gt 2 ]; then
            echo "Error: unexpected extra argument '$3' for 'restore' command."
            echo ""
            print_usage
            exit 1
        fi
        do_restore "$2"
        ;;
    --help|-h)
        print_usage
        exit 0
        ;;
    *)
        echo "Error: unknown command '$1'."
        echo ""
        print_usage
        exit 1
        ;;
esac