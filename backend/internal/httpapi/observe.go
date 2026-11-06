package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net/http"
	"time"
)

// requestInfo dibawa context dari accessLog ke capturePattern dan recoverer. withDeadline membuat salinan
// request, sehingga r.Pattern yang diisi ServeMux tidak terlihat oleh middleware luar; pointer ini berbagi
// hasilnya (ADR-0054).
type requestInfo struct {
	id      string
	pattern string
	// panicked diset recoverer saat handler panik sesudah header terkirim (ADR-0054 review akhir): header
	// yang sudah terkirim membuat WriteHeader(500) recoverer jadi no-op, jadi statusRecorder tetap merekam
	// status lama (mis. 200). accessLog memakai penanda ini untuk tetap mencatat permintaan sebagai 500 di
	// log dan metrik, karena responsnya memang gagal meski header awal sempat terkirim.
	panicked bool
}

type requestInfoKey struct{}

func requestInfoFrom(ctx context.Context) *requestInfo {
	info, _ := ctx.Value(requestInfoKey{}).(*requestInfo)
	return info
}

// RequestID mengembalikan id permintaan yang sedang dilayani, atau "" di luar permintaan.
func RequestID(ctx context.Context) string {
	if info := requestInfoFrom(ctx); info != nil {
		return info.id
	}
	return ""
}

// newRequestID: 8 byte acak. Header X-Request-ID dari klien diabaikan agar id tidak bisa dipalsukan atau
// dipakai menyuntik log.
func newRequestID() string {
	var b [8]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}

// route adalah pola ServeMux yang cocok (mis. "POST /v1/enrollments/{id}/credentials"); rute tak dikenal
// cocok dengan pola catch-all "/". Path mentah tidak pernah dipakai: bisa memuat id (aturan 6).
func (i *requestInfo) route() string {
	if i.pattern == "" {
		return "/"
	}
	return i.pattern
}

// statusRecorder mencatat status dan jumlah byte respons untuk log akses.
type statusRecorder struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (s *statusRecorder) WriteHeader(code int) {
	if s.status == 0 {
		s.status = code
	}
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusRecorder) Write(b []byte) (int, error) {
	if s.status == 0 {
		s.status = http.StatusOK
	}
	n, err := s.ResponseWriter.Write(b)
	s.bytes += n
	return n, err
}

// Unwrap membuat http.ResponseController tetap bisa menjangkau writer asli.
func (s *statusRecorder) Unwrap() http.ResponseWriter { return s.ResponseWriter }

// accessLog memberi setiap permintaan request id (juga di header X-Request-ID) dan menulis satu baris log
// sesudah handler selesai: pola rute, status, durasi, dan ukuran respons. Path mentah, query, body, header,
// dan alamat IP tidak dicatat (aturan 6, NFR-PR01).
func accessLog(logger *slog.Logger, metrics *Metrics, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		info := &requestInfo{id: newRequestID()}
		w.Header().Set("X-Request-ID", info.id)
		rec := &statusRecorder{ResponseWriter: w}
		start := time.Now()
		metrics.begin()
		aborted := true
		defer func() {
			status := rec.status
			if status == 0 && !aborted {
				status = http.StatusOK // handler tidak menulis apa pun: net/http mengirim 200
			}
			if info.panicked {
				status = http.StatusInternalServerError
			}
			elapsed := time.Since(start)
			metrics.end(info.route(), status, elapsed)
			// Context kosong: request_id ditulis eksplisit, tidak digandakan oleh WithRequestID.
			logger.LogAttrs(context.Background(), slog.LevelInfo, "http request",
				slog.String("request_id", info.id),
				slog.String("route", info.route()),
				slog.Int("status", status),
				slog.Float64("duration_ms", float64(elapsed.Microseconds())/1000),
				slog.Int("bytes", rec.bytes))
		}()
		next.ServeHTTP(rec, r.WithContext(context.WithValue(r.Context(), requestInfoKey{}, info)))
		aborted = false
	})
}

// capturePattern menyalin pola ServeMux ke requestInfo, juga saat handler panic (defer), sehingga
// recoverer dan log akses tahu rutenya.
func capturePattern(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if info := requestInfoFrom(r.Context()); info != nil {
				info.pattern = r.Pattern
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// WithRequestID membungkus handler slog agar log yang ditulis dengan context permintaan (slog.*Context)
// membawa request_id yang sama dengan log akses dan header X-Request-ID.
func WithRequestID(h slog.Handler) slog.Handler { return requestIDHandler{h} }

type requestIDHandler struct{ slog.Handler }

func (h requestIDHandler) Handle(ctx context.Context, r slog.Record) error {
	if id := RequestID(ctx); id != "" {
		r.AddAttrs(slog.String("request_id", id))
	}
	return h.Handler.Handle(ctx, r)
}

func (h requestIDHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return requestIDHandler{h.Handler.WithAttrs(attrs)}
}

func (h requestIDHandler) WithGroup(name string) slog.Handler {
	return requestIDHandler{h.Handler.WithGroup(name)}
}
