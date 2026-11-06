package main

import (
	"bytes"
	"encoding/json"
	"log/slog"
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

// TestErrorLogKeSlogWarn (minor review akhir ADR-0054): http.Server.ErrorLog bawaan menulis ke os.Stderr
// lewat paket log standar, di luar logger terstruktur app (format, redaksi request_id, dan tujuan log
// terpusat). Galat net/http sendiri (mis. TLS handshake gagal) bisa memuat alamat IP klien, jadi harus
// lewat logger yang sama dengan log akses, bukan jalur terpisah yang tak diawasi.
func TestErrorLogKeSlogWarn(t *testing.T) {
	var buf bytes.Buffer
	logger := slog.New(slog.NewTextHandler(&buf, nil))
	srv := newAPIServer(":0", http.NotFoundHandler(), logger)
	if srv.ErrorLog == nil {
		t.Fatal("ErrorLog tidak diset")
	}
	srv.ErrorLog.Print("galat jaringan percobaan")
	if !strings.Contains(buf.String(), "level=WARN") || !strings.Contains(buf.String(), "galat jaringan percobaan") {
		t.Fatalf("log = %q, ingin level WARN lewat logger app", buf.String())
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
	// Review akhir ADR-0054: scraper yang macet tidak boleh menahan koneksi tanpa batas.
	if s.WriteTimeout <= 0 || s.IdleTimeout <= 0 || s.ReadHeaderTimeout <= 0 {
		t.Fatalf("timeout listener metrik: write %v idle %v header %v", s.WriteTimeout, s.IdleTimeout, s.ReadHeaderTimeout)
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

// TestFormatLogTidakPekaHurufBesar (minor review akhir ADR-0054): operator yang menulis ANASTROPHE_LOG_FORMAT
// sebagai "JSON" atau "Json" sebelumnya jatuh diam-diam ke format teks (hanya perbandingan "json" persis).
func TestFormatLogTidakPekaHurufBesar(t *testing.T) {
	for _, v := range []string{"JSON", "Json", "json", " json ", "\tjson\n"} {
		var buf bytes.Buffer
		loggerFromEnv(func(k string) string {
			if k == "ANASTROPHE_LOG_FORMAT" {
				return v
			}
			return ""
		}, &buf).Info("uji")
		var m map[string]any
		if err := json.Unmarshal(buf.Bytes(), &m); err != nil || m["msg"] != "uji" {
			t.Fatalf("ANASTROPHE_LOG_FORMAT=%q: log = %q (%v), ingin JSON", v, buf.String(), err)
		}
	}
	// Nilai tak dikenal tetap jatuh ke teks, bukan dianggap galat konfigurasi diam-diam.
	var buf bytes.Buffer
	loggerFromEnv(func(string) string { return "xml" }, &buf).Info("uji")
	if !strings.Contains(buf.String(), "level=INFO") {
		t.Fatalf("ANASTROPHE_LOG_FORMAT=xml: log = %q, ingin format teks", buf.String())
	}
}
