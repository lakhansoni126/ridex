# RideX Architecture

```
Flutter mobile  --REST/WS-->  Go Gin API  -->  Postgres+PostGIS
                                  |                ^
                                  +--> local /storage (images)
```

## Backend (Go)

- **Gin** HTTP router + **gorilla/websocket**
- **Single `service.Svc`** injected into handlers and reused by REST + WS (location ingest, ride status, etc.)
- **pgx** pool; versioned migrations embedded from `internal/db/migrations/NNN_name.sql`, applied on startup in order (one transaction each, under a Postgres advisory lock, recorded in `schema_migrations`)
- JWT access tokens (HS256 only, `exp` required); refresh tokens hashed in DB, rotated on use, reuse of a revoked token revokes all of the user's sessions
- Media stored under `STORAGE_ROOT` (`posts/`, `avatars/`, `thumbnails/`); uploads are content-sniffed (JPEG/PNG/WebP), JPEG thumbnails generated with the stdlib
- WebSockets: one `ws.Client` per connection with a buffered send queue and a single writer goroutine; slow clients are dropped; ping/pong keepalive
- Background janitor (every 10 min): location retention (`LOCATION_RETENTION_DAYS`), share expiry, refresh-token cleanup, rate-limit map pruning
- Structured logs via `log/slog` (JSON when `APP_ENV=production`), `X-Request-ID` on every response, `/health` (liveness) and `/ready` (DB ping)
- `APP_ENV=production` refuses to start with the default or a short (<32 chars) `JWT_SECRET`

## Mobile

Flutter app under `mobile/` — Riverpod, GoRouter, background location buffer syncing to the same REST/WS contracts.
