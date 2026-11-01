# RideX API

Base URL: `http://localhost:8000`  
REST prefix: `/api/v1`  
Interactive docs: `/docs`

Auth header: `Authorization: Bearer <access_token>`

## Auth

| Method | Path | Notes |
|--------|------|-------|
| POST | `/auth/register` | `{email, username, password, display_name}` → tokens + user |
| POST | `/auth/login` | `{email, password}` |
| POST | `/auth/refresh` | `{refresh_token}` rotates refresh |
| POST | `/auth/logout` | `{refresh_token}` revokes |

## Users

| Method | Path | Notes |
|--------|------|-------|
| GET | `/users/me` | Profile |
| PATCH | `/users/me` | `{display_name?, bio?}` |
| POST | `/users/me/avatar` | multipart file |
| GET | `/users/{id}/profile` | Public card |

## Friends

| Method | Path | Notes |
|--------|------|-------|
| GET | `/friends` | Accepted |
| GET | `/friends/requests` | Incoming + outgoing |
| POST | `/friends/requests` | `{username}` |
| POST | `/friends/requests/{id}/accept` | |
| POST | `/friends/requests/{id}/decline` | |
| DELETE | `/friends/{user_id}` | Unfriend |

## Rides

| Method | Path | Notes |
|--------|------|-------|
| GET | `/rides` | Public discover; `status`, `near=lon,lat`, `radius_m` |
| POST | `/rides` | Create (host auto-joined) |
| GET | `/rides/{id}` | Detail + participants |
| PATCH | `/rides/{id}` | Host: title/visibility/status… |
| POST | `/rides/join` | `{join_code}` or `{invite_token}` |
| POST | `/rides/{id}/start` | Host → `live` |
| POST | `/rides/{id}/end` | Host → `ended` |
| POST | `/rides/{id}/participants/{user_id}/remove` | Host |
| PATCH | `/rides/{id}/me/status` | Participant status |
| POST | `/rides/{id}/locations` | Batch points (rate-limited) |

Participant status: `joined`, `on_the_way`, `riding`, `paused`, `stopped`, `reached`, `removed`, `left`  
Ride status: `scheduled`, `live`, `ended`, `cancelled`

## Location shares

| Method | Path | Notes |
|--------|------|-------|
| POST | `/location-shares` | `{duration: 1h\|8h\|indefinite, friend_ids[]}` |
| GET | `/location-shares` | Mine + shared-with-me |
| POST | `/location-shares/{id}/stop` | |
| DELETE | `/location-shares/{id}/grants/{friend_id}` | |
| POST | `/location-shares/{id}/locations` | Batch points |

## Community

| Method | Path | Notes |
|--------|------|-------|
| GET | `/posts` | Cursor feed `?cursor=&limit=` |
| POST | `/posts` | multipart: `caption`, `images[]`, optional ride stats |
| GET | `/posts/{id}` | |
| POST | `/posts/{id}/like` | Toggle |
| GET/POST | `/posts/{id}/comments` | |

## Media

| Method | Path | Notes |
|--------|------|-------|
| GET | `/media/{path}` | Auth required; relative to storage root |

## WebSockets

### `/ws/rides/{ride_id}?token=...`

Client → server:
```json
{"type":"location","lat":12.9,"lon":77.6,"speed":12.3,"heading":90,"accuracy":5,"recorded_at":"...","status":"riding"}
{"type":"status","status":"paused"}
{"type":"ping"}
```

Server → client:
```json
{"type":"participant_update","user_id":"...","lat":...,"lon":...,"status":"riding","last_seen_at":"...","distance_to_host_m":1200,"distance_to_destination_m":5400}
{"type":"ride_status","status":"ended"}
{"type":"participant_removed","user_id":"..."}
{"type":"pong"}
```

### `/ws/location-shares?token=...`

```json
{"type":"location","share_id":"...","lat":...,"lon":...,"recorded_at":"..."}
{"type":"friend_location","share_id":"...","user_id":"...","lat":...,"lon":...,"last_seen_at":"...","online":true}
{"type":"share_ended","share_id":"..."}
```

## Health

`GET /health` → `{"status":"ok","service":"RideX"}`
