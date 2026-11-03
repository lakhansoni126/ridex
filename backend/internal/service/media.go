package service

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

const thumbMaxSide = 640

var allowedImageTypes = map[string]string{
	"image/jpeg": ".jpg",
	"image/png":  ".png",
	"image/webp": ".webp",
}

func (s *Svc) EnsureStorageDirs() error {
	for _, sub := range []string{"posts", "avatars", "thumbnails"} {
		if err := os.MkdirAll(filepath.Join(s.Cfg.StorageRoot, sub), 0o755); err != nil {
			return err
		}
	}
	return nil
}

// SafeMediaPath maps a client-supplied relative path to a file under root.
// It rejects absolute paths, traversal and anything escaping root.
func SafeMediaPath(root, rel string) (string, bool) {
	rel = strings.ReplaceAll(rel, "\\", "/")
	rel = strings.TrimPrefix(rel, "/")
	if rel == "" || strings.Contains(rel, "\x00") {
		return "", false
	}
	for _, seg := range strings.Split(rel, "/") {
		if seg == ".." {
			return "", false
		}
	}
	clean := path.Clean(rel)
	if clean == "." || strings.HasPrefix(clean, "../") || path.IsAbs(clean) || filepath.IsAbs(filepath.FromSlash(clean)) || filepath.VolumeName(filepath.FromSlash(clean)) != "" {
		return "", false
	}
	absRoot, err := filepath.Abs(root)
	if err != nil {
		return "", false
	}
	full := filepath.Join(absRoot, filepath.FromSlash(clean))
	r, err := filepath.Rel(absRoot, full)
	if err != nil || r == ".." || strings.HasPrefix(r, ".."+string(filepath.Separator)) {
		return "", false
	}
	return full, true
}

// MediaFile resolves a media path for serving; 404 when invalid or missing.
func (s *Svc) MediaFile(rel string) (string, error) {
	full, ok := SafeMediaPath(s.Cfg.StorageRoot, rel)
	if !ok {
		return "", httpx.NotFound("not found")
	}
	st, err := os.Stat(full)
	if err != nil || st.IsDir() {
		return "", httpx.NotFound("not found")
	}
	return full, nil
}

type storedImage struct {
	Rel   string
	Thumb string
}

// saveImage stores an uploaded image under kind/ and a JPEG thumbnail under
// thumbnails/. The type comes from content sniffing, never the client.
func (s *Svc) saveImage(fh *multipart.FileHeader, kind string) (storedImage, error) {
	if fh.Size > s.Cfg.MediaMaxBytes {
		return storedImage{}, httpx.E(http.StatusRequestEntityTooLarge, "image is too large")
	}
	if err := s.EnsureStorageDirs(); err != nil {
		return storedImage{}, err
	}
	f, err := fh.Open()
	if err != nil {
		return storedImage{}, httpx.BadRequest("could not read upload")
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, s.Cfg.MediaMaxBytes+1))
	if err != nil {
		return storedImage{}, httpx.BadRequest("could not read upload")
	}
	if int64(len(data)) > s.Cfg.MediaMaxBytes {
		return storedImage{}, httpx.E(http.StatusRequestEntityTooLarge, "image is too large")
	}
	ct := http.DetectContentType(data)
	ext, ok := allowedImageTypes[ct]
	if !ok {
		return storedImage{}, httpx.E(http.StatusUnsupportedMediaType, "only JPEG, PNG or WebP images are allowed")
	}

	id := uuid.NewString()
	out := storedImage{Rel: kind + "/" + id + ext}
	if err := os.WriteFile(filepath.Join(s.Cfg.StorageRoot, filepath.FromSlash(out.Rel)), data, 0o644); err != nil {
		return storedImage{}, err
	}

	thumb, thumbExt := makeThumbnail(data, ct)
	if thumb == nil {
		thumb, thumbExt = data, ext // e.g. WebP (no stdlib decoder): reuse original
	}
	out.Thumb = "thumbnails/" + id + "_thumb" + thumbExt
	if err := os.WriteFile(filepath.Join(s.Cfg.StorageRoot, filepath.FromSlash(out.Thumb)), thumb, 0o644); err != nil {
		s.removeFiles(out.Rel)
		return storedImage{}, err
	}
	return out, nil
}

// removeFiles deletes stored media best-effort.
func (s *Svc) removeFiles(rels ...string) {
	for _, r := range rels {
		if r == "" {
			continue
		}
		if full, ok := SafeMediaPath(s.Cfg.StorageRoot, r); ok {
			_ = os.Remove(full)
		}
	}
}

// makeThumbnail decodes JPEG/PNG and returns a JPEG no larger than
// thumbMaxSide on its longest side. Returns nil when it can't decode.
func makeThumbnail(data []byte, ct string) ([]byte, string) {
	var src image.Image
	var err error
	switch ct {
	case "image/jpeg":
		src, err = jpeg.Decode(bytes.NewReader(data))
	case "image/png":
		src, err = png.Decode(bytes.NewReader(data))
	default:
		return nil, ""
	}
	if err != nil {
		return nil, ""
	}
	dst := resizeBox(src, thumbMaxSide)
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, dst, &jpeg.Options{Quality: 80}); err != nil {
		return nil, ""
	}
	return buf.Bytes(), ".jpg"
}

// resizeBox downsamples with box filtering (averaging) so the longest side is
// at most maxSide. Transparent pixels are composited onto white.
func resizeBox(src image.Image, maxSide int) image.Image {
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	if w <= 0 || h <= 0 {
		return src
	}
	nw, nh := w, h
	if w > maxSide || h > maxSide {
		if w >= h {
			nw, nh = maxSide, max(1, h*maxSide/w)
		} else {
			nw, nh = max(1, w*maxSide/h), maxSide
		}
	}
	dst := image.NewRGBA(image.Rect(0, 0, nw, nh))
	for y := 0; y < nh; y++ {
		y0 := b.Min.Y + y*h/nh
		y1 := max(y0+1, b.Min.Y+(y+1)*h/nh)
		for x := 0; x < nw; x++ {
			x0 := b.Min.X + x*w/nw
			x1 := max(x0+1, b.Min.X+(x+1)*w/nw)
			var r, g, bl, n uint64
			for yy := y0; yy < y1; yy++ {
				for xx := x0; xx < x1; xx++ {
					cr, cg, cb, ca := src.At(xx, yy).RGBA()
					// composite onto white
					white := uint64(0xffff - ca)
					r += uint64(cr) + white
					g += uint64(cg) + white
					bl += uint64(cb) + white
					n++
				}
			}
			dst.SetRGBA(x, y, color.RGBA{
				R: uint8((r / n) >> 8), G: uint8((g / n) >> 8), B: uint8((bl / n) >> 8), A: 0xff,
			})
		}
	}
	return dst
}
