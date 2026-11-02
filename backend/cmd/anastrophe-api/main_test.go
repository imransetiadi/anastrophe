package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/imransetiadi/anastrophe/backend/internal/httpapi"
)

func TestRegistriWajibAdaKunci(t *testing.T) {
	// Tanpa kunci registri yang valid, API menolak start (ADR-0031).
	for _, key := range []string{"", "zz", strings.Repeat("ab", 31)} {
		if _, err := registryFromEnv(func(string) string { return key }); err == nil {
			t.Errorf("kunci %q seharusnya ditolak", key)
		}
	}
	if mac, err := registryFromEnv(func(string) string { return strings.Repeat("ab", 32) }); err != nil || mac == nil {
		t.Fatalf("kunci valid ditolak: %v", err)
	}
}

func TestListenerMetrikOpsional(t *testing.T) {
	// ADR-0054: /metrics hanya di listener internal yang dikonfigurasi.
	m := httpapi.NewMetrics()
	if s := newMetricsServer("", m); s != nil {
		t.Fatal("listener metrik dibuat tanpa ANASTROPHE_METRICS_ADDR")
	}
	s := newMetricsServer("127.0.0.1:0", m)
	if s == nil {
		t.Fatal("listener metrik tidak dibuat")
	}
	rec := httptest.NewRecorder()
	s.Handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "anastrophe_http_requests_in_flight") {
		t.Fatalf("/metrics: %d %s", rec.Code, rec.Body)
	}
	rec = httptest.NewRecorder()
	s.Handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/config", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("listener metrik melayani path lain: %d", rec.Code)
	}
}

func TestFormatLog(t *testing.T) {
	var buf bytes.Buffer
	loggerFromEnv(func(k string) string {
		if k == "ANASTROPHE_LOG_FORMAT" {
			return "json"
		}
		return ""
	}, &buf).Info("uji", "k", "v")
	var m map[string]any
	if err := json.Unmarshal(buf.Bytes(), &m); err != nil || m["msg"] != "uji" {
		t.Fatalf("log JSON = %q (%v)", buf.String(), err)
	}
	buf.Reset()
	loggerFromEnv(func(string) string { return "" }, &buf).Info("uji")
	if !strings.Contains(buf.String(), "level=INFO") || !strings.Contains(buf.String(), "msg=uji") {
		t.Fatalf("log teks = %q", buf.String())
	}
}
