# RideX API

Base URL: `https://130.210.24.87.sslip.io` (prod) · `http://localhost:8000` (local)
REST prefix: `/api/v1` · Auth header: `Authorization: Bearer <access_token>`

All errors are JSON `{"detail": "<human readable message>"}`. Every response carries `X-Request-ID`.
Bad UUIDs in path parameters return 404. JSON bodies are capped at 1 MiB; multipart uploads at
`4 × MEDIA_MAX_UPLOAD_MB + 1 MiB`.

Health: `GET /health` (liveness) · `GET /ready` (DB ping, 503 when unreachable).

## Shapes

```
UserPublic  = {id, username, display_name, avatar_path|null}
User        = UserPublic + {email, bio|null, created_at}
TokenOut    = {access_token, refresh_token, token_type:"bearer", user: User}
Friendship  = {id, requester_id, addressee_id, status, created_at,
               user: UserPublic /* the other party */, requester: UserPublic, addressee: UserPublic}
Participant = {id, ride_id, user_id, role, status, last_seen_at, distance_to_host_m,
               distance_to_destination_m, joined_at, user: UserPublic, lat, lon}
Ride        = {id, host_id, host: UserPublic, title, description|null, visibility,
               status: scheduled|live|ended|cancelled, join_code|null, invite_token|null,
               scheduled_at, started_at, ended_at, created_at, updated_at,
               start_lat, start_lon, dest_lat, dest_lon, waypoints: [],
               participant_count, is_participant, participants: [Participant]}
Share       = {id, owner_id, owner: UserPublic, duration, expires_at|null, is_active,
               last_seen_at, created_at, lat, lon,
               grants: [{friend_user_id, friend: UserPublic, revoked_at|null}]}
Post        = {id, author_id, author: UserPublic, caption|null, ride_id|null, distance_km|null,
               duration_s|null, like_count, comment_count, created_at,
               images: [{id, file_path, thumb_path, sort_order}], liked_by_me}
Comment     = {id, post_id, user_id, body, created_at, user: UserPublic}
LocationPoint = {lat, lon, speed_mps?, heading?, accuracy_m?, recorded_at, status?}
```

`join_code` / `invite_token` are only returned to current participants. `participants` is `[]` in
list responses; participants with status `removed` or `left` are excluded from lists and counts.

## Auth

| Method | Path | Body → Response |
|--------|------|-----------------|
| POST | `/auth/register` | `{email, username, password, display_name}` → `TokenOut`. 400 validation (email shape, username `^[a-z0-9_.]{3,32}$`, password 8–128, display name 1–60). 409 `email already registered` / `username taken`. 429 after 20/hour per IP |
| POST | `/auth/login` | `{email, password}` → `TokenOut`. 401 `invalid email or password`. 429 after 10 attempts / 15 min per IP+email |
| POST | `/auth/refresh` | `{refresh_token}` → `TokenOut` (rotates; reusing a revoked token revokes every session of that user) |
| POST | `/auth/logout` | `{refresh_token}` → 204 |

## Users

| Method | Path | Notes |
|--------|------|-------|
| GET | `/users/me` | → `User` |
| PATCH | `/users/me` | `{display_name?, bio? (≤280, "" clears)}` → `User` |
| DELETE | `/users/me` | → 204. Anonymises the account, revokes sessions, stops shares, deletes posts/comments/likes/friendships, cancels hosted upcoming rides |
| POST | `/users/me/avatar` | multipart `avatar` (JPEG/PNG/WebP) → `User` |
| GET | `/users/me/stats` | → `{friends, rides_hosted, rides_joined, posts}` |
| GET | `/users/search?q=` | `q` ≥ 2 chars, prefix on username/display name → `{"users": [UserPublic + {friendship: none|friends|incoming|outgoing}]}` (max 20) |

## Friends

| Method | Path | Notes |
|--------|------|-------|
| GET | `/friends` | → `{"friends": [UserPublic]}` |
| GET | `/friends/requests` | → `{"incoming": [Friendship], "outgoing": [Friendship]}` |
| POST | `/friends/requests` | `{username}` → `Friendship`. Auto-accepts if they already asked you (status `accepted`); re-opens declined requests. 409 `already friends` / `request already pending`; 404 unknown user; 400 self |
| POST | `/friends/requests/{id}/accept` | → `Friendship` |
| POST | `/friends/requests/{id}/decline` | → 204 |
| DELETE | `/friends/requests/{id}` | requester cancels a pending request → 204 |
| DELETE | `/friends/{user_id}` | unfriend (also revokes location grants between you) → 204 |

## Group rides

| Method | Path | Notes |
|--------|------|-------|
| GET | `/rides?scope=discover\|mine&status=&near=lon,lat&radius_m=` | → `{"rides": [Ride]}`. `discover`: public, not ended/cancelled, live first. `mine`: rides you're in. Max 50 |
| POST | `/rides` | `{title (1–100), description? (≤1000), visibility: public\|private, scheduled_at?, start?{lat,lon}, destination?{lat,lon}, waypoints?}` → `Ride` |
| POST | `/rides/join` | `{join_code?}` (case-insensitive) or `{invite_token?}` → `Ride`. 404 not found, 409 `ride has ended`, 403 `you were removed from this ride` |
| GET | `/rides/{id}` | → `Ride` (private rides 404 for non-participants) |
| PATCH | `/rides/{id}` | host: `{title?, description?, visibility?, scheduled_at?}` → `Ride` |
| POST | `/rides/{id}/start` | host, scheduled → live → `Ride` |
| POST | `/rides/{id}/end` | host, live → ended → `Ride` |
| POST | `/rides/{id}/cancel` | host, scheduled → cancelled → `Ride` |
| POST | `/rides/{id}/leave` | participant → 204 (host: 400 `host cannot leave; end or cancel the ride`) |
| POST | `/rides/{id}/participants/{user_id}/remove` | host → 204 |
| PATCH | `/rides/{id}/me/status` | `{status: joined\|on_the_way\|riding\|paused\|reached}` → 204 |
| POST | `/rides/{id}/locations` | `{points: [LocationPoint]}` (≤500) → 204. Ride must be live (409 `ride not live`); duplicates are ignored |

## Location sharing

| Method | Path | Notes |
|--------|------|-------|
| POST | `/location-shares` | `{duration: 1h\|8h\|indefinite, friend_ids: [uuid]}` → `Share`. Only accepted friends are granted (400 `select at least one friend`). Ends your previous active share |
| GET | `/location-shares` | → `{"mine": [Share] (last 20), "shared_with_me": [Share] (active)}` |
| POST | `/location-shares/{id}/stop` | → 204 |
| DELETE | `/location-shares/{id}/grants/{friend_id}` | → 204 |
| POST | `/location-shares/{id}/locations` | `{points: [LocationPoint]}` → 204 |

## Community

| Method | Path | Notes |
|--------|------|-------|
| GET | `/posts?cursor=&limit=&author_id=` | → `{"posts": [Post], "next_cursor": string\|null}`; pass `next_cursor` back as `cursor` |
| POST | `/posts` | multipart: `images` (1–4, JPEG/PNG/WebP), `caption?` (≤2000), `ride_id?`, `distance_km?`, `duration_s?` → `Post` |
| GET | `/posts/{id}` | → `Post` |
| DELETE | `/posts/{id}` | author → 204 |
| POST | `/posts/{id}/like` | toggle → `{"liked": bool, "like_count": int}` |
| GET | `/posts/{id}/comments` | → `{"comments": [Comment]}` |
| POST | `/posts/{id}/comments` | `{body (1–1000)}` → `Comment` |
| DELETE | `/posts/{id}/comments/{comment_id}` | comment author or post author → 204 |
| GET | `/media/{path}` | authenticated file download (e.g. `thumbnails/…_thumb.jpg`) |

## WebSockets

Pass the access token as `?token=`. Server sends a ping every 25 s; clients may also send `{"type":"ping"}` and get `{"type":"pong"}`.

### `/ws/rides/{ride_id}` (participants only; 403 otherwise)

Client → server:

```json
{"type":"location","lat":0,"lon":0,"speed":0,"heading":0,"accuracy":0,"recorded_at":"RFC3339","status":"riding"}
{"type":"status","status":"paused"}
```

Server → client: `ride_status {status}`, `participant_update {user_id, lat, lon, status, last_seen_at, distance_to_host_m, distance_to_destination_m}` (status-only updates omit coordinates), `participant_joined {user_id, user}`, `participant_left {user_id}`, `participant_removed {user_id}`.

### `/ws/location-shares`

Client → server: `{"type":"location","share_id":"…","lat":0,"lon":0,"recorded_at":"RFC3339"}`

Server → client: `friend_location {share_id, user_id, lat, lon, last_seen_at, online:true}`, `share_ended {share_id}`.
