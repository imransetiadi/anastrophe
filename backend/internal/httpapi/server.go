// Package httpapi merakit REST /v1 Anastrophe (SDD §8.5).
package httpapi

import (
	"context"
	"log/slog"
	"net/http"
	"time"
)

// Config adalah konfigurasi per lingkungan yang dikembalikan GET /v1/config (FR-04).
type Config struct {
	EnabledChannels      []string
	WalletProgramEnabled bool
}

// Deps berisi layanan yang dipakai handler; diisi bertahap oleh task berikutnya. Logger nil = slog.Default().
type Deps struct {
	Routes func(mux *http.ServeMux)
	Logger *slog.Logger
}

// New mengembalikan handler HTTP lengkap. Urutan middleware: log akses (request id) → recoverer →
// deadline → pola rute → mux (ADR-0054).
func New(cfg Config, deps Deps) http.Handler {
	logger := deps.Logger
	if logger == nil {
		logger = slog.Default()
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("GET /v1/config", func(w http.ResponseWriter, _ *http.Request) {
		channels := cfg.EnabledChannels
		if channels == nil {
			channels = []string{}
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"enabled_channels":       channels,
			"wallet_program_enabled": cfg.WalletProgramEnabled,
		})
	})
	if deps.Routes != nil {
		deps.Routes(mux)
	}
	mux.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		WriteProblem(w, NewProblem("NOT-FOUND", http.StatusNotFound))
	})
	return accessLog(logger, recoverer(logger, withDeadline(capturePattern(mux))))
}

// Route mendaftarkan handler untuk satu metode, plus jawaban 405 problem+json untuk metode
// lain pada path yang sama (tanpa ini catch-all "/" mengubah 405 menjadi 404).
func Route(mux *http.ServeMux, method, path string, handler http.HandlerFunc) {
	mux.HandleFunc(method+" "+path, handler)
	mux.HandleFunc(path, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Allow", method)
		WriteProblem(w, NewProblem("METHOD-NOT-ALLOWED", http.StatusMethodNotAllowed))
	})
}

// RequestTimeout membatasi setiap permintaan; query database ikut dibatalkan lewat context,
// sehingga tidak ada permintaan yang menggantung selamanya (review backend C1).
const RequestTimeout = 15 * time.Second

func withDeadline(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), RequestTimeout)
		defer cancel()
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// recoverer mengubah panik menjadi 500 tanpa membocorkan detail ke klien.
func recoverer(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				if v == http.ErrAbortHandler {
					panic(v) // sinyal net/http untuk memutus koneksi; jangan ditelan
				}
				route := "/"
				if info := requestInfoFrom(r.Context()); info != nil {
					route = info.route()
				}
				// Nilai panik dan path mentah tidak di-log: bisa memuat data sensitif atau id (aturan 6).
				logger.ErrorContext(r.Context(), "panic in handler", "route", route)
				WriteProblem(w, NewProblem("INTERNAL", http.StatusInternalServerError))
			}
		}()
		next.ServeHTTP(w, r)
	})
}
