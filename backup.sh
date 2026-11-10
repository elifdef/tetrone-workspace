#!/usr/bin/env bash

set -e

BACKUP_ROOT="./backups"
DB_CONTAINER="tetrone_postgres"
STORAGE_PATH="./tetrone-backend/storage"
ENV_PATH="./.env"

# Підтягуємо змінні з .env для автоавторизації в БД
if [ -f "$ENV_PATH" ]; then
    export $(grep -v '^#' "$ENV_PATH" | xargs)
fi

DB_USER="${DB_USERNAME:-postgres}"
DB_NAME="${DB_DATABASE:-tetrone}"

do_backup() {
    TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
    TARGET_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
    mkdir -p "${TARGET_DIR}"

    echo "=== Початок бекапу [${TIMESTAMP}] ==="

    # 1. Бекап бази даних
    echo "[1/3] Створення дампу БД..."
    docker exec -t "${DB_CONTAINER}" pg_dump -U "${DB_USER}" -d "${DB_NAME}" | gzip > "${TARGET_DIR}/db_backup.sql.gz"

    # 2. Бекап папки storage (включно з логами)
    echo "[2/3] Архівування storage..."
    tar -czf "${TARGET_DIR}/storage.tar.gz" -C "$(dirname "$STORAGE_PATH")" "$(basename "$STORAGE_PATH")"

    # 3. Бекап .env файлу
    echo "[3/3] Збереження .env..."
    cp "${ENV_PATH}" "${TARGET_DIR}/.env"

    echo "=== Бекап успішно збережено у: ${TARGET_DIR} ==="
}

do_restore() {
    RESTORE_DIR="$1"

    if [ -z "$RESTORE_DIR" ]; then
        echo "Помилка: Вкажіть шлях до папки бекапу."
        echo "Приклад: $0 restore ./backups/2026-11-10_15-30-00"
        exit 1
    fi

    if [ ! -d "$RESTORE_DIR" ]; then
        echo "Помилка: Директорію ${RESTORE_DIR} не знайдено."
        exit 1
    fi

    echo "=== Початок відновлення з: ${RESTORE_DIR} ==="

    # 1. Відновлення .env
    if [ -f "${RESTORE_DIR}/.env" ]; then
        echo "[1/3] Відновлення .env..."
        cp "${RESTORE_DIR}/.env" "${ENV_PATH}"
    fi

    # 2. Відновлення storage
    if [ -f "${RESTORE_DIR}/storage.tar.gz" ]; then
        echo "[2/3] Перезапис папки storage..."
        rm -rf "${STORAGE_PATH}"
        tar -xzf "${RESTORE_DIR}/storage.tar.gz" -C "$(dirname "$STORAGE_PATH")"
    fi

    # 3. Відновлення БД
    if [ -f "${RESTORE_DIR}/db_backup.sql.gz" ]; then
        echo "[3/3] Відновлення схеми та даних PostgreSQL..."
        docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" > /dev/null
        gunzip -c "${RESTORE_DIR}/db_backup.sql.gz" | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" > /dev/null
    fi

    echo "=== Відновлення успішно завершено ==="
}

case "$1" in
    backup)
        do_backup
        ;;
    restore)
        do_restore "$2"
        ;;
    *)
        echo "Використання:"
        echo "  Створити бекап:    $0 backup"
        echo "  Відновити бекап:  $0 restore ./backups/РРРР-ММ-ДД_ГГ-ХХ-СС"
        exit 1
        ;;
esac