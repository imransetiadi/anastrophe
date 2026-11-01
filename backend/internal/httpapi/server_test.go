package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func serve(t *testing.T, h http.Handler, method, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, path, nil))
	return rec
}

func TestHealthz(t *testing.T) {
	rec := serve(t, New(Config{}, Deps{}), http.MethodGet, "/healthz")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
}

func TestConfigSnakeCase(t *testing.T) {
	rec := serve(t, New(Config{EnabledChannels: []string{"ble"}}, Deps{}), http.MethodGet, "/v1/config")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if got := body["enabled_channels"]; len(got.([]any)) != 1 || got.([]any)[0] != "ble" {
		t.Fatalf("enabled_channels = %v", got)
	}
	if got, ok := body["wallet_program_enabled"]; !ok || got != false {
		t.Fatalf("wallet_program_enabled = %v", got)
	}
}

func TestRuteTakDikenalProblemJSON(t *testing.T) {
	rec := serve(t, New(Config{}, Deps{}), http.MethodGet, "/v1/tidak-ada")
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/problem+json" {
		t.Fatalf("content-type = %q", ct)
	}
	var p Problem
	if err := json.Unmarshal(rec.Body.Bytes(), &p); err != nil || p.Type != "NOT-FOUND" || p.Status != 404 {
		t.Fatalf("problem = %+v, err = %v", p, err)
	}
}

func TestErrorTidakMembocorkanDetail(t *testing.T) {
	// Review Focus 5: pesan error Go/SQL mentah tidak boleh sampai ke klien.
	h := recoverer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic("pq: password authentication failed for user secret_admin")
	}))
	rec := serve(t, h, http.MethodGet, "/")
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "secret_admin") || strings.Contains(rec.Body.String(), "pq:") {
		t.Fatalf("body membocorkan detail: %s", rec.Body.String())
	}
	var p Problem
	if err := json.Unmarshal(rec.Body.Bytes(), &p); err != nil || p.Type != "INTERNAL" {
		t.Fatalf("problem = %+v", p)
	}
}

func TestSetiapPermintaanPunyaDeadline(t *testing.T) {
	var hasDeadline bool
	h := New(Config{}, Deps{Routes: func(mux *http.ServeMux) {
		mux.HandleFunc("GET /probe", func(w http.ResponseWriter, r *http.Request) {
			_, hasDeadline = r.Context().Deadline()
		})
	}})
	serve(t, h, http.MethodGet, "/probe")
	if !hasDeadline {
		t.Fatal("permintaan tanpa deadline bisa menggantung selamanya")
	}
}
