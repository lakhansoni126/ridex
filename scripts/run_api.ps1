# Start RideX API bound to all interfaces (LAN reachable at :8000).
# Requires Postgres/PostGIS (prefer: docker compose up -d db).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location "$root\backend"

if (-not $env:DATABASE_URL) {
  $env:DATABASE_URL = "postgres://ridex:ridex_dev_password@localhost:5432/ridex?sslmode=disable"
}
$env:STORAGE_ROOT = Join-Path $root "storage"
$env:API_PORT = "8000"
$env:CORS_ORIGINS = "*"
$env:JWT_SECRET = if ($env:JWT_SECRET) { $env:JWT_SECRET } else { "change-me-to-a-long-random-string" }

Write-Host "RideX API -> http://0.0.0.0:8000 (LAN http://192.168.29.37:8000)"
go run ./cmd/api
