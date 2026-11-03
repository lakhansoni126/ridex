package service

import (
	"sync"
	"time"
)

// Limiter is a fixed-window counter: at most Max events per key per Window.
type Limiter struct {
	Max    int
	Window time.Duration

	mu      sync.Mutex
	buckets map[string]*bucket
	now     func() time.Time
}

type bucket struct {
	start time.Time
	count int
}

func NewLimiter(max int, window time.Duration) *Limiter {
	return &Limiter{Max: max, Window: window, buckets: map[string]*bucket{}, now: time.Now}
}

// Allow records an event for key and reports whether it is within the limit.
func (l *Limiter) Allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	b := l.buckets[key]
	if b == nil || now.Sub(b.start) >= l.Window {
		l.buckets[key] = &bucket{start: now, count: 1}
		return true
	}
	if b.count >= l.Max {
		return false
	}
	b.count++
	return true
}

// Exceeded reports whether key is currently over the limit without recording.
func (l *Limiter) Exceeded(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	b := l.buckets[key]
	return b != nil && l.now().Sub(b.start) < l.Window && b.count >= l.Max
}

// Reset forgets key (e.g. after a successful login).
func (l *Limiter) Reset(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.buckets, key)
}

// Prune drops expired buckets so the map does not grow forever.
func (l *Limiter) Prune() {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	for k, b := range l.buckets {
		if now.Sub(b.start) >= l.Window {
			delete(l.buckets, k)
		}
	}
}

// Len returns the number of tracked keys.
func (l *Limiter) Len() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.buckets)
}
