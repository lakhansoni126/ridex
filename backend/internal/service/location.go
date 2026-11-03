package service

import (
	"context"
	"net/http"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

// MaxBatchPoints caps one REST location upload.
const MaxBatchPoints = 500

var errRateLimited = httpx.E(http.StatusTooManyRequests, "rate limited")

// normalizePoints validates coordinates, fills/clamps timestamps and sorts by time.
func normalizePoints(points []LocationPoint) ([]LocationPoint, error) {
	if len(points) > MaxBatchPoints {
		return nil, httpx.BadRequest("too many points in one batch (max 500)")
	}
	now := time.Now().UTC()
	out := make([]LocationPoint, 0, len(points))
	for _, p := range points {
		if !ValidCoord(p.Lat, p.Lon) {
			return nil, httpx.BadRequest("invalid coordinates")
		}
		if p.RecordedAt.IsZero() || p.RecordedAt.After(now.Add(5*time.Minute)) {
			p.RecordedAt = now
		}
		p.RecordedAt = p.RecordedAt.UTC()
		out = append(out, p)
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].RecordedAt.Before(out[j].RecordedAt) })
	return out, nil
}

// insertLocationPoints bulk-inserts points, silently skipping duplicates
// (the same sample may arrive over both WS and REST batch sync).
func (s *Svc) insertLocationPoints(ctx context.Context, tx pgx.Tx, me uuid.UUID, rideID, shareID *uuid.UUID, points []LocationPoint) error {
	n := len(points)
	lats, lons := make([]float64, n), make([]float64, n)
	spd, hd, acc := make([]*float64, n), make([]*float64, n), make([]*float64, n)
	ts := make([]time.Time, n)
	for i, p := range points {
		lats[i], lons[i], spd[i], hd[i], acc[i], ts[i] = p.Lat, p.Lon, p.SpeedMps, p.Heading, p.AccuracyM, p.RecordedAt
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO location_points(user_id, ride_id, location_share_id, geom, speed_mps, heading, accuracy_m, recorded_at)
		SELECT $1::uuid, $2::uuid, $3::uuid, ST_SetSRID(ST_MakePoint(x.lon, x.lat), 4326)::geography, x.spd, x.hd, x.acc, x.t
		FROM unnest($4::float8[], $5::float8[], $6::float8[], $7::float8[], $8::float8[], $9::timestamptz[])
		     AS x(lat, lon, spd, hd, acc, t)
		ON CONFLICT DO NOTHING`,
		me, rideID, shareID, lats, lons, spd, hd, acc, ts)
	return err
}

// IngestRideLocations stores points and updates the participant snapshot.
// Shared by REST batch sync (fromWS=false) and live WS messages (fromWS=true,
// rate limited).
func (s *Svc) IngestRideLocations(ctx context.Context, me, rideID uuid.UUID, points []LocationPoint, fromWS bool) error {
	if len(points) == 0 {
		return nil
	}
	if fromWS && !s.wsLocation.Allow("ride:"+rideID.String()+":"+me.String()) {
		return errRateLimited
	}
	points, err := normalizePoints(points)
	if err != nil {
		return err
	}
	var rideStatus, partStatus string
	err = s.DB.QueryRow(ctx, `
		SELECT r.status, p.status FROM rides r
		JOIN ride_participants p ON p.ride_id=r.id AND p.user_id=$2
		WHERE r.id=$1`, rideID, me).Scan(&rideStatus, &partStatus)
	if isNoRows(err) || partStatus == "removed" || partStatus == "left" {
		return httpx.Forbidden("you are not in this ride")
	}
	if err != nil {
		return err
	}
	if rideStatus != "live" {
		return httpx.Conflict("ride not live")
	}

	last := points[len(points)-1]
	var newStatus *string
	if last.Status != nil && ValidParticipantStatus(*last.Status) {
		newStatus = last.Status
	}
	var distHost, distDest *float64
	var status string
	var updated bool
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		rid := rideID
		if err := s.insertLocationPoints(ctx, tx, me, &rid, nil, points); err != nil {
			return err
		}
		err := tx.QueryRow(ctx, `
			UPDATE ride_participants SET
				last_location = ST_GeogFromText($3),
				last_seen_at = $4,
				status = COALESCE($5, status),
				distance_to_host_m = ST_Distance(
					ST_GeogFromText($3),
					(SELECT last_location FROM ride_participants WHERE ride_id=$1 AND role='host')
				),
				distance_to_destination_m = ST_Distance(
					ST_GeogFromText($3),
					(SELECT destination FROM rides WHERE id=$1)
				)
			WHERE ride_id=$1 AND user_id=$2 AND (last_seen_at IS NULL OR last_seen_at <= $4)
			RETURNING status, distance_to_host_m, distance_to_destination_m`,
			rideID, me, pointWKT(last.Lon, last.Lat), last.RecordedAt, newStatus,
		).Scan(&status, &distHost, &distDest)
		if isNoRows(err) {
			return nil // older than the snapshot we already have
		}
		if err == nil {
			updated = true
		}
		return err
	})
	if err != nil {
		return err
	}
	if updated {
		s.Hub.Broadcast(rideID.String(), map[string]any{
			"type":                      "participant_update",
			"user_id":                   me.String(),
			"lat":                       last.Lat,
			"lon":                       last.Lon,
			"status":                    status,
			"last_seen_at":              last.RecordedAt.Format(time.RFC3339Nano),
			"distance_to_host_m":        distHost,
			"distance_to_destination_m": distDest,
		})
	}
	return nil
}

// IngestShareLocations stores points for my active location share.
func (s *Svc) IngestShareLocations(ctx context.Context, me, shareID uuid.UUID, points []LocationPoint, fromWS bool) error {
	if len(points) == 0 {
		return nil
	}
	if fromWS && !s.wsLocation.Allow("share:"+shareID.String()+":"+me.String()) {
		return errRateLimited
	}
	points, err := normalizePoints(points)
	if err != nil {
		return err
	}
	var owner uuid.UUID
	var active bool
	err = s.DB.QueryRow(ctx, `
		SELECT owner_id, is_active AND (expires_at IS NULL OR expires_at > now())
		FROM location_shares WHERE id=$1`, shareID,
	).Scan(&owner, &active)
	if isNoRows(err) || (err == nil && owner != me) {
		return httpx.NotFound("share not found")
	}
	if err != nil {
		return err
	}
	if !active {
		return httpx.Conflict("share not active")
	}
	last := points[len(points)-1]
	var updated bool
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		sid := shareID
		if err := s.insertLocationPoints(ctx, tx, me, nil, &sid, points); err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `
			UPDATE location_shares SET last_location=ST_GeogFromText($2), last_seen_at=$3
			WHERE id=$1 AND (last_seen_at IS NULL OR last_seen_at <= $3)`,
			shareID, pointWKT(last.Lon, last.Lat), last.RecordedAt)
		updated = err == nil && tag.RowsAffected() > 0
		return err
	})
	if err != nil || !updated {
		return err
	}
	msg := map[string]any{
		"type":         "friend_location",
		"share_id":     shareID.String(),
		"user_id":      me.String(),
		"lat":          last.Lat,
		"lon":          last.Lon,
		"last_seen_at": last.RecordedAt.Format(time.RFC3339Nano),
		"online":       true,
	}
	for _, fid := range s.activeGrantees(ctx, shareID) {
		s.Hub.Broadcast("shares:"+fid.String(), msg)
	}
	return nil
}

func (s *Svc) activeGrantees(ctx context.Context, shareID uuid.UUID) []uuid.UUID {
	rows, err := s.DB.Query(ctx, `
		SELECT friend_user_id FROM location_share_grants WHERE share_id=$1 AND revoked_at IS NULL`, shareID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		if rows.Scan(&id) == nil {
			out = append(out, id)
		}
	}
	return out
}
