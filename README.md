# RideX

Premium **automobile community** and **group-ride** app.

| Layer | Stack |
|-------|--------|
| Mobile | Flutter (`mobile/`) — Riverpod, GoRouter, flutter_map, Isar |
| Backend | FastAPI + SQLAlchemy 2 + GeoAlchemy2 + Alembic (`backend/`) |
| Infra | Docker Compose — PostGIS 16 + API; local `/storage` media |
| Realtime | WebSockets (`/ws/rides/{id}`, `/ws/location-shares`) |

## Monorepo

```
ridex/
├── mobile/           # Flutter client
├── backend/          # FastAPI
├── assets/branding/  # Logo / icons (SVG + exports)
├── storage/          # Local media (gitignored uploads)
├── infra/            # PostGIS init
├── docs/             # Architecture, API, schema, roadmap
├── scripts/          # setup, seed, native patches
├── docker-compose.yml
└── .env.example
```

## Quick start — backend

```bash
cp .env.example .env
docker compose up -d --build
# API docs: http://localhost:8000/docs
# Health:   http://localhost:8000/health

docker compose exec -T api python /scripts/seed.py
# Demo users: alex@ridex.local / sam@ridex.local / jordan@ridex.local
# Password: password123
```

Unit tests (no DB):

```bash
cd backend
pip install -r requirements.txt
python -m pytest -q
```

## Quick start — mobile

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter create --platforms android,ios .
python ../scripts/patch_mobile_native.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter run
```

| Target | API URL |
|--------|---------|
| Android emulator | `http://10.0.2.2:8000` (default) |
| iOS simulator | `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000` |
| Physical device | `flutter run --dart-define=API_BASE_URL=http://<LAN-IP>:8000` |

## Features shipped

1. **Auth** — register / login / JWT refresh  
2. **Group drives** — create, join by code, host start/end, live map + participant status over WebSocket  
3. **Background location** — FGS notification “RideX is sharing your location”, adaptive sampling, offline buffer + batch sync  
4. **Friends** — request / accept / decline  
5. **Location sharing** — 1h / 8h / indefinite, revoke per friend  
6. **Community** — feed, image posts (local server storage + thumbnails), likes & comments  
7. **Personal track** — existing solo GPS dashboard / history / garage (cars)  

## Docs

- [`docs/architecture.md`](docs/architecture.md)
- [`docs/api.md`](docs/api.md)
- [`docs/schema.md`](docs/schema.md)
- [`docs/native-location.md`](docs/native-location.md)
- [`docs/roadmap.md`](docs/roadmap.md)
- [`assets/branding/README.md`](assets/branding/README.md)

## Manual smoke checklist

1. Register → allow location → home shows **RideX**  
2. Create a public drive → second user joins with code → host starts → both see markers move  
3. Start location share with a friend → friend sees updates; stop/revoke works  
4. Post image to Community → appears in feed; like + comment  
5. Lock phone during a live drive — Android shows RideX FGS notification; points still sync  
