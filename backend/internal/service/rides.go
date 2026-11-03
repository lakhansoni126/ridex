package service

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

// Participant statuses a rider may set on themselves.
var participantStatuses = map[string]bool{
	"joined": true, "on_the_way": true, "riding": true, "paused": true, "reached": true,
}

// ValidParticipantStatus reports whether st is settable by a participant.
func ValidParticipantStatus(st string) bool { return participantStatuses[st] }

func joinCode() string {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	b := make([]byte, 6)
	for i := range b {
		n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		b[i] = alphabet[n.Int64()]
	}
	return string(b)
}

// rideSelect needs $1 = viewer id.
const rideSelect = `
	SELECT r.id, r.host_id, h.username, h.display_name, h.avatar_path,
	       r.title, r.description, r.visibility, r.status, r.join_code, r.invite_token,
	       r.scheduled_at, r.started_at, r.ended_at, r.created_at, r.updated_at,
	       ST_Y(r.start_point::geometry), ST_X(r.start_point::geometry),
	       ST_Y(r.destination::geometry), ST_X(r.destination::geometry),
	       r.waypoints,
	       (SELECT count(*) FROM ride_participants p WHERE p.ride_id=r.id AND p.status NOT IN ('removed','left')),
	       COALESCE((SELECT p.status FROM ride_participants p WHERE p.ride_id=r.id AND p.user_id=$1), '')
	FROM rides r JOIN users h ON h.id=r.host_id`

func scanRide(row pgx.Row) (Ride, string, error) {
	var r Ride
	var code string
	var invite uuid.UUID
	var wp []byte
	var viewerStatus string
	err := row.Scan(&r.ID, &r.HostID, &r.Host.Username, &r.Host.DisplayName, &r.Host.AvatarPath,
		&r.Title, &r.Description, &r.Visibility, &r.Status, &code, &invite,
		&r.ScheduledAt, &r.StartedAt, &r.EndedAt, &r.CreatedAt, &r.UpdatedAt,
		&r.StartLat, &r.StartLon, &r.DestLat, &r.DestLon, &wp,
		&r.ParticipantCount, &viewerStatus)
	if err != nil {
		return r, "", err
	}
	r.Host.ID = r.HostID
	r.IsParticipant = viewerStatus != "" && viewerStatus != "removed" && viewerStatus != "left"
	if r.IsParticipant {
		inv := invite.String()
		r.JoinCode, r.InviteToken = &code, &inv
	}
	r.Waypoints = []map[string]any{}
	if len(wp) > 0 {
		_ = json.Unmarshal(wp, &r.Waypoints)
		if r.Waypoints == nil {
			r.Waypoints = []map[string]any{}
		}
	}
	r.Participants = []Participant{}
	return r, viewerStatus, nil
}

type CreateRideInput struct {
	Title       string
	Description string
	Visibility  string
	ScheduledAt *time.Time
	Start       *GeoPoint
	Destination *GeoPoint
	Waypoints   []map[string]any
}

func validVisibility(v string) bool { return v == "public" || v == "private" }

func (s *Svc) CreateRide(ctx context.Context, host uuid.UUID, in CreateRideInput) (Ride, error) {
	title, err := TrimmedText("title", in.Title, 1, 100)
	if err != nil {
		return Ride{}, err
	}
	desc, err := TrimmedText("description", in.Description, 0, 1000)
	if err != nil {
		return Ride{}, err
	}
	if in.Visibility == "" {
		in.Visibility = "public"
	}
	if !validVisibility(in.Visibility) {
		return Ride{}, httpx.BadRequest("visibility must be public or private")
	}
	var startWKT, destWKT *string
	if in.Start != nil {
		if !ValidCoord(in.Start.Lat, in.Start.Lon) {
			return Ride{}, httpx.BadRequest("invalid start coordinates")
		}
		w := pointWKT(in.Start.Lon, in.Start.Lat)
		startWKT = &w
	}
	if in.Destination != nil {
		if !ValidCoord(in.Destination.Lat, in.Destination.Lon) {
			return Ride{}, httpx.BadRequest("invalid destination coordinates")
		}
		w := pointWKT(in.Destination.Lon, in.Destination.Lat)
		destWKT = &w
	}
	if len(in.Waypoints) > 50 {
		return Ride{}, httpx.BadRequest("too many waypoints")
	}
	var wp []byte
	if in.Waypoints != nil {
		wp, _ = json.Marshal(in.Waypoints)
	}
	id := uuid.New()
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		var lastErr error
		for attempt := 0; attempt < 5; attempt++ {
			_, lastErr = tx.Exec(ctx, `SAVEPOINT ride_insert`)
			if lastErr != nil {
				return lastErr
			}
			_, lastErr = tx.Exec(ctx, `
				INSERT INTO rides(id,host_id,title,description,visibility,status,join_code,invite_token,scheduled_at,start_point,destination,waypoints)
				VALUES ($1,$2,$3,$4,$5,'scheduled',$6,$7,$8,
					CASE WHEN $9::text IS NULL THEN NULL ELSE ST_GeogFromText($9) END,
					CASE WHEN $10::text IS NULL THEN NULL ELSE ST_GeogFromText($10) END,
					$11)`,
				id, host, title, nullIfEmpty(desc), in.Visibility, joinCode(), uuid.New(), in.ScheduledAt, startWKT, destWKT, wp)
			if lastErr == nil {
				break
			}
			if _, rbErr := tx.Exec(ctx, `ROLLBACK TO SAVEPOINT ride_insert`); rbErr != nil {
				return rbErr
			}
			if !isUniqueViolation(lastErr) { // only retry join-code collisions
				return lastErr
			}
		}
		if lastErr != nil {
			return lastErr
		}
		_, err := tx.Exec(ctx, `
			INSERT INTO ride_participants(id,ride_id,user_id,role,status) VALUES ($1,$2,$3,'host','joined')`,
			uuid.New(), id, host)
		return err
	})
	if err != nil {
		return Ride{}, err
	}
	return s.GetRide(ctx, host, id)
}

func nullIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

type ListRidesInput struct {
	Scope   string // discover | mine
	Status  string
	NearLon *float64
	NearLat *float64
	RadiusM float64
}

func (s *Svc) ListRides(ctx context.Context, me uuid.UUID, in ListRidesInput) ([]Ride, error) {
	args := []any{me}
	var where []string
	order := ""
	switch in.Scope {
	case "", "discover":
		where = append(where, `r.visibility='public'`, `r.status NOT IN ('ended','cancelled')`)
		order = ` ORDER BY (r.status='live') DESC, r.scheduled_at ASC NULLS LAST, r.created_at DESC`
	case "mine":
		where = append(where, `EXISTS (SELECT 1 FROM ride_participants mp WHERE mp.ride_id=r.id AND mp.user_id=$1 AND mp.status NOT IN ('removed','left'))`)
		order = ` ORDER BY r.created_at DESC`
	default:
		return nil, httpx.BadRequest("scope must be discover or mine")
	}
	if in.Status != "" {
		switch in.Status {
		case "scheduled", "live", "ended", "cancelled":
		default:
			return nil, httpx.BadRequest("invalid status filter")
		}
		args = append(args, in.Status)
		where = append(where, fmt.Sprintf("r.status=$%d", len(args)))
	}
	if in.NearLon != nil && in.NearLat != nil {
		if !ValidCoord(*in.NearLat, *in.NearLon) {
			return nil, httpx.BadRequest("invalid near coordinates")
		}
		radius := in.RadiusM
		if radius <= 0 || radius > 500000 {
			radius = 50000
		}
		args = append(args, pointWKT(*in.NearLon, *in.NearLat), radius)
		where = append(where, fmt.Sprintf("r.start_point IS NOT NULL AND ST_DWithin(r.start_point, ST_GeogFromText($%d), $%d)", len(args)-1, len(args)))
	}
	q := rideSelect + " WHERE " + strings.Join(where, " AND ") + order + " LIMIT 50"
	rows, err := s.DB.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Ride{}
	for rows.Next() {
		r, _, err := scanRide(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// GetRide returns a ride visible to viewer (private rides only to participants).
func (s *Svc) GetRide(ctx context.Context, viewer, id uuid.UUID) (Ride, error) {
	r, _, err := scanRide(s.DB.QueryRow(ctx, rideSelect+` WHERE r.id=$2`, viewer, id))
	if isNoRows(err) {
		return r, httpx.NotFound("ride not found")
	}
	if err != nil {
		return r, err
	}
	if r.Visibility != "public" && !r.IsParticipant {
		return Ride{}, httpx.NotFound("ride not found")
	}
	parts, err := s.participants(ctx, id)
	if err != nil {
		return r, err
	}
	r.Participants = parts
	return r, nil
}

func (s *Svc) participants(ctx context.Context, rideID uuid.UUID) ([]Participant, error) {
	rows, err := s.DB.Query(ctx, `
		SELECT p.id, p.ride_id, p.user_id, p.role, p.status, p.last_seen_at,
		       p.distance_to_host_m, p.distance_to_destination_m, p.joined_at,
		       ST_Y(p.last_location::geometry), ST_X(p.last_location::geometry),
		       u.username, u.display_name, u.avatar_path
		FROM ride_participants p
		JOIN users u ON u.id = p.user_id
		WHERE p.ride_id=$1 AND p.status NOT IN ('removed','left')
		ORDER BY (p.role='host') DESC, p.joined_at`, rideID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Participant{}
	for rows.Next() {
		var p Participant
		u := UserPublic{}
		if err := rows.Scan(&p.ID, &p.RideID, &p.UserID, &p.Role, &p.Status, &p.LastSeenAt,
			&p.DistanceToHostM, &p.DistanceToDestinationM, &p.JoinedAt, &p.Lat, &p.Lon,
			&u.Username, &u.DisplayName, &u.AvatarPath); err != nil {
			return nil, err
		}
		u.ID = p.UserID
		p.User = &u
		out = append(out, p)
	}
	return out, rows.Err()
}

// participantStatus returns my status on a ride ("" when not a participant).
func (s *Svc) participantStatus(ctx context.Context, rideID, me uuid.UUID) (string, error) {
	var st string
	err := s.DB.QueryRow(ctx, `SELECT status FROM ride_participants WHERE ride_id=$1 AND user_id=$2`, rideID, me).Scan(&st)
	if isNoRows(err) {
		return "", nil
	}
	return st, err
}

// CanJoinRideSocket reports whether me may subscribe to the ride's live feed.
func (s *Svc) CanJoinRideSocket(ctx context.Context, rideID, me uuid.UUID) (bool, error) {
	st, err := s.participantStatus(ctx, rideID, me)
	if err != nil {
		return false, err
	}
	return st != "" && st != "removed" && st != "left", nil
}

func (s *Svc) JoinRide(ctx context.Context, me uuid.UUID, code string, invite *uuid.UUID) (Ride, error) {
	var id uuid.UUID
	var status string
	var err error
	code = strings.ToUpper(strings.TrimSpace(code))
	switch {
	case code != "":
		err = s.DB.QueryRow(ctx, `SELECT id, status FROM rides WHERE join_code=$1`, code).Scan(&id, &status)
	case invite != nil:
		err = s.DB.QueryRow(ctx, `SELECT id, status FROM rides WHERE invite_token=$1`, *invite).Scan(&id, &status)
	default:
		return Ride{}, httpx.BadRequest("join_code or invite_token required")
	}
	if isNoRows(err) {
		return Ride{}, httpx.NotFound("ride not found")
	}
	if err != nil {
		return Ride{}, err
	}
	if status == "ended" || status == "cancelled" {
		return Ride{}, httpx.Conflict("ride has ended")
	}
	prev, err := s.participantStatus(ctx, id, me)
	if err != nil {
		return Ride{}, err
	}
	switch prev {
	case "removed":
		return Ride{}, httpx.Forbidden("you were removed from this ride")
	case "":
		_, err = s.DB.Exec(ctx, `
			INSERT INTO ride_participants(id,ride_id,user_id,role,status)
			VALUES ($1,$2,$3,'participant','joined')
			ON CONFLICT (ride_id, user_id) DO NOTHING`, uuid.New(), id, me)
	case "left":
		_, err = s.DB.Exec(ctx, `
			UPDATE ride_participants SET status='joined', joined_at=now() WHERE ride_id=$1 AND user_id=$2 AND status='left'`, id, me)
	}
	if err != nil {
		return Ride{}, err
	}
	if prev == "" || prev == "left" {
		if u, err := s.getUser(ctx, me); err == nil {
			s.Hub.Broadcast(id.String(), map[string]any{"type": "participant_joined", "user_id": me.String(), "user": u.Public()})
		}
	}
	return s.GetRide(ctx, me, id)
}

func (s *Svc) assertHost(ctx context.Context, rideID, me uuid.UUID) (string, error) {
	var host uuid.UUID
	var status, visibility string
	if err := s.DB.QueryRow(ctx, `SELECT host_id, status, visibility FROM rides WHERE id=$1`, rideID).Scan(&host, &status, &visibility); err != nil {
		if isNoRows(err) {
			return "", httpx.NotFound("ride not found")
		}
		return "", err
	}
	if host != me {
		if visibility != "public" {
			if ok, _ := s.CanJoinRideSocket(ctx, rideID, me); !ok {
				return "", httpx.NotFound("ride not found")
			}
		}
		return "", httpx.Forbidden("only the host can do that")
	}
	return status, nil
}

// transition moves a ride from one of `from` to `to` (host only).
func (s *Svc) transition(ctx context.Context, me, rideID uuid.UUID, from []string, to, setCol, errMsg string) (Ride, error) {
	status, err := s.assertHost(ctx, rideID, me)
	if err != nil {
		return Ride{}, err
	}
	ok := false
	for _, f := range from {
		if status == f {
			ok = true
		}
	}
	if !ok {
		return Ride{}, httpx.Conflict(errMsg)
	}
	q := `UPDATE rides SET status=$2, updated_at=now()`
	if setCol != "" {
		q += `, ` + setCol + `=now()`
	}
	q += ` WHERE id=$1 AND status = ANY($3::text[])`
	tag, err := s.DB.Exec(ctx, q, rideID, to, from)
	if err != nil {
		return Ride{}, err
	}
	if tag.RowsAffected() == 0 {
		return Ride{}, httpx.Conflict(errMsg)
	}
	s.Hub.Broadcast(rideID.String(), map[string]any{"type": "ride_status", "status": to})
	return s.GetRide(ctx, me, rideID)
}

func (s *Svc) StartRide(ctx context.Context, me, rideID uuid.UUID) (Ride, error) {
	return s.transition(ctx, me, rideID, []string{"scheduled"}, "live", "started_at", "ride can only be started once, from scheduled")
}

func (s *Svc) EndRide(ctx context.Context, me, rideID uuid.UUID) (Ride, error) {
	return s.transition(ctx, me, rideID, []string{"live"}, "ended", "ended_at", "only a live ride can be ended")
}

func (s *Svc) CancelRide(ctx context.Context, me, rideID uuid.UUID) (Ride, error) {
	return s.transition(ctx, me, rideID, []string{"scheduled"}, "cancelled", "ended_at", "only a scheduled ride can be cancelled")
}

type PatchRideInput struct {
	Title       *string
	Description *string
	Visibility  *string
	ScheduledAt *time.Time
}

func (s *Svc) PatchRide(ctx context.Context, me, rideID uuid.UUID, in PatchRideInput) (Ride, error) {
	if _, err := s.assertHost(ctx, rideID, me); err != nil {
		return Ride{}, err
	}
	if in.Title != nil {
		v, err := TrimmedText("title", *in.Title, 1, 100)
		if err != nil {
			return Ride{}, err
		}
		in.Title = &v
	}
	setDesc := in.Description != nil
	var desc any
	if in.Description != nil {
		v, err := TrimmedText("description", *in.Description, 0, 1000)
		if err != nil {
			return Ride{}, err
		}
		if v != "" {
			desc = v
		}
	}
	if in.Visibility != nil && !validVisibility(*in.Visibility) {
		return Ride{}, httpx.BadRequest("visibility must be public or private")
	}
	_, err := s.DB.Exec(ctx, `
		UPDATE rides SET
			title = COALESCE($2, title),
			description = CASE WHEN $3 THEN $4::text ELSE description END,
			visibility = COALESCE($5, visibility),
			scheduled_at = COALESCE($6, scheduled_at),
			updated_at = now()
		WHERE id=$1`, rideID, in.Title, setDesc, desc, in.Visibility, in.ScheduledAt)
	if err != nil {
		return Ride{}, err
	}
	return s.GetRide(ctx, me, rideID)
}

func (s *Svc) LeaveRide(ctx context.Context, me, rideID uuid.UUID) error {
	var host uuid.UUID
	if err := s.DB.QueryRow(ctx, `SELECT host_id FROM rides WHERE id=$1`, rideID).Scan(&host); err != nil {
		if isNoRows(err) {
			return httpx.NotFound("ride not found")
		}
		return err
	}
	if host == me {
		return httpx.BadRequest("host cannot leave; end or cancel the ride")
	}
	tag, err := s.DB.Exec(ctx, `
		UPDATE ride_participants SET status='left'
		WHERE ride_id=$1 AND user_id=$2 AND status NOT IN ('removed','left')`, rideID, me)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.NotFound("you are not in this ride")
	}
	s.Hub.Broadcast(rideID.String(), map[string]any{"type": "participant_left", "user_id": me.String()})
	return nil
}

func (s *Svc) RemoveParticipant(ctx context.Context, me, rideID, userID uuid.UUID) error {
	if _, err := s.assertHost(ctx, rideID, me); err != nil {
		return err
	}
	if userID == me {
		return httpx.BadRequest("host cannot remove themselves")
	}
	tag, err := s.DB.Exec(ctx, `
		UPDATE ride_participants SET status='removed' WHERE ride_id=$1 AND user_id=$2 AND status <> 'removed'`, rideID, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.NotFound("participant not found")
	}
	s.Hub.Broadcast(rideID.String(), map[string]any{"type": "participant_removed", "user_id": userID.String()})
	return nil
}

func (s *Svc) SetMyStatus(ctx context.Context, me, rideID uuid.UUID, status string) error {
	if !ValidParticipantStatus(status) {
		return httpx.BadRequest("status must be one of joined, on_the_way, riding, paused, reached")
	}
	tag, err := s.DB.Exec(ctx, `
		UPDATE ride_participants SET status=$3
		WHERE ride_id=$1 AND user_id=$2 AND status NOT IN ('removed','left')`,
		rideID, me, status)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.NotFound("you are not in this ride")
	}
	s.Hub.Broadcast(rideID.String(), map[string]any{"type": "participant_update", "user_id": me.String(), "status": status})
	return nil
}
