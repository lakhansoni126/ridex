# RideX

Premium **automobile community** and **group-ride** app.

| Layer | Stack |
|-------|--------|
| Mobile | Flutter (`mobile/`) — Riverpod, GoRouter, flutter_map |
| Backend | **Go + Gin** (`backend/`) — shared service layer, pgx, PostGIS, WebSockets |
| Infra | Docker Compose — PostGIS 16 + API; local `/storage` media |

## Run backend

```bash
cp .env.example .env
docker compose up -d --build
# Health: http://localhost:8000/health

docker compose exec -T api /app/seed
# Demo: alex@ridex.local / password123
```

API paths stay under `/api/v1` (same mobile contract). WebSockets: `/ws/rides/{id}`, `/ws/location-shares`.

Unit tests (no DB):

```bash
cd backend
go test ./...
```

## Run mobile

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter create --platforms android,ios .
python ../scripts/patch_mobile_native.py
flutter run
```

## Architecture (backend)

```
backend/
  cmd/api          # process entry
  cmd/seed         # demo users
  internal/
    handler/       # thin HTTP/WS adapters
    service/       # all business logic (reused by REST + WS)
    middleware/    # JWT
    ws/            # room hub
    db/            # pool + embedded schema
```

Handlers never contain business rules — they call `service.Svc` methods shared by REST and WebSocket paths (e.g. `IngestRideLocations`).

## Docs

- [`docs/api.md`](docs/api.md)
- [`docs/architecture.md`](docs/architecture.md)
- [`docs/schema.md`](docs/schema.md)
- [`docs/native-location.md`](docs/native-location.md)
