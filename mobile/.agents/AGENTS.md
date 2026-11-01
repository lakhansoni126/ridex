# Project-Scoped Rules: RideX

RideX is a premium automobile (car) community and group-ride application built with Flutter (mobile) and FastAPI (backend).

## Core Directives

1. **Architecture**: Prefer Clean Architecture (Presentation, Domain, Data). Keep UI widgets free of business logic where practical.
2. **State Management**: Use Riverpod unless otherwise clarified.
3. **Domain**: This is a **car** community app — never use motorcycle/bike wording, icons, or assets.
4. **Branding**: App name is **RideX** everywhere (display name, notifications, docs).
5. **Storage**: Local Isar may cache/buffer offline data; server-authoritative data lives in Postgres+PostGIS via the backend.
6. **Performance**: Prioritize 60 FPS. Heavy GPS work should be buffered/batched and avoid blocking the UI isolate.
7. **Design**: Luxury automotive dashboard feel — dark-first, glass/translucency, large glove-friendly targets, single bold accent (`#E53935`).
8. **Offline-first location**: Buffer location points locally when offline; sync in batches when online.
9. **API**: Base URL via `ApiConfig` / `--dart-define=API_BASE_URL=...` (default Android emulator `http://10.0.2.2:8000`). REST prefix `/api/v1`. Auth JWT with refresh on 401.
10. **Realtime**: Ride WS `/ws/rides/{id}?token=` and location-share WS `/ws/location-shares?token=` via `web_socket_channel`.

## Mobile layout (`mobile/lib`)

- `core/` — `config.dart`, `providers.dart`, theme
- `data/api/` — `ApiClient` + feature repositories
- `data/ws/` — ride + location-share socket helpers
- `data/local/` — token store, offline location buffer
- `features/auth|rides|friends|sharing|community|permissions/` — new social/group features
- Existing personal tracking: `features/ride`, `features/map`, `features/history`, `features/garage`
- `services/background_location_service.dart` — FGS GPS when group ride live or share active

## Reference Stack
- **Framework**: Flutter (`mobile/`)
- **Backend**: FastAPI (`backend/`)
- **Location**: `geolocator`, `permission_handler`, offline `PendingLocationPoint` / file buffer
- **Routing**: GoRouter (auth gate → `/login`)
- **Mapping**: `flutter_map` + OpenStreetMap
- **Local cache**: Isar + `shared_preferences` for tokens
- **Realtime**: `web_socket_channel`

## After schema changes
```bash
cd mobile
dart run build_runner build --delete-conflicting-outputs
```
