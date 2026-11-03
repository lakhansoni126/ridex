package main

import (
	"context"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/lakhansoni126/ridex/backend/internal/config"
	"github.com/lakhansoni126/ridex/backend/internal/db"
	"github.com/lakhansoni126/ridex/backend/internal/service"
	"github.com/lakhansoni126/ridex/backend/internal/ws"
)

func main() {
	cfg := config.Load()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()
	if err := db.Migrate(ctx, pool); err != nil {
		log.Fatal(err)
	}

	svc := service.New(pool, cfg, ws.NewHub())
	demos := []struct{ email, user, name, pass string }{
		{"alex@ridex.local", "alex", "Alex Driver", "password123"},
		{"sam@ridex.local", "sam", "Sam Cruiser", "password123"},
		{"jordan@ridex.local", "jordan", "Jordan Roadster", "password123"},
	}
	var ids []uuid.UUID
	for _, d := range demos {
		// Empty IP skips the per-IP abuse limits for the seeder.
		tok, err := svc.Register(ctx, "", d.email, d.user, d.pass, d.name)
		if err != nil {
			u, e2 := svc.Login(ctx, "", d.email, d.pass)
			if e2 != nil {
				log.Println("skip", d.user, err)
				continue
			}
			ids = append(ids, u.User.ID)
			log.Println("exists:", d.user)
			continue
		}
		ids = append(ids, tok.User.ID)
		log.Println("created:", d.user, "/", d.pass)
	}
	if len(ids) >= 2 {
		if _, err := svc.RequestFriend(ctx, ids[0], "sam"); err == nil {
			reqs, _ := svc.ListFriendRequests(ctx, ids[1])
			for _, r := range reqs["incoming"] {
				_, _ = svc.AcceptFriend(ctx, ids[1], r.ID)
			}
		}
	}
}
