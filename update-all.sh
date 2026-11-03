#!/bin/bash

# Зупинити виконання при будь-якій помилці
set -e

# Вкажи назву твого дев-файлу docker-compose (наприклад: docker-compose.dev.yml або docker-compose.yml)
COMPOSE_FILE="docker-compose.dev.yml"


echo " 1. Updating Backend Dependencies (Composer)"

if command -v docker compose &> /dev/null; then
    docker compose -f $COMPOSE_FILE run --rm backend composer update
else
    docker-compose -f $COMPOSE_FILE run --rm backend composer update
fi


echo " 2. Updating Frontend Dependencies (NPM)"

if command -v docker compose &> /dev/null; then
    docker compose -f $COMPOSE_FILE run --rm frontend npm update
else
    docker-compose -f $COMPOSE_FILE run --rm frontend npm update
fi


echo " 3. Updating WebSockets Microservice"

# У твоєму конфігу мікросервіс вебсокетів називається 'socket'
if command -v docker compose &> /dev/null; then
    docker compose -f $COMPOSE_FILE run --rm socket npm update
else
    docker-compose -f $COMPOSE_FILE run --rm socket npm update
fi


echo " 4. Fixing file ownership (WSL / Linux)"

if [ -n "$USER" ]; then
    sudo chown -R $USER:$USER . 2>/dev/null || true
fi


echo " All dependencies updated successfully!"
echo " Run 'git status' to check modified lock files."
