package httpapi

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"sync"
	"testing"
)

// logBuffer mengumpulkan baris log JSON (aman dipakai bersamaan).
type logBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *logBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *logBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

func (b *logBuffer) records(t *testing.T) []map[string]any {
	t.Helper()
	var out []map[string]any
	for _, line := range strings.Split(strings.TrimSpace(b.String()), "\n") {
		if line == "" {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(line), &m); err != nil {
			t.Fatalf("baris log bukan JSON: %q", line)
		}
		out = append(out, m)
	}
	return out
}

func byMsg(records []map[string]any, msg string) []map[string]any {
	var out []map[string]any
	for _, r := range records {
		if r["msg"] == msg {
			out = append(out, r)
		}
	}
	return out
}

func observedHandler(t *testing.T, routes func(*http.ServeMux, *slog.Logger)) (http.Handler, *logBuffer) {
	t.Helper()
	buf := &logBuffer{}
	logger := slog.New(WithRequestID(slog.NewJSONHandler(buf, nil)))
	return New(Config{}, Deps{Logger: logger, Routes: func(mux *http.ServeMux) {
		if routes != nil {
			routes(mux, logger)
		}
	}}), buf
}

func TestLogAksesTanpaDataPribadi(t *testing.T) {
	// ADR-0054: satu baris per permintaan dengan pola rute; tanpa path mentah, query, body, atau IP (aturan 6).
	h, buf := observedHandler(t, func(mux *http.ServeMux, _ *slog.Logger) {
		Route(mux, http.MethodPost, "/v1/uji/{id}", func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusCreated)
			_, _ = w.Write([]byte("ok"))
		})
	})
	const id = "3f1e2d4c-5b6a-4789-8abc-def012345678"
	req := httptest.NewRequest(http.MethodPost, "/v1/uji/"+id+"?site=RAHASIA-QUERY&card=04A1B2C3", strings.NewReader(`{"card":{"tech":"iso14443a","id":"04A1B2C3"}}`))
	req.RemoteAddr = "203.0.113.7:5000"
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("status %d", rec.Code)
	}
	access := byMsg(buf.records(t), "http request")
	if len(access) != 1 {
		t.Fatalf("log akses = %d baris: %s", len(access), buf.String())
	}
	a := access[0]
	if a["route"] != "POST /v1/uji/{id}" || a["status"] != float64(201) || a["bytes"] != float64(2) {
		t.Fatalf("log akses = %v", a)
	}
	if d, ok := a["duration_ms"].(float64); !ok || d < 0 {
		t.Fatalf("duration_ms = %v", a["duration_ms"])
	}
	if a["request_id"] == nil || a["request_id"] != rec.Header().Get("X-Request-ID") {
		t.Fatalf("request_id log %v, header %q", a["request_id"], rec.Header().Get("X-Request-ID"))
	}
	for _, secret := range []string{id, "RAHASIA-QUERY", "04A1B2C3", "203.0.113.7"} {
		if strings.Contains(buf.String(), secret) {
			t.Fatalf("log memuat %q: %s", secret, buf.String())
		}
	}
}

func TestRequestIDUnik(t *testing.T) {
	h, _ := observedHandler(t, nil)
	pattern := regexp.MustCompile(`^[0-9a-f]{16}$`)
	seen := map[string]bool{}
	for i := 0; i < 2; i++ {
		req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
		req.Header.Set("X-Request-ID", "palsu")
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		id := rec.Header().Get("X-Request-ID")
		if !pattern.MatchString(id) || seen[id] {
			t.Fatalf("request id %q (sudah dipakai: %v)", id, seen[id])
		}
		seen[id] = true
	}
}

func TestLogGalatMembawaRequestID(t *testing.T) {
	h, buf := observedHandler(t, func(mux *http.ServeMux, logger *slog.Logger) {
		Route(mux, http.MethodGet, "/v1/gagal", func(w http.ResponseWriter, r *http.Request) {
			logger.ErrorContext(r.Context(), "gagal", "err_type", "uji")
			w.WriteHeader(http.StatusInternalServerError)
		})
	})
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/gagal", nil))
	errs := byMsg(buf.records(t), "gagal")
	if len(errs) != 1 || errs[0]["request_id"] != rec.Header().Get("X-Request-ID") {
		t.Fatalf("log galat = %v, header %q", errs, rec.Header().Get("X-Request-ID"))
	}
}

func TestPanicTercatat(t *testing.T) {
	h, buf := observedHandler(t, func(mux *http.ServeMux, _ *slog.Logger) {
		Route(mux, http.MethodGet, "/v1/panik/{id}", func(http.ResponseWriter, *http.Request) {
			panic("rahasia-panik")
		})
	})
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/panik/ID-RAHASIA-PATH", nil))
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status %d", rec.Code)
	}
	records := buf.records(t)
	access := byMsg(records, "http request")
	panics := byMsg(records, "panic in handler")
	if len(access) != 1 || access[0]["status"] != float64(500) || access[0]["route"] != "GET /v1/panik/{id}" {
		t.Fatalf("log akses = %v", access)
	}
	if len(panics) != 1 || panics[0]["route"] != "GET /v1/panik/{id}" || panics[0]["request_id"] != rec.Header().Get("X-Request-ID") {
		t.Fatalf("log panic = %v", panics)
	}
	for _, secret := range []string{"ID-RAHASIA-PATH", "rahasia-panik"} {
		if strings.Contains(buf.String(), secret) {
			t.Fatalf("log memuat %q", secret)
		}
	}
}
