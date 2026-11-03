// Package handler is the thin HTTP/WS adapter over service.Svc.
package handler

import (
	"context"
	"errors"
	"net/http"
	"path"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
	"github.com/lakhansoni126/ridex/backend/internal/middleware"
	"github.com/lakhansoni126/ridex/backend/internal/service"
)

type API struct{ Svc *service.Svc }

func (a *API) Mount(r *gin.Engine) {
	r.GET("/health", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "RideX"}) })
	r.GET("/ready", a.ready)

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
		api.DELETE("/users/me", a.deleteMe)
		api.POST("/users/me/avatar", a.uploadAvatar)
		api.GET("/users/me/stats", a.myStats)
		api.GET("/users/search", a.searchUsers)

		api.GET("/friends", a.friends)
		api.GET("/friends/requests", a.friendRequests)
		api.POST("/friends/requests", a.requestFriend)
		api.POST("/friends/requests/:id/accept", a.acceptFriend)
		api.POST("/friends/requests/:id/decline", a.declineFriend)
		api.DELETE("/friends/requests/:id", a.cancelFriendRequest)
		api.DELETE("/friends/:id", a.unfriend)

		api.GET("/rides", a.listRides)
		api.POST("/rides", a.createRide)
		api.POST("/rides/join", a.joinRide)
		api.GET("/rides/:id", a.getRide)
		api.PATCH("/rides/:id", a.patchRide)
		api.POST("/rides/:id/start", a.startRide)
		api.POST("/rides/:id/end", a.endRide)
		api.POST("/rides/:id/cancel", a.cancelRide)
		api.POST("/rides/:id/leave", a.leaveRide)
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
		api.DELETE("/posts/:id", a.deletePost)
		api.POST("/posts/:id/like", a.likePost)
		api.GET("/posts/:id/comments", a.listComments)
		api.POST("/posts/:id/comments", a.addComment)
		api.DELETE("/posts/:id/comments/:comment_id", a.deleteComment)
		api.GET("/media/*path", a.media)
	}

	r.GET("/ws/rides/:id", a.wsRide)
	r.GET("/ws/location-shares", a.wsShares)
}

func (a *API) ready(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
	defer cancel()
	if err := a.Svc.DB.Ping(ctx); err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"status": "unavailable", "detail": "database unreachable"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ready"})
}

// respond writes v (or err) — keeps handlers to a few lines.
func respond(c *gin.Context, v any, err error) {
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.OK(c, v)
}

func respondNoContent(c *gin.Context, err error) {
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	httpx.NoContent(c)
}

// ---- auth ----

func (a *API) register(c *gin.Context) {
	var in struct {
		Email       string `json:"email"`
		Username    string `json:"username"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
	}
	if !httpx.Bind(c, &in) {
		return
	}
	out, err := a.Svc.Register(c.Request.Context(), c.ClientIP(), in.Email, in.Username, in.Password, in.DisplayName)
	respond(c, out, err)
}

func (a *API) login(c *gin.Context) {
	var in struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if !httpx.Bind(c, &in) {
		return
	}
	if strings.TrimSpace(in.Email) == "" || in.Password == "" {
		httpx.Fail(c, httpx.BadRequest("email and password are required"))
		return
	}
	out, err := a.Svc.Login(c.Request.Context(), c.ClientIP(), in.Email, in.Password)
	respond(c, out, err)
}

func (a *API) refresh(c *gin.Context) {
	var in struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}
	if !httpx.Bind(c, &in) {
		return
	}
	out, err := a.Svc.Refresh(c.Request.Context(), in.RefreshToken)
	respond(c, out, err)
}

func (a *API) logout(c *gin.Context) {
	var in struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}
	if !httpx.Bind(c, &in) {
		return
	}
	respondNoContent(c, a.Svc.Logout(c.Request.Context(), in.RefreshToken))
}

// ---- users ----

func (a *API) me(c *gin.Context) {
	u, err := a.Svc.Me(c.Request.Context(), middleware.UserID(c))
	respond(c, u, err)
}

func (a *API) patchMe(c *gin.Context) {
	var in struct {
		DisplayName *string `json:"display_name"`
		Bio         *string `json:"bio"`
	}
	if !httpx.Bind(c, &in) {
		return
	}
	u, err := a.Svc.UpdateMe(c.Request.Context(), middleware.UserID(c), in.DisplayName, in.Bio)
	respond(c, u, err)
}

func (a *API) deleteMe(c *gin.Context) {
	respondNoContent(c, a.Svc.DeleteMe(c.Request.Context(), middleware.UserID(c)))
}

func (a *API) uploadAvatar(c *gin.Context) {
	fh, err := c.FormFile("avatar")
	if err != nil {
		httpx.Fail(c, multipartErr(err, "avatar file is required"))
		return
	}
	u, err := a.Svc.SetAvatar(c.Request.Context(), middleware.UserID(c), fh)
	respond(c, u, err)
}

func (a *API) myStats(c *gin.Context) {
	st, err := a.Svc.Stats(c.Request.Context(), middleware.UserID(c))
	respond(c, st, err)
}

func (a *API) searchUsers(c *gin.Context) {
	users, err := a.Svc.SearchUsers(c.Request.Context(), middleware.UserID(c), c.Query("q"))
	respond(c, gin.H{"users": users}, err)
}

// ---- friends ----

func (a *API) friends(c *gin.Context) {
	out, err := a.Svc.ListFriends(c.Request.Context(), middleware.UserID(c))
	respond(c, gin.H{"friends": out}, err)
}

func (a *API) friendRequests(c *gin.Context) {
	out, err := a.Svc.ListFriendRequests(c.Request.Context(), middleware.UserID(c))
	respond(c, out, err)
}

func (a *API) requestFriend(c *gin.Context) {
	var in struct {
		Username string `json:"username" binding:"required"`
	}
	if !httpx.Bind(c, &in) {
		return
	}
	out, err := a.Svc.RequestFriend(c.Request.Context(), middleware.UserID(c), in.Username)
	respond(c, out, err)
}

func (a *API) acceptFriend(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	out, err := a.Svc.AcceptFriend(c.Request.Context(), middleware.UserID(c), id)
	respond(c, out, err)
}

func (a *API) declineFriend(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	respondNoContent(c, a.Svc.DeclineFriend(c.Request.Context(), middleware.UserID(c), id))
}

func (a *API) cancelFriendRequest(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	respondNoContent(c, a.Svc.CancelFriendRequest(c.Request.Context(), middleware.UserID(c), id))
}

func (a *API) unfriend(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	respondNoContent(c, a.Svc.Unfriend(c.Request.Context(), middleware.UserID(c), id))
}

// ---- media ----

func (a *API) media(c *gin.Context) {
	full, err := a.Svc.MediaFile(path.Clean("/" + c.Param("path"))[1:])
	if err != nil {
		httpx.Fail(c, err)
		return
	}
	c.Header("Cache-Control", "private, max-age=86400")
	c.File(full)
}

// ---- helpers ----

func multipartErr(err error, missing string) error {
	var mbe *http.MaxBytesError
	if errors.As(err, &mbe) || strings.Contains(err.Error(), "too large") {
		return httpx.E(http.StatusRequestEntityTooLarge, "upload is too large")
	}
	return httpx.BadRequest(missing)
}

func queryFloat(c *gin.Context, key string) *float64 {
	if v := c.Query(key); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			return &f
		}
	}
	return nil
}

func formUUID(c *gin.Context, key string) (*uuid.UUID, error) {
	v := strings.TrimSpace(c.PostForm(key))
	if v == "" {
		return nil, nil
	}
	id, err := uuid.Parse(v)
	if err != nil {
		return nil, httpx.BadRequest("invalid " + key)
	}
	return &id, nil
}
