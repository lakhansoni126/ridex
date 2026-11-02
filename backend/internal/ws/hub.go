package ws

import (
	"encoding/json"
	"sync"

	"github.com/gorilla/websocket"
)

// Hub fans out JSON messages to rooms (ride IDs or "shares:"+userID).
type Hub struct {
	mu    sync.RWMutex
	rooms map[string]map[*websocket.Conn]struct{}
}

func NewHub() *Hub { return &Hub{rooms: map[string]map[*websocket.Conn]struct{}{}} }

func (h *Hub) Join(room string, c *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.rooms[room] == nil {
		h.rooms[room] = map[*websocket.Conn]struct{}{}
	}
	h.rooms[room][c] = struct{}{}
}

func (h *Hub) Leave(room string, c *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if m := h.rooms[room]; m != nil {
		delete(m, c)
		if len(m) == 0 {
			delete(h.rooms, room)
		}
	}
}

func (h *Hub) Broadcast(room string, v any) {
	b, err := json.Marshal(v)
	if err != nil {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.rooms[room] {
		_ = c.WriteMessage(websocket.TextMessage, b)
	}
}
