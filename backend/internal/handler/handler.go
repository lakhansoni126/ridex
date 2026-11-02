package handler

import (
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
	"github.com/lakhansoni126/ridex/backend/internal/middleware"
	"github.com/lakhansoni126/ridex/backend/internal/service"
)

type API struct{ Svc *service.Svc }

var upgrader = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}

func (a *API) Mount(r *gin.Engine) {
	r.GET("/health", func(c *gin.Context) { c.JSON(200, gin.H{"status": "ok", "service": "RideX"}) })

	v1 := r.Group("/api/v1")
	v1.POST("/auth/register", a.register)
	v1.POST("/auth/login", a.login)
	v1.POST("/auth/refresh", a.refresh)
	v1.POST("/auth/logout", a.logout)

	api := v1.Group("")
	api.Use(middleware.Auth(a.Svc))
	{
		api.GET("/users/me", a.me)
		api.PATCH("/users/me", a.patchMe)

		api.GET("/friends", a.friends)
		api.GET("/friends/requests", a.friendRequests)
		api.POST("/friends/requests", a.requestFriend)
		api.POST("/friends/requests/:id/accept", a.acceptFriend)
		api.POST("/friends/requests/:id/decline", a.declineFriend)
		api.DELETE("/friends/:user_id", a.unfriend)

		api.GET("/rides", a.listRides)
		api.POST("/rides", a.createRide)
		api.POST("/rides/join", a.joinRide)
		api.GET("/rides/:id", a.getRide)
		api.PATCH("/rides/:id", a.patchRide)
		api.POST("/rides/:id/start", a.startRide)
		api.POST("/rides/:id/end", a.endRide)
		api.POST("/rides/:id/participants/:user_id/remove", a.removeParticipant)
		api.PATCH("/rides/:id/me/status", a.myStatus)
		api.POST("/rides/:id/locations", a.rideLocations)

		api.POST("/location-shares", a.createShare)
		api.GET("/location-shares", a.listShares)
		api.POST("/location-shares/:id/stop", a.stopShare)
		api.DELETE("/location-shares/:id/grants/:friend_id", a.revokeGrant)
		api.POST("/location-shares/:id/locations", a.shareLocations)

		api.GET("/posts", a.listPosts)
		api.POST("/posts", a.createPost)
		api.GET("/posts/:id", a.getPost)
		api.POST("/posts/:id/like", a.likePost)
		api.GET("/posts/:id/comments", a.listComments)
		api.POST("/posts/:id/comments", a.addComment)
		api.GET("/media/*path", a.media)
	}

	r.GET("/ws/rides/:id", a.wsRide)
	r.GET("/ws/location-shares", a.wsShares)
}

func (a *API) register(c *gin.Context) {
	var in struct {
		Email       string `json:"email" binding:"required"`
		Username    string `json:"username" binding:"required"`
		Password    string `json:"password" binding:"required"`
		DisplayName string `json:"display_name" binding:"required"`
	}
	if !httpx.Bind(c, &in) {
		return
	}
	out, err := a.Svc.Register(c, in.Email, in.Username, in.Password, in.DisplayName)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, out)
}

func (a *API) login(c *gin.Context) {
	var body struct {
		Email    string `json:"email" binding:"required"`
		Password string `json:"password" binding:"required"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	out, err := a.Svc.Login(c, body.Email, body.Password)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, out)
}

func (a *API) refresh(c *gin.Context) {
	var body struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	out, err := a.Svc.Refresh(c, body.RefreshToken)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, out)
}

func (a *API) logout(c *gin.Context) {
	var body struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	_ = a.Svc.Logout(c, body.RefreshToken)
	c.Status(http.StatusNoContent)
}

func (a *API) me(c *gin.Context) {
	u, err := a.Svc.Me(c, middleware.UserID(c))
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, u)
}

func (a *API) patchMe(c *gin.Context) {
	var body struct {
		DisplayName *string `json:"display_name"`
		Bio         *string `json:"bio"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	u, err := a.Svc.UpdateMe(c, middleware.UserID(c), body.DisplayName, body.Bio)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, u)
}

func (a *API) friends(c *gin.Context) {
	out, err := a.Svc.ListFriends(c, middleware.UserID(c))
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, gin.H{"friends": out})
}

func (a *API) friendRequests(c *gin.Context) {
	out, err := a.Svc.ListFriendRequests(c, middleware.UserID(c))
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, out)
}

func (a *API) requestFriend(c *gin.Context) {
	var body struct {
		Username string `json:"username" binding:"required"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	out, err := a.Svc.RequestFriend(c, middleware.UserID(c), body.Username)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, out)
}

func (a *API) acceptFriend(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	if err := a.Svc.AcceptFriend(c, middleware.UserID(c), id); err != nil {
		httpx.Fail(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (a *API) declineFriend(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	if err := a.Svc.DeclineFriend(c, middleware.UserID(c), id); err != nil {
		httpx.Fail(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (a *API) unfriend(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("user_id"))
	_ = a.Svc.Unfriend(c, middleware.UserID(c), id)
	c.Status(http.StatusNoContent)
}

func (a *API) listRides(c *gin.Context) {
	var nearLon, nearLat *float64
	if parts := strings.Split(c.Query("near"), ","); len(parts) == 2 {
		if lon, err1 := strconv.ParseFloat(parts[0], 64); err1 == nil {
			if lat, err2 := strconv.ParseFloat(parts[1], 64); err2 == nil {
				nearLon, nearLat = &lon, &lat
			}
		}
	}
	radius, _ := strconv.ParseFloat(c.DefaultQuery("radius_m", "50000"), 64)
	rides, err := a.Svc.ListRides(c, c.Query("status"), nearLon, nearLat, radius)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, gin.H{"rides": rides})
}

func (a *API) createRide(c *gin.Context) {
	var body struct {
		Title       string            `json:"title" binding:"required"`
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
	ride, err := a.Svc.CreateRide(c, middleware.UserID(c), body.Title, body.Description, body.Visibility, body.ScheduledAt, body.Start, body.Destination, body.Waypoints)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, ride)
}

func (a *API) joinRide(c *gin.Context) {
	var body struct {
		JoinCode    *string    `json:"join_code"`
		InviteToken *uuid.UUID `json:"invite_token"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	code := ""
	if body.JoinCode != nil {
		code = *body.JoinCode
	}
	ride, err := a.Svc.JoinRide(c, middleware.UserID(c), code, body.InviteToken)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, ride)
}

func (a *API) getRide(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	ride, err := a.Svc.GetRide(c, middleware.UserID(c), id)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, ride)
}

func (a *API) patchRide(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	var p struct {
		Title       *string `json:"title"`
		Description *string `json:"description"`
		Visibility  *string `json:"visibility"`
		Status      *string `json:"status"`
	}
	if !httpx.Bind(c, &p) {
		return
	}
	ride, err := a.Svc.PatchRide(c, middleware.UserID(c), id, p.Title, p.Description, p.Visibility, p.Status)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, ride)
}

func (a *API) startRide(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	ride, err := a.Svc.StartRide(c, middleware.UserID(c), id)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, ride)
}

func (a *API) endRide(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	ride, err := a.Svc.EndRide(c, middleware.UserID(c), id)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, ride)
}

func (a *API) removeParticipant(c *gin.Context) {
	rid, _ := uuid.Parse(c.Param("id"))
	uid, _ := uuid.Parse(c.Param("user_id"))
	if err := a.Svc.RemoveParticipant(c, middleware.UserID(c), rid, uid); err != nil {
		httpx.Fail(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (a *API) myStatus(c *gin.Context) {
	rid, _ := uuid.Parse(c.Param("id"))
	var body struct {
		Status string `json:"status" binding:"required"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	if err := a.Svc.SetMyStatus(c, middleware.UserID(c), rid, body.Status); err != nil {
		httpx.Fail(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (a *API) rideLocations(c *gin.Context) {
	rid, _ := uuid.Parse(c.Param("id"))
	var body struct {
		Points []service.LocationPoint `json:"points"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	if err := a.Svc.IngestRideLocations(c, middleware.UserID(c), rid, body.Points); err != nil {
		httpx.Fail(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (a *API) createShare(c *gin.Context) {
	var body struct {
		Duration  string      `json:"duration" binding:"required"`
		FriendIDs []uuid.UUID `json:"friend_ids"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	out, err := a.Svc.CreateShare(c, middleware.UserID(c), body.Duration, body.FriendIDs)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, out)
}

func (a *API) listShares(c *gin.Context) {
	out, err := a.Svc.ListShares(c, middleware.UserID(c))
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, out)
}

func (a *API) stopShare(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	if err := a.Svc.StopShare(c, middleware.UserID(c), id); err != nil {
		httpx.Fail(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (a *API) revokeGrant(c *gin.Context) {
	sid, _ := uuid.Parse(c.Param("id"))
	fid, _ := uuid.Parse(c.Param("friend_id"))
	if err := a.Svc.RevokeShareGrant(c, middleware.UserID(c), sid, fid); err != nil {
		httpx.Fail(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (a *API) shareLocations(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	var body struct {
		Points []service.LocationPoint `json:"points"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	if err := a.Svc.IngestShareLocations(c, middleware.UserID(c), id, body.Points); err != nil {
		httpx.Fail(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (a *API) listPosts(c *gin.Context) {
	var cursor *time.Time
	if v := c.Query("cursor"); v != "" {
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			cursor = &t
		}
	}
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	out, err := a.Svc.ListPosts(c, middleware.UserID(c), cursor, limit)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, gin.H{"posts": out})
}

func (a *API) createPost(c *gin.Context) {
	form, err := c.MultipartForm()
	if err != nil {
		httpx.Fail(c, httpx.E(400, "multipart required"))
		return
	}
	var caption *string
	if v := c.PostForm("caption"); v != "" {
		caption = &v
	}
	var rideID *uuid.UUID
	if v := c.PostForm("ride_id"); v != "" {
		if id, err := uuid.Parse(v); err == nil {
			rideID = &id
		}
	}
	out, err := a.Svc.CreatePost(c, middleware.UserID(c), caption, rideID, nil, nil, form.File["images"])
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, out)
}

func (a *API) getPost(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	out, err := a.Svc.GetPost(c, middleware.UserID(c), id)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, out)
}

func (a *API) likePost(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	out, err := a.Svc.ToggleLike(c, middleware.UserID(c), id)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, out)
}

func (a *API) listComments(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	out, err := a.Svc.ListComments(c, id)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, gin.H{"comments": out})
}

func (a *API) addComment(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	var body struct {
		Body string `json:"body" binding:"required"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	out, err := a.Svc.AddComment(c, middleware.UserID(c), id, body.Body)
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, out)
}

func (a *API) media(c *gin.Context) {
	rel := strings.TrimPrefix(c.Param("path"), "/")
	c.File(filepath.Join(a.Svc.Cfg.StorageRoot, filepath.FromSlash(rel)))
}

func (a *API) wsRide(c *gin.Context) {
	uid, err := a.Svc.ParseAccess(c.Query("token"))
	if err != nil {
		c.JSON(401, gin.H{"detail": "unauthorized"})
		return
	}
	rideID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(400, gin.H{"detail": "bad ride id"})
		return
	}
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	room := rideID.String()
	a.Svc.Hub.Join(room, conn)
	defer func() { a.Svc.Hub.Leave(room, conn); _ = conn.Close() }()

	for {
		var msg map[string]any
		if err := conn.ReadJSON(&msg); err != nil {
			return
		}
		switch msg["type"] {
		case "ping":
			_ = conn.WriteJSON(map[string]string{"type": "pong"})
		case "status":
			if st, _ := msg["status"].(string); st != "" {
				_ = a.Svc.SetMyStatus(c.Request.Context(), uid, rideID, st)
			}
		case "location":
			_ = a.Svc.IngestRideLocations(c.Request.Context(), uid, rideID, []service.LocationPoint{pointFromWS(msg)})
		}
	}
}

func (a *API) wsShares(c *gin.Context) {
	uid, err := a.Svc.ParseAccess(c.Query("token"))
	if err != nil {
		c.JSON(401, gin.H{"detail": "unauthorized"})
		return
	}
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	room := "shares:" + uid.String()
	a.Svc.Hub.Join(room, conn)
	defer func() { a.Svc.Hub.Leave(room, conn); _ = conn.Close() }()

	for {
		var msg map[string]any
		if err := conn.ReadJSON(&msg); err != nil {
			return
		}
		if msg["type"] == "location" {
			sid, _ := uuid.Parse(asString(msg["share_id"]))
			_ = a.Svc.IngestShareLocations(c.Request.Context(), uid, sid, []service.LocationPoint{pointFromWS(msg)})
		}
	}
}

func pointFromWS(msg map[string]any) service.LocationPoint {
	pt := service.LocationPoint{RecordedAt: time.Now().UTC()}
	pt.Lat, _ = msg["lat"].(float64)
	pt.Lon, _ = msg["lon"].(float64)
	if v, ok := msg["speed"].(float64); ok {
		pt.SpeedMps = &v
	}
	if v, ok := msg["heading"].(float64); ok {
		pt.Heading = &v
	}
	if v, ok := msg["accuracy"].(float64); ok {
		pt.AccuracyM = &v
	}
	if v, ok := msg["status"].(string); ok {
		pt.Status = &v
	}
	if v, ok := msg["recorded_at"].(string); ok {
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			pt.RecordedAt = t
		}
	}
	return pt
}

func asString(v any) string {
	s, _ := v.(string)
	return s
}
