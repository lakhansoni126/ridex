package ws

import (
	"errors"
	"sync"
	"testing"
	"time"
)

// fakeConn records writes and flags concurrent WriteMessage calls.
type fakeConn struct {
	mu       sync.Mutex
	writing  bool
	overlap  bool
	messages [][]byte
	closed   chan struct{}
	once     sync.Once
}

func newFakeConn() *fakeConn { return &fakeConn{closed: make(chan struct{})} }

func (f *fakeConn) SetReadLimit(int64)                {}
func (f *fakeConn) SetReadDeadline(time.Time) error   { return nil }
func (f *fakeConn) SetWriteDeadline(time.Time) error  { return nil }
func (f *fakeConn) SetPongHandler(func(string) error) {}
func (f *fakeConn) ReadMessage() (int, []byte, error) {
	<-f.closed
	return 0, nil, errors.New("closed")
}
func (f *fakeConn) WriteMessage(_ int, b []byte) error {
	f.mu.Lock()
	if f.writing {
		f.overlap = true
	}
	f.writing = true
	f.mu.Unlock()
	time.Sleep(50 * time.Microsecond)
	f.mu.Lock()
	f.writing = false
	if b != nil {
		f.messages = append(f.messages, b)
	}
	f.mu.Unlock()
	return nil
}
func (f *fakeConn) Close() error { f.once.Do(func() { close(f.closed) }); return nil }

func (f *fakeConn) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.messages)
}

func TestBroadcastReachesAllClientsWithoutConcurrentWrites(t *testing.T) {
	h := NewHub()
	conns := []*fakeConn{newFakeConn(), newFakeConn(), newFakeConn()}
	var clients []*Client
	for _, fc := range conns {
		c := NewClient(fc)
		clients = append(clients, c)
		h.Join("room", c)
	}
	if h.RoomSize("room") != 3 {
		t.Fatalf("room size = %d", h.RoomSize("room"))
	}

	var wg sync.WaitGroup
	for g := 0; g < 4; g++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < 10; i++ {
				h.Broadcast("room", map[string]int{"i": i})
			}
		}()
	}
	wg.Wait()

	deadline := time.Now().Add(3 * time.Second)
	for _, fc := range conns {
		for fc.count() < 40 && time.Now().Before(deadline) {
			time.Sleep(5 * time.Millisecond)
		}
		if fc.count() != 40 {
			t.Fatalf("client got %d messages, want 40", fc.count())
		}
		if fc.overlap {
			t.Fatal("concurrent writes detected on a single connection")
		}
	}
	for _, c := range clients {
		h.Leave("room", c)
		c.Close()
	}
	if h.RoomSize("room") != 0 {
		t.Fatal("room not cleaned up")
	}
}

func TestSlowClientIsDropped(t *testing.T) {
	fc := newFakeConn()
	c := &Client{conn: fc, send: make(chan []byte, 1), done: make(chan struct{})}
	// No write pump: the queue fills immediately.
	if !c.sendRaw([]byte("a")) {
		t.Fatal("first send should queue")
	}
	if c.sendRaw([]byte("b")) {
		t.Fatal("second send should fail and close the slow client")
	}
	select {
	case <-c.Done():
	default:
		t.Fatal("slow client not closed")
	}
}
