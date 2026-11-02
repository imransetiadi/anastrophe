package httpapi

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

func metricsHandler(t *testing.T, m *Metrics) http.Handler {
	t.Helper()
	return New(Config{}, Deps{Metrics: m, Logger: slog.New(slog.NewTextHandler(io.Discard, nil)), Routes: func(mux *http.ServeMux) {
		Route(mux, http.MethodPost, "/v1/uji/{id}", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusCreated) })
		Route(mux, http.MethodGet, "/v1/panik", func(http.ResponseWriter, *http.Request) { panic("uji") })
	}})
}

func scrape(t *testing.T, m *Metrics) (string, http.Header) {
	t.Helper()
	rec := httptest.NewRecorder()
	m.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	return rec.Body.String(), rec.Header()
}

func TestMetrikPerRuteDanStatus(t *testing.T) {
	m := NewMetrics()
	h := metricsHandler(t, m)
	for i := 0; i < 3; i++ {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/v1/uji/"+strconv.Itoa(i), nil))
	}
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/tidak-ada/04A1B2C3", nil))
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodDelete, "/v1/uji/1", nil))
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/v1/panik", nil))
	text, header := scrape(t, m)
	if !strings.HasPrefix(header.Get("Content-Type"), "text/plain; version=0.0.4") {
		t.Fatalf("Content-Type = %q", header.Get("Content-Type"))
	}
	for _, want := range []string{
		`anastrophe_http_requests_total{route="POST /v1/uji/{id}",status="201"} 3`,
		`anastrophe_http_requests_total{route="/",status="404"} 1`,
		`anastrophe_http_requests_total{route="/v1/uji/{id}",status="405"} 1`,
		`anastrophe_http_requests_total{route="GET /v1/panik",status="500"} 1`,
		`anastrophe_http_request_duration_seconds_count{route="POST /v1/uji/{id}"} 3`,
		`anastrophe_http_request_duration_seconds_bucket{route="POST /v1/uji/{id}",le="+Inf"} 3`,
		`anastrophe_http_requests_in_flight 0`,
		`# TYPE anastrophe_http_requests_total counter`,
		`# TYPE anastrophe_http_request_duration_seconds histogram`,
		`# TYPE anastrophe_http_requests_in_flight gauge`,
	} {
		if !strings.Contains(text, want+"\n") {
			t.Fatalf("metrik tanpa %q:\n%s", want, text)
		}
	}
	if strings.Contains(text, "04A1B2C3") {
		t.Fatal("path mentah muncul sebagai label")
	}
	// Bucket kumulatif dan tidak menurun, termasuk batas 0,3 dtk (NFR-P05).
	prefix := `anastrophe_http_request_duration_seconds_bucket{route="POST /v1/uji/{id}",le="`
	last, sawTarget := -1, false
	for _, line := range strings.Split(text, "\n") {
		if !strings.HasPrefix(line, prefix) {
			continue
		}
		if strings.HasPrefix(line, prefix+`0.3"}`) {
			sawTarget = true
		}
		v, err := strconv.Atoi(line[strings.LastIndex(line, " ")+1:])
		if err != nil || v < last {
			t.Fatalf("bucket tidak kumulatif: %q", line)
		}
		last = v
	}
	if !sawTarget || last != 3 {
		t.Fatalf("bucket 0.3 ada: %v, terakhir %d", sawTarget, last)
	}
}

func TestEscapeLabel(t *testing.T) {
	if got := escapeLabel("a\"b\\c\nd"); got != `a\"b\\c\nd` {
		t.Fatalf("escape = %q", got)
	}
}

func TestMetrikTidakDiPortPublik(t *testing.T) {
	rec := httptest.NewRecorder()
	metricsHandler(t, NewMetrics()).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("GET /metrics di port publik = %d", rec.Code)
	}
}

func TestMetrikBersamaan(t *testing.T) {
	m := NewMetrics()
	h := metricsHandler(t, m)
	var wg sync.WaitGroup
	for g := 0; g < 50; g++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < 20; i++ {
				h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/v1/uji/x", nil))
			}
		}()
	}
	wg.Wait()
	if text, _ := scrape(t, m); !strings.Contains(text, `anastrophe_http_requests_total{route="POST /v1/uji/{id}",status="201"} 1000`+"\n") {
		t.Fatalf("hitungan bersamaan salah:\n%s", text)
	}
}

// blockingWriter meniru scraper yang berhenti membaca: Write memblok sampai dilepas.
type blockingWriter struct {
	header  http.Header
	started chan struct{}
	release chan struct{}
	once    sync.Once
}

func (b *blockingWriter) Header() http.Header { return b.header }
func (b *blockingWriter) WriteHeader(int)     {}
func (b *blockingWriter) Write(p []byte) (int, error) {
	b.once.Do(func() { close(b.started) })
	<-b.release
	return len(p), nil
}

func TestScrapeMacetTidakMemblokirPermintaan(t *testing.T) {
	// Review akhir ADR-0054 (Important): kunci metrik tidak boleh dipegang selama menulis ke jaringan, karena
	// setiap permintaan publik mengambil kunci yang sama di akhir log akses.
	m := NewMetrics()
	for i := 0; i < 50; i++ { // > 4 KiB teks agar penulisan terjadi selama render
		m.end("GET /v1/r"+strconv.Itoa(i), http.StatusOK, time.Millisecond)
	}
	bw := &blockingWriter{header: http.Header{}, started: make(chan struct{}), release: make(chan struct{})}
	defer close(bw.release)
	go m.ServeHTTP(bw, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	<-bw.started
	done := make(chan struct{})
	go func() {
		m.begin()
		m.end("GET /v1/r0", http.StatusOK, time.Millisecond)
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("permintaan terblokir oleh scrape yang macet")
	}
}
