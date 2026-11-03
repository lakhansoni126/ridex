package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
	"github.com/lakhansoni126/ridex/backend/internal/service"
	"github.com/lakhansoni126/ridex/backend/internal/ws"
)

// Mobile clients send no Origin; auth is the token, so any origin is allowed.
var upgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

type wsMessage struct {
	Type       string   `json:"type"`
	Status     string   `json:"status"`
	ShareID    string   `json:"share_id"`
	Lat        *float64 `json:"lat"`
	Lon        *float64 `json:"lon"`
	Speed      *float64 `json:"speed"`
	Heading    *float64 `json:"heading"`
	Accuracy   *float64 `json:"accuracy"`
	RecordedAt string   `json:"recorded_at"`
}

func (m wsMessage) point() (service.LocationPoint, bool) {
	if m.Lat == nil || m.Lon == nil {
		return service.LocationPoint{}, false
	}
	pt := service.LocationPoint{Lat: *m.Lat, Lon: *m.Lon, SpeedMps: m.Speed, Heading: m.Heading, AccuracyM: m.Accuracy}
	if m.RecordedAt != "" {
		if t, err := time.Parse(time.RFC3339Nano, m.RecordedAt); err == nil {
			pt.RecordedAt = t
		}
	}
	if m.Status != "" {
		st := m.Status
		pt.Status = &st
	}
	return pt, true
}

func (a *API) wsAuth(c *gin.Context) (uuid.UUID, bool) {
	uid, err := a.Svc.AuthenticateAccess(c.Request.Context(), c.Query("token"))
	if err != nil {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"detail": "unauthorized"})
		return uuid.Nil, false
	}
	return uid, true
}

// serve upgrades, joins room and runs the read loop with handle per message.
func (a *API) serve(c *gin.Context, room string, handle func(ctx context.Context, cl *ws.Client, m wsMessage)) {
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	client := ws.NewClient(conn)
	a.Svc.Hub.Join(room, client)
	defer func() {
		a.Svc.Hub.Leave(room, client)
		client.Close()
	}()
	// The request context is cancelled once the handler returns; use a
	// detached context for DB work done on behalf of socket messages.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	for {
		b, err := client.Read()
		if err != nil {
			return
		}
		var m wsMessage
		if json.Unmarshal(b, &m) != nil {
			continue // ignore malformed frames, keep the socket
		}
		if m.Type == "ping" {
			client.Send(map[string]string{"type": "pong"})
			continue
		}
		mctx, mcancel := context.WithTimeout(ctx, 10*time.Second)
		handle(mctx, client, m)
		mcancel()
	}
}

func (a *API) wsRide(c *gin.Context) {
	uid, ok := a.wsAuth(c)
	if !ok {
		return
	}
	rideID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		httpx.Fail(c, httpx.NotFound("ride not found"))
		return
	}
	allowed, err := a.Svc.CanJoinRideSocket(c.Request.Context(), rideID, uid)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	if !allowed {
		c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"detail": "not a participant of this ride"})
		return
	}
	a.serve(c, rideID.String(), func(ctx context.Context, cl *ws.Client, m wsMessage) {
		switch m.Type {
		case "status":
			_ = a.Svc.SetMyStatus(ctx, uid, rideID, m.Status)
		case "location":
			if pt, ok := m.point(); ok {
				_ = a.Svc.IngestRideLocations(ctx, uid, rideID, []service.LocationPoint{pt}, true)
			}
		}
	})
}

func (a *API) wsShares(c *gin.Context) {
	uid, ok := a.wsAuth(c)
	if !ok {
		return
	}
	a.serve(c, "shares:"+uid.String(), func(ctx context.Context, cl *ws.Client, m wsMessage) {
		if m.Type != "location" {
			return
		}
		sid, err := uuid.Parse(m.ShareID)
		if err != nil {
			return
		}
		if pt, ok := m.point(); ok {
			pt.Status = nil
			_ = a.Svc.IngestShareLocations(ctx, uid, sid, []service.LocationPoint{pt}, true)
		}
	})
}
