#!/bin/bash

# За замовчуванням підключаємо до backend
TARGET="${1:-backend}"

case "$TARGET" in
    backend|b)
        CONTAINER="tetrone_backend"
        ;;
    queue|q)
        CONTAINER="tetrone_queue"
        ;;
    schedule|s)
        CONTAINER="tetrone_schedule"
        ;;
    frontend|front|f)
        CONTAINER="tetrone_frontend"
        ;;
    socket|ws|w)
        CONTAINER="tetrone_websocket"
        ;;
    db|postgres|p)
        CONTAINER="tetrone_postgres"
        ;;
    redis|r)
        CONTAINER="tetrone_redis"
        ;;
    mailpit|m)
        CONTAINER="tetrone_mailpit"
        ;;
    elasticsearch|elastic|es)
        CONTAINER="tetrone_elasticsearch"
        ;;
    *)
        CONTAINER="$TARGET"
        ;;
esac

# Перевірка наявності контейнера серед активних
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "[ERROR] Container '$CONTAINER' is not running!"
    echo "Available aliases: backend (b), frontend (f), socket (ws), queue (q), schedule (s), db (p), redis (r)"
    exit 1
fi

echo "Connecting to $CONTAINER..."

# Автоматичний вибір оболонки: bash (Debian/Ubuntu) або sh (Alpine)
if docker exec "$CONTAINER" which bash >/dev/null 2>&1; then
    docker exec -it "$CONTAINER" bash
else
    docker exec -it "$CONTAINER" sh
fi