# RideX Architecture

## Overview

RideX is a monorepo: Flutter client (`mobile/`) + FastAPI backend (`backend/`) + local PostGIS via Docker Compose.

```
┌────────────────────────────┐
│  Flutter (mobile/)         │
│  REST + WebSocket client   │
└────────────┬───────────────┘
             │
     ┌───────┴────────┐
     ▼                ▼
┌──────────┐   ┌──────────────┐
│ REST API │   │ WS hubs      │
│ /api/v1  │   │ /ws/rides/*  │
│          │   │ /ws/location │
└────┬─────┘   └──────┬───────┘
     │                │
     ▼                ▼
┌────────────────────────────┐
│ PostgreSQL + PostGIS       │
│ geography Point/LineString │
└────────────────────────────┘
             +
┌────────────────────────────┐
│ Local filesystem /storage  │
│ posts / avatars / thumbs   │
└────────────────────────────┘
```

## Backend layout

| Path | Role |
|------|------|
| `app/core/` | Config, DB, JWT/password, deps, rate limit |
| `app/models/` | SQLAlchemy 2 + GeoAlchemy2 |
| `app/schemas/` | Pydantic request/response models |
| `app/services/` | Auth, friends, rides, shares, posts, media, retention |
| `app/api/v1/` | REST routers |
| `app/ws/` | In-memory WebSocket manager + hubs |
| `migrations/` | Alembic (PostGIS-enabled initial schema) |

## Auth

- Register/login issue **JWT access** + **opaque refresh** (SHA-256 hashed in `refresh_tokens`).
- Access token via `Authorization: Bearer`.
- WebSockets pass `?token=<access_jwt>`.

## Realtime

- Single-process **in-memory** connection manager (no Redis yet).
- Ride room: `/ws/rides/{ride_id}` — location/status fan-out to participants.
- Shares hub: `/ws/location-shares` — friend location updates + `share_ended`.

## Location privacy & retention

- Ride locations only to ride participants.
- Share locations only to owner + granted friends; stop/revoke ends fan-out.
- `location_points` purged by retention helper (`LOCATION_RETENTION_DAYS`, default 30).
- In-memory rate limit: ~2s moving / ~15s stationary per user.

## Media

- Uploads under `STORAGE_ROOT` (`posts/`, `avatars/`, `thumbnails/`).
- MIME allowlist, size cap, sanitized filenames, Pillow thumbnails.
- Served authenticated at `GET /api/v1/media/{path}`.

## Local infra

- `docker-compose.yml`: `db` (postgis/postgis:16-3.4) + `api`.
- `infra/init-db.sql`: `CREATE EXTENSION postgis`.
- API container runs `alembic upgrade head` then uvicorn.
