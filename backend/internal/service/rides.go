package service

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

func joinCode() string {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	b := make([]byte, 6)
	for i := range b {
		n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		b[i] = alphabet[n.Int64()]
	}
	return string(b)
}

func (s *Svc) CreateRide(ctx context.Context, host uuid.UUID, title, desc, visibility string, scheduled *time.Time, start, dest *GeoPoint, waypoints []map[string]any) (Ride, error) {
	if visibility == "" {
		visibility = "public"
	}
	id, token := uuid.New(), uuid.New()
	code := joinCode()
	var wp any
	if waypoints != nil {
		b, _ := json.Marshal(waypoints)
		wp = b
	}
	var startWKT, destWKT *string
	if start != nil {
		w := pointWKT(start.Lon, start.Lat)
		startWKT = &w
	}
	if dest != nil {
		w := pointWKT(dest.Lon, dest.Lat)
		destWKT = &w
	}
	_, err := s.DB.Exec(ctx, `
		INSERT INTO rides(id,host_id,title,description,visibility,status,join_code,invite_token,scheduled_at,start_point,destination,waypoints)
		VALUES ($1,$2,$3,$4,$5,'scheduled',$6,$7,$8,
			CASE WHEN $9::text IS NULL THEN NULL ELSE ST_GeogFromText($9) END,
			CASE WHEN $10::text IS NULL THEN NULL ELSE ST_GeogFromText($10) END,
			$11)`,
		id, host, title, nullIfEmpty(desc), visibility, code, token, scheduled, startWKT, destWKT, wp)
	if err != nil {
		return Ride{}, err
	}
	_, _ = s.DB.Exec(ctx, `
		INSERT INTO ride_participants(id,ride_id,user_id,role,status) VALUES ($1,$2,$3,'host','joined')`,
		uuid.New(), id, host)
	return s.GetRide(ctx, host, id)
}

func nullIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func (s *Svc) ListRides(ctx context.Context, status string, nearLon, nearLat *float64, radiusM float64) ([]Ride, error) {
	q := `
		SELECT id, host_id, title, description, visibility, status, join_code, invite_token,
		       scheduled_at, started_at, ended_at, created_at, updated_at,
		       ST_Y(start_point::geometry), ST_X(start_point::geometry),
		       ST_Y(destination::geometry), ST_X(destination::geometry)
		FROM rides WHERE visibility='public'`
	args := []any{}
	if status != "" {
		args = append(args, status)
		q += fmt.Sprintf(" AND status=$%d", len(args))
	}
	if nearLon != nil && nearLat != nil {
		args = append(args, pointWKT(*nearLon, *nearLat), radiusM)
		q += fmt.Sprintf(" AND start_point IS NOT NULL AND ST_DWithin(start_point, ST_GeogFromText($%d), $%d)", len(args)-1, len(args))
	}
	q += " ORDER BY created_at DESC LIMIT 50"
	rows, err := s.DB.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Ride
	for rows.Next() {
		r, err := scanRide(rows)
		if err != nil {
			return nil, err
		}
		r.Participants = []Participant{}
		out = append(out, r)
	}
	if out == nil {
		out = []Ride{}
	}
	return out, nil
}

type scannable interface {
	Scan(dest ...any) error
}

func scanRide(row scannable) (Ride, error) {
	var r Ride
	var wp []byte
	err := row.Scan(&r.ID, &r.HostID, &r.Title, &r.Description, &r.Visibility, &r.Status, &r.JoinCode, &r.InviteToken,
		&r.ScheduledAt, &r.StartedAt, &r.EndedAt, &r.CreatedAt, &r.UpdatedAt,
		&r.StartLat, &r.StartLon, &r.DestLat, &r.DestLon)
	_ = wp
	return r, err
}

func (s *Svc) GetRide(ctx context.Context, viewer, id uuid.UUID) (Ride, error) {
	row := s.DB.QueryRow(ctx, `
		SELECT id, host_id, title, description, visibility, status, join_code, invite_token,
		       scheduled_at, started_at, ended_at, created_at, updated_at,
		       ST_Y(start_point::geometry), ST_X(start_point::geometry),
		       ST_Y(destination::geometry), ST_X(destination::geometry)
		FROM rides WHERE id=$1`, id)
	r, err := scanRide(row)
	if err == pgx.ErrNoRows {
		return r, httpx.E(http.StatusNotFound, "ride not found")
	}
	if err != nil {
		return r, err
	}
	parts, err := s.participants(ctx, id)
	if err != nil {
		return r, err
	}
	r.Participants = parts
	if r.Waypoints == nil {
		r.Waypoints = []map[string]any{}
	}
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
		WHERE p.ride_id=$1`, rideID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Participant
	for rows.Next() {
		var p Participant
		var uname, dname string
		var avatar *string
		if err := rows.Scan(&p.ID, &p.RideID, &p.UserID, &p.Role, &p.Status, &p.LastSeenAt,
			&p.DistanceToHostM, &p.DistanceToDestinationM, &p.JoinedAt, &p.Lat, &p.Lon,
			&uname, &dname, &avatar); err != nil {
			return nil, err
		}
		p.User = &UserPublic{ID: p.UserID, Username: uname, DisplayName: dname, AvatarPath: avatar}
		out = append(out, p)
	}
	if out == nil {
		out = []Participant{}
	}
	return out, nil
}

func (s *Svc) JoinRide(ctx context.Context, me uuid.UUID, code string, invite *uuid.UUID) (Ride, error) {
	var id uuid.UUID
	var err error
	if code != "" {
		err = s.DB.QueryRow(ctx, `SELECT id FROM rides WHERE join_code=$1`, code).Scan(&id)
	} else if invite != nil {
		err = s.DB.QueryRow(ctx, `SELECT id FROM rides WHERE invite_token=$1`, *invite).Scan(&id)
	} else {
		return Ride{}, httpx.E(http.StatusBadRequest, "join_code or invite_token required")
	}
	if err != nil {
		return Ride{}, httpx.E(http.StatusNotFound, "ride not found")
	}
	_, _ = s.DB.Exec(ctx, `
		INSERT INTO ride_participants(id,ride_id,user_id,role,status)
		VALUES ($1,$2,$3,'participant','joined')
		ON CONFLICT (ride_id, user_id) DO NOTHING`, uuid.New(), id, me)
	return s.GetRide(ctx, me, id)
}

func (s *Svc) assertHost(ctx context.Context, rideID, me uuid.UUID) error {
	var host uuid.UUID
	if err := s.DB.QueryRow(ctx, `SELECT host_id FROM rides WHERE id=$1`, rideID).Scan(&host); err != nil {
		return httpx.E(http.StatusNotFound, "ride not found")
	}
	if host != me {
		return httpx.E(http.StatusForbidden, "host only")
	}
	return nil
}

func (s *Svc) StartRide(ctx context.Context, me, rideID uuid.UUID) (Ride, error) {
	if err := s.assertHost(ctx, rideID, me); err != nil {
		return Ride{}, err
	}
	_, err := s.DB.Exec(ctx, `UPDATE rides SET status='live', started_at=now(), updated_at=now() WHERE id=$1`, rideID)
	if err != nil {
		return Ride{}, err
	}
	s.Hub.Broadcast(rideID.String(), map[string]any{"type": "ride_status", "status": "live"})
	return s.GetRide(ctx, me, rideID)
}

func (s *Svc) EndRide(ctx context.Context, me, rideID uuid.UUID) (Ride, error) {
	if err := s.assertHost(ctx, rideID, me); err != nil {
		return Ride{}, err
	}
	_, err := s.DB.Exec(ctx, `UPDATE rides SET status='ended', ended_at=now(), updated_at=now() WHERE id=$1`, rideID)
	if err != nil {
		return Ride{}, err
	}
	s.Hub.Broadcast(rideID.String(), map[string]any{"type": "ride_status", "status": "ended"})
	return s.GetRide(ctx, me, rideID)
}

func (s *Svc) PatchRide(ctx context.Context, me, rideID uuid.UUID, title, desc, visibility, status *string) (Ride, error) {
	if err := s.assertHost(ctx, rideID, me); err != nil {
		return Ride{}, err
	}
	_, err := s.DB.Exec(ctx, `
		UPDATE rides SET
			title = COALESCE($2, title),
			description = COALESCE($3, description),
			visibility = COALESCE($4, visibility),
			status = COALESCE($5, status),
			updated_at = now()
		WHERE id=$1`, rideID, title, desc, visibility, status)
	if err != nil {
		return Ride{}, err
	}
	return s.GetRide(ctx, me, rideID)
}

func (s *Svc) RemoveParticipant(ctx context.Context, me, rideID, userID uuid.UUID) error {
	if err := s.assertHost(ctx, rideID, me); err != nil {
		return err
	}
	_, err := s.DB.Exec(ctx, `UPDATE ride_participants SET status='removed' WHERE ride_id=$1 AND user_id=$2`, rideID, userID)
	s.Hub.Broadcast(rideID.String(), map[string]any{"type": "participant_removed", "user_id": userID.String()})
	return err
}

func (s *Svc) SetMyStatus(ctx context.Context, me, rideID uuid.UUID, status string) error {
	tag, err := s.DB.Exec(ctx, `
		UPDATE ride_participants SET status=$3 WHERE ride_id=$1 AND user_id=$2 AND status <> 'removed'`,
		rideID, me, status)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.E(http.StatusNotFound, "not a participant")
	}
	s.Hub.Broadcast(rideID.String(), map[string]any{"type": "participant_update", "user_id": me.String(), "status": status})
	return nil
}
