package service

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"math"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestNormalizeEmail(t *testing.T) {
	good := map[string]string{
		" Alex@RideX.app ":     "alex@ridex.app",
		"a.b+c@sub.example.co": "a.b+c@sub.example.co",
	}
	for in, want := range good {
		got, err := NormalizeEmail(in)
		if err != nil || got != want {
			t.Errorf("NormalizeEmail(%q) = %q, %v", in, got, err)
		}
	}
	for _, bad := range []string{"", "alex", "alex@", "@ridex.app", "alex@ridex", "alex@ridex.", "a b@x.io", strings.Repeat("a", 320) + "@x.io"} {
		if _, err := NormalizeEmail(bad); err == nil {
			t.Errorf("NormalizeEmail(%q) accepted", bad)
		}
	}
}

func TestNormalizeUsername(t *testing.T) {
	if got, err := NormalizeUsername("  Alex_Driver.1 "); err != nil || got != "alex_driver.1" {
		t.Fatalf("got %q %v", got, err)
	}
	for _, bad := range []string{"ab", "has space", "émile", "dash-name", strings.Repeat("a", 33)} {
		if _, err := NormalizeUsername(bad); err == nil {
			t.Errorf("NormalizeUsername(%q) accepted", bad)
		}
	}
}

func TestValidatePassword(t *testing.T) {
	if ValidatePassword("1234567") == nil {
		t.Fatal("7 chars accepted")
	}
	if ValidatePassword("12345678") != nil {
		t.Fatal("8 chars rejected")
	}
	if ValidatePassword(strings.Repeat("x", 129)) == nil {
		t.Fatal("129 chars accepted")
	}
}

func TestTrimmedText(t *testing.T) {
	if v, err := TrimmedText("title", "  Sunday run  ", 1, 100); err != nil || v != "Sunday run" {
		t.Fatalf("got %q %v", v, err)
	}
	if _, err := TrimmedText("title", "   ", 1, 100); err == nil {
		t.Fatal("blank accepted")
	}
	if _, err := TrimmedText("bio", strings.Repeat("é", 281), 0, 280); err == nil {
		t.Fatal("too long accepted")
	}
}

func TestValidCoord(t *testing.T) {
	if !ValidCoord(28.6, 77.2) || !ValidCoord(-90, 180) {
		t.Fatal("valid coord rejected")
	}
	for _, c := range [][2]float64{{91, 0}, {0, -181}, {math.NaN(), 0}, {0, math.Inf(1)}} {
		if ValidCoord(c[0], c[1]) {
			t.Fatalf("invalid coord %v accepted", c)
		}
	}
}

func TestValidParticipantStatus(t *testing.T) {
	for _, s := range []string{"joined", "on_the_way", "riding", "paused", "reached"} {
		if !ValidParticipantStatus(s) {
			t.Fatalf("%s rejected", s)
		}
	}
	for _, s := range []string{"", "removed", "left", "host", "RIDING"} {
		if ValidParticipantStatus(s) {
			t.Fatalf("%q accepted", s)
		}
	}
}

func TestSafeMediaPath(t *testing.T) {
	root := t.TempDir()
	ok := []string{"posts/a.jpg", "/posts/a.jpg", "thumbnails/x_thumb.jpg", "avatars/./b.png"}
	for _, p := range ok {
		full, good := SafeMediaPath(root, p)
		if !good {
			t.Errorf("%q rejected", p)
			continue
		}
		if !strings.HasPrefix(full, root) {
			t.Errorf("%q escaped root: %s", p, full)
		}
	}
	bad := []string{"", "/", "..", "../etc/passwd", "posts/../../etc/passwd", "posts/..\\..\\x", "..\\windows", "posts/\x00.jpg"}
	for _, p := range bad {
		if full, good := SafeMediaPath(root, p); good {
			t.Errorf("%q accepted -> %s", p, full)
		}
	}
	if full, good := SafeMediaPath(root, "posts/a.jpg"); !good || full != filepath.Join(root, "posts", "a.jpg") {
		t.Fatalf("unexpected path %s", full)
	}
}

func TestNormalizePoints(t *testing.T) {
	now := time.Now().UTC()
	pts, err := normalizePoints([]LocationPoint{
		{Lat: 1, Lon: 1, RecordedAt: now.Add(-time.Second)},
		{Lat: 1, Lon: 1, RecordedAt: now.Add(-time.Minute)},
		{Lat: 1, Lon: 1, RecordedAt: now.Add(time.Hour)}, // future -> clamped to now
		{Lat: 1, Lon: 1}, // zero -> now
	})
	if err != nil {
		t.Fatal(err)
	}
	for i := 1; i < len(pts); i++ {
		if pts[i].RecordedAt.Before(pts[i-1].RecordedAt) {
			t.Fatal("points not sorted")
		}
	}
	if pts[len(pts)-1].RecordedAt.After(time.Now().Add(time.Second)) {
		t.Fatal("future timestamp not clamped")
	}
	if _, err := normalizePoints([]LocationPoint{{Lat: 100, Lon: 0}}); err == nil {
		t.Fatal("invalid coordinate accepted")
	}
	if _, err := normalizePoints(make([]LocationPoint, MaxBatchPoints+1)); err == nil {
		t.Fatal("oversized batch accepted")
	}
}

func TestLimiter(t *testing.T) {
	l := NewLimiter(2, time.Minute)
	now := time.Now()
	l.now = func() time.Time { return now }
	if !l.Allow("k") || !l.Allow("k") || l.Allow("k") {
		t.Fatal("limit not enforced")
	}
	if !l.Exceeded("k") {
		t.Fatal("Exceeded should be true")
	}
	if !l.Allow("other") {
		t.Fatal("keys must be independent")
	}
	now = now.Add(2 * time.Minute)
	if !l.Allow("k") {
		t.Fatal("window did not reset")
	}
	now = now.Add(2 * time.Minute)
	l.Prune()
	if l.Len() != 0 {
		t.Fatalf("prune left %d keys", l.Len())
	}
}

func TestMakeThumbnail(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 1600, 900))
	for y := 0; y < 900; y++ {
		for x := 0; x < 1600; x++ {
			img.Set(x, y, color.RGBA{R: uint8(x), G: uint8(y), B: 128, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, nil); err != nil {
		t.Fatal(err)
	}
	thumb, ext := makeThumbnail(buf.Bytes(), "image/jpeg")
	if thumb == nil || ext != ".jpg" {
		t.Fatal("no thumbnail")
	}
	out, err := jpeg.Decode(bytes.NewReader(thumb))
	if err != nil {
		t.Fatal(err)
	}
	if b := out.Bounds(); b.Dx() != thumbMaxSide || b.Dy() != 900*thumbMaxSide/1600 {
		t.Fatalf("thumbnail size %v", b)
	}
	if t2, _ := makeThumbnail([]byte("not an image"), "image/jpeg"); t2 != nil {
		t.Fatal("garbage decoded")
	}
}
