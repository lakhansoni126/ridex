// Package ws fans JSON messages out to rooms of websocket clients.
//
// gorilla/websocket allows one concurrent writer per connection, so every
// connection gets a Client with a buffered send queue drained by a single
// writePump goroutine. Broadcast never blocks: a client whose queue is full
// is considered too slow and is disconnected.
package ws

import (
	"encoding/json"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = 25 * time.Second
	maxMessageSize = 64 * 1024
	sendBuffer     = 64
)

// Conn is the subset of *websocket.Conn the hub needs (lets tests fake it).
type Conn interface {
	SetReadLimit(int64)
	SetReadDeadline(time.Time) error
	SetWriteDeadline(time.Time) error
	SetPongHandler(func(string) error)
	ReadMessage() (int, []byte, error)
	WriteMessage(int, []byte) error
	Close() error
}

// Client is one websocket connection with a single-writer send queue.
type Client struct {
	conn      Conn
	send      chan []byte
	closeOnce sync.Once
	done      chan struct{}
}

// NewClient wraps conn and starts its write pump.
func NewClient(conn Conn) *Client {
	c := &Client{conn: conn, send: make(chan []byte, sendBuffer), done: make(chan struct{})}
	conn.SetReadLimit(maxMessageSize)
	_ = conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(pongWait))
	})
	go c.writePump()
	return c
}

// Send queues a JSON-encoded message. It never blocks; slow clients are closed.
func (c *Client) Send(v any) bool {
	b, err := json.Marshal(v)
	if err != nil {
		return false
	}
	return c.sendRaw(b)
}

func (c *Client) sendRaw(b []byte) bool {
	select {
	case <-c.done:
		return false
	default:
	}
	select {
	case c.send <- b:
		return true
	default:
		c.Close()
		return false
	}
}

// Read returns the next frame payload (refreshing the read deadline). Any
// error means the connection is finished.
func (c *Client) Read() ([]byte, error) {
	_, b, err := c.conn.ReadMessage()
	if err != nil {
		return nil, err
	}
	_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
	return b, nil
}

// Close stops the write pump and closes the underlying connection.
func (c *Client) Close() {
	c.closeOnce.Do(func() {
		close(c.done)
		_ = c.conn.Close()
	})
}

// Done is closed once the client is closed.
func (c *Client) Done() <-chan struct{} { return c.done }

func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.Close()
	}()
	for {
		select {
		case <-c.done:
			return
		case msg := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// Hub fans out JSON messages to rooms (ride IDs or "shares:"+userID).
type Hub struct {
	mu    sync.RWMutex
	rooms map[string]map[*Client]struct{}
}

func NewHub() *Hub { return &Hub{rooms: map[string]map[*Client]struct{}{}} }

func (h *Hub) Join(room string, c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.rooms[room] == nil {
		h.rooms[room] = map[*Client]struct{}{}
	}
	h.rooms[room][c] = struct{}{}
}

func (h *Hub) Leave(room string, c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if m := h.rooms[room]; m != nil {
		delete(m, c)
		if len(m) == 0 {
			delete(h.rooms, room)
		}
	}
}

// RoomSize returns the number of clients in room.
func (h *Hub) RoomSize(room string) int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.rooms[room])
}

// Broadcast queues v for every client in room. Safe for nil hubs (tests).
func (h *Hub) Broadcast(room string, v any) {
	if h == nil {
		return
	}
	b, err := json.Marshal(v)
	if err != nil {
		return
	}
	h.mu.RLock()
	clients := make([]*Client, 0, len(h.rooms[room]))
	for c := range h.rooms[room] {
		clients = append(clients, c)
	}
	h.mu.RUnlock()
	for _, c := range clients {
		c.sendRaw(b)
	}
}
