# RideX Architecture

```
Flutter mobile  --REST/WS-->  Go Gin API  -->  Postgres+PostGIS
                                  |                ^
                                  +--> local /storage (images)
```

## Backend (Go)

- **Gin** HTTP router + **gorilla/websocket**
- **Single `service.Svc`** injected into handlers and reused by REST + WS (location ingest, ride status, etc.)
- **pgx** pool; schema embedded in `internal/db/schema.sql` and applied on startup
- JWT access tokens; refresh tokens hashed in DB
- Media stored under `STORAGE_ROOT` (`posts/`, `avatars/`, `thumbnails/`)

## Mobile

Flutter app under `mobile/` — Riverpod, GoRouter, background location buffer syncing to the same REST/WS contracts.
