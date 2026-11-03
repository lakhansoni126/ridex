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

func (a *API) listPosts(c *gin.Context) {
	var cursor *time.Time
	if v := c.Query("cursor"); v != "" {
		t, err := time.Parse(time.RFC3339Nano, v)
		if err != nil {
			httpx.Fail(c, httpx.BadRequest("invalid cursor"))
			return
		}
		cursor = &t
	}
	var author *uuid.UUID
	if v := c.Query("author_id"); v != "" {
		id, err := uuid.Parse(v)
		if err != nil {
			httpx.Fail(c, httpx.BadRequest("invalid author_id"))
			return
		}
		author = &id
	}
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	out, err := a.Svc.ListPosts(c.Request.Context(), middleware.UserID(c), cursor, limit, author)
	respond(c, out, err)
}

func (a *API) createPost(c *gin.Context) {
	form, err := c.MultipartForm()
	if err != nil {
		httpx.Fail(c, multipartErr(err, "multipart form with images is required"))
		return
	}
	in := service.CreatePostInput{Files: form.File["images"]}
	if v, ok := c.GetPostForm("caption"); ok {
		in.Caption = &v
	}
	if in.RideID, err = formUUID(c, "ride_id"); err != nil {
		httpx.Fail(c, err)
		return
	}
	if v := strings.TrimSpace(c.PostForm("distance_km")); v != "" {
		f, err := strconv.ParseFloat(v, 64)
		if err != nil {
			httpx.Fail(c, httpx.BadRequest("invalid distance_km"))
			return
		}
		in.DistanceKm = &f
	}
	if v := strings.TrimSpace(c.PostForm("duration_s")); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil {
			httpx.Fail(c, httpx.BadRequest("invalid duration_s"))
			return
		}
		in.DurationS = &n
	}
	out, err := a.Svc.CreatePost(c.Request.Context(), middleware.UserID(c), in)
	respond(c, out, err)
}

func (a *API) getPost(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	out, err := a.Svc.GetPost(c.Request.Context(), middleware.UserID(c), id)
	respond(c, out, err)
}

func (a *API) deletePost(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	respondNoContent(c, a.Svc.DeletePost(c.Request.Context(), middleware.UserID(c), id))
}

func (a *API) likePost(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	out, err := a.Svc.ToggleLike(c.Request.Context(), middleware.UserID(c), id)
	respond(c, out, err)
}

func (a *API) listComments(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	out, err := a.Svc.ListComments(c.Request.Context(), id)
	respond(c, gin.H{"comments": out}, err)
}

func (a *API) addComment(c *gin.Context) {
	id, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	var body struct {
		Body string `json:"body"`
	}
	if !httpx.Bind(c, &body) {
		return
	}
	out, err := a.Svc.AddComment(c.Request.Context(), middleware.UserID(c), id, body.Body)
	respond(c, out, err)
}

func (a *API) deleteComment(c *gin.Context) {
	pid, ok := httpx.ParamUUID(c, "id")
	if !ok {
		return
	}
	cid, ok := httpx.ParamUUID(c, "comment_id")
	if !ok {
		return
	}
	respondNoContent(c, a.Svc.DeleteComment(c.Request.Context(), middleware.UserID(c), pid, cid))
}
