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

// Deps berisi layanan yang dipakai handler; diisi bertahap oleh task berikutnya.
type Deps struct {
	Routes func(mux *http.ServeMux)
}

// New mengembalikan handler HTTP lengkap.
func New(cfg Config, deps Deps) http.Handler {
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
		WriteProblem(w, Problem{Type: "NOT-FOUND", Title: "Not found", Status: http.StatusNotFound})
	})
	return recoverer(withDeadline(mux))
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
func recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				slog.Error("panic in handler", "path", r.URL.Path) // nilai panik tidak di-log: bisa memuat data sensitif
				WriteProblem(w, Problem{Type: "INTERNAL", Title: "Internal error", Status: http.StatusInternalServerError})
			}
		}()
		next.ServeHTTP(w, r)
	})
}
