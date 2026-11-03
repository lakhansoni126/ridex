package handler

import (
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
	"github.com/lakhansoni126/ridex/backend/internal/middleware"
	"github.com/lakhansoni126/ridex/backend/internal/service"
)

func (a *API) listRides(c *gin.Context) {
	in := service.ListRidesInput{Scope: c.DefaultQuery("scope", "discover"), Status: c.Query("status")}
	if parts := strings.Split(c.Query("near"), ","); len(parts) == 2 {
		lon, err1 := strconv.ParseFloat(strings.TrimSpace(parts[0]), 64)
		lat, err2 := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
		if err1 != nil || err2 != nil {
			httpx.Fail(c, httpx.BadRequest("near must be lon,lat"))
			return
		}
		in.NearLon, in.NearLat = &lon, &lat
	}
	if r := queryFloat(c, "radius_m"); r != nil {
		in.RadiusM = *r
	}
	rides, err := a.Svc.ListRides(c.Request.Context(), middleware.UserID(c), in)
	respond(c, gin.H{"rides": rides}, err)
}

func (a *API) createRide(c *gin.Context) {
	var body struct {
		Title       string            `json:"title"`
		Description string            `json:"description"`
		Visibility  string            `json:"visibility"`
		ScheduledAt *time.Time        `json:"scheduled_at"`
		Start       *service.GeoPoint `json:"start"`
		Destination *service.GeoPoint `json:"destination"`
		Waypoints   []map[string]any  `json:"waypoints"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	ride, err := a.Svc.CreateRide(c.Request.Context(), middleware.UserID(c), service.CreateRideInput{
		Title: body.Title, Description: body.Description, Visibility: body.Visibility,
		ScheduledAt: body.ScheduledAt, Start: body.Start, Destination: body.Destination, Waypoints: body.Waypoints,
	})
	respond(c, ride, err)
}

func (a *API) joinRide(c *gin.Context) {
	var body struct {
		JoinCode    *string `json:"join_code"`
		InviteToken *string `json:"invite_token"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	code := ""
	if body.JoinCode != nil {
		code = *body.JoinCode
	}
	var invite *uuid.UUID
	if body.InviteToken != nil && strings.TrimSpace(*body.InviteToken) != "" {
		id, err := uuid.Parse(strings.TrimSpace(*body.InviteToken))
		if err != nil {
			httpx.Fail(c, httpx.NotFound("ride not found"))
			return
		}
		invite = &id
	}
	ride, err := a.Svc.JoinRide(c.Request.Context(), middleware.UserID(c), code, invite)
	respond(c, ride, err)
}

func (a *API) getRide(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	ride, err := a.Svc.GetRide(c.Request.Context(), middleware.UserID(c), id)
	respond(c, ride, err)
}

func (a *API) patchRide(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	var p struct {
		Title       *string    `json:"title"`
		Description *string    `json:"description"`
		Visibility  *string    `json:"visibility"`
		ScheduledAt *time.Time `json:"scheduled_at"`
	}
	if !httpx.Bind(c, &p) {
		return
	}
	ride, err := a.Svc.PatchRide(c.Request.Context(), middleware.UserID(c), id, service.PatchRideInput{
		Title: p.Title, Description: p.Description, Visibility: p.Visibility, ScheduledAt: p.ScheduledAt,
	})
	respond(c, ride, err)
}

type rideAction func(svc *service.Svc, c *gin.Context, me, id uuid.UUID) (service.Ride, error)

func (a *API) rideTransition(fn rideAction) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, ok := httpx.ParamUUID(c, "id")
		if !ok {
			return
		}
		ride, err := fn(a.Svc, c, middleware.UserID(c), id)
		respond(c, ride, err)
	}
}

func (a *API) startRide(c *gin.Context) {
	a.rideTransition(func(s *service.Svc, c *gin.Context, me, id uuid.UUID) (service.Ride, error) {
		return s.StartRide(c.Request.Context(), me, id)
	})(c)
}

func (a *API) endRide(c *gin.Context) {
	a.rideTransition(func(s *service.Svc, c *gin.Context, me, id uuid.UUID) (service.Ride, error) {
		return s.EndRide(c.Request.Context(), me, id)
	})(c)
}

func (a *API) cancelRide(c *gin.Context) {
	a.rideTransition(func(s *service.Svc, c *gin.Context, me, id uuid.UUID) (service.Ride, error) {
		return s.CancelRide(c.Request.Context(), me, id)
	})(c)
}

func (a *API) leaveRide(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	respondNoContent(c, a.Svc.LeaveRide(c.Request.Context(), middleware.UserID(c), id))
}

func (a *API) removeParticipant(c *gin.Context) {
	rid, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	uid, ok := httpx.ParamUUID(c, "user_id")
	if !ok {
		return
	}
	respondNoContent(c, a.Svc.RemoveParticipant(c.Request.Context(), middleware.UserID(c), rid, uid))
}

func (a *API) myStatus(c *gin.Context) {
	rid, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	var body struct {
		Status string `json:"status" binding:"required"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	respondNoContent(c, a.Svc.SetMyStatus(c.Request.Context(), middleware.UserID(c), rid, body.Status))
}

func (a *API) rideLocations(c *gin.Context) {
	rid, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	var body struct {
		Points []service.LocationPoint `json:"points"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	respondNoContent(c, a.Svc.IngestRideLocations(c.Request.Context(), middleware.UserID(c), rid, body.Points, false))
}

// ---- location shares ----

func (a *API) createShare(c *gin.Context) {
	var body struct {
		Duration  string      `json:"duration" binding:"required"`
		FriendIDs []uuid.UUID `json:"friend_ids"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	out, err := a.Svc.CreateShare(c.Request.Context(), middleware.UserID(c), body.Duration, body.FriendIDs)
	respond(c, out, err)
}

func (a *API) listShares(c *gin.Context) {
	out, err := a.Svc.ListShares(c.Request.Context(), middleware.UserID(c))
	respond(c, out, err)
}

func (a *API) stopShare(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	respondNoContent(c, a.Svc.StopShare(c.Request.Context(), middleware.UserID(c), id))
}

func (a *API) revokeGrant(c *gin.Context) {
	sid, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	fid, ok := httpx.ParamUUID(c, "friend_id")
	if !ok {
		return
	}
	respondNoContent(c, a.Svc.RevokeShareGrant(c.Request.Context(), middleware.UserID(c), sid, fid))
}

func (a *API) shareLocations(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	var body struct {
		Points []service.LocationPoint `json:"points"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	respondNoContent(c, a.Svc.IngestShareLocations(c.Request.Context(), middleware.UserID(c), id, body.Points, false))
}
