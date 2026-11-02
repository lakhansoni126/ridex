#!/usr/bin/env bash
set -euo pipefail
docker compose exec -T api /app/seed
