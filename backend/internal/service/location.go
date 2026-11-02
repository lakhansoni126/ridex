package service

import (
	"context"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

// IngestRideLocations stores batched points and updates the participant snapshot (reused by REST + WS).
func (s *Svc) IngestRideLocations(ctx context.Context, me, rideID uuid.UUID, points []LocationPoint) error {
	if len(points) == 0 {
		return nil
	}
	if !s.AllowLocation(me, 2*time.Second) {
		return httpx.E(http.StatusTooManyRequests, "rate limited")
	}
	last := points[len(points)-1]
	for _, p := range points {
		_, err := s.DB.Exec(ctx, `
			INSERT INTO location_points(user_id, ride_id, geom, speed_mps, heading, accuracy_m, recorded_at)
			VALUES ($1,$2,ST_GeogFromText($3),$4,$5,$6,$7)`,
			me, rideID, pointWKT(p.Lon, p.Lat), p.SpeedMps, p.Heading, p.AccuracyM, p.RecordedAt)
		if err != nil {
			return err
		}
	}
	status := "riding"
	if last.Status != nil {
		status = *last.Status
	}
	_, err := s.DB.Exec(ctx, `
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
		WHERE ride_id=$1 AND user_id=$2`,
		rideID, me, pointWKT(last.Lon, last.Lat), last.RecordedAt, status)
	if err != nil {
		return err
	}

	var distHost, distDest *float64
	_ = s.DB.QueryRow(ctx, `
		SELECT distance_to_host_m, distance_to_destination_m FROM ride_participants
		WHERE ride_id=$1 AND user_id=$2`, rideID, me).Scan(&distHost, &distDest)

	s.Hub.Broadcast(rideID.String(), map[string]any{
		"type":                        "participant_update",
		"user_id":                     me.String(),
		"lat":                         last.Lat,
		"lon":                         last.Lon,
		"status":                      status,
		"last_seen_at":                last.RecordedAt.UTC().Format(time.RFC3339),
		"distance_to_host_m":          distHost,
		"distance_to_destination_m":   distDest,
	})
	return nil
}

// IngestShareLocations stores points for a location share (reused by REST + WS).
func (s *Svc) IngestShareLocations(ctx context.Context, me, shareID uuid.UUID, points []LocationPoint) error {
	if len(points) == 0 {
		return nil
	}
	if !s.AllowLocation(me, 2*time.Second) {
		return httpx.E(http.StatusTooManyRequests, "rate limited")
	}
	var owner uuid.UUID
	var active bool
	err := s.DB.QueryRow(ctx, `
		SELECT owner_id, is_active FROM location_shares
		WHERE id=$1 AND (expires_at IS NULL OR expires_at > now())`, shareID,
	).Scan(&owner, &active)
	if err != nil || !active || owner != me {
		return httpx.E(http.StatusForbidden, "share not active")
	}
	last := points[len(points)-1]
	for _, p := range points {
		_, err := s.DB.Exec(ctx, `
			INSERT INTO location_points(user_id, location_share_id, geom, speed_mps, heading, accuracy_m, recorded_at)
			VALUES ($1,$2,ST_GeogFromText($3),$4,$5,$6,$7)`,
			me, shareID, pointWKT(p.Lon, p.Lat), p.SpeedMps, p.Heading, p.AccuracyM, p.RecordedAt)
		if err != nil {
			return err
		}
	}
	_, err = s.DB.Exec(ctx, `
		UPDATE location_shares SET last_location=ST_GeogFromText($2), last_seen_at=$3 WHERE id=$1`,
		shareID, pointWKT(last.Lon, last.Lat), last.RecordedAt)
	if err != nil {
		return err
	}
	msg := map[string]any{
		"type":         "friend_location",
		"share_id":     shareID.String(),
		"user_id":      me.String(),
		"lat":          last.Lat,
		"lon":          last.Lon,
		"last_seen_at": last.RecordedAt.UTC().Format(time.RFC3339),
		"online":       true,
	}
	rows, _ := s.DB.Query(ctx, `
		SELECT friend_user_id FROM location_share_grants WHERE share_id=$1 AND revoked_at IS NULL`, shareID)
	if rows != nil {
		defer rows.Close()
		for rows.Next() {
			var fid uuid.UUID
			_ = rows.Scan(&fid)
			s.Hub.Broadcast("shares:"+fid.String(), msg)
		}
	}
	return nil
}
