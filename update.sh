#!/bin/bash
set -e

MODE="${1:-prod}"

echo "Starting automated update pipeline (Mode: $MODE)"

# sync repo
./sync.sh

# rebuild
./deploy.sh "$MODE"

echo "Update pipeline finished successfully!"