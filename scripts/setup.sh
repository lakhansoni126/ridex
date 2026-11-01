#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env from .env.example"
fi

mkdir -p storage/posts storage/avatars storage/thumbnails

echo "Building and starting Docker Compose stack..."
docker compose up -d --build

echo "Waiting for API health..."
for i in {1..40}; do
  if curl -sf "http://localhost:8000/health" >/dev/null; then
    echo "API is up: http://localhost:8000/docs"
    break
  fi
  sleep 2
  if [[ $i -eq 40 ]]; then
    echo "API did not become healthy in time; check: docker compose logs api"
    exit 1
  fi
done

echo "Seeding demo users..."
docker compose exec -T api python /scripts/seed.py

echo "Done. Demo passwords: password123 (alex / sam / jordan)"
