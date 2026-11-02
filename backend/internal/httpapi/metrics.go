package httpapi

import (
	"bufio"
	"io"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// durationBuckets dalam detik; 0,3 dtk adalah target p95 API (NFR-P05).
var durationBuckets = []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.3, 0.5, 1, 2.5, 5, 10}

// Metrics menyimpan metrik permintaan HTTP di memori dan menulisnya dalam format teks eksposisi
// Prometheus 0.0.4 (ADR-0054). Label hanya pola rute ServeMux dan status, jadi kardinalitasnya terbatas.
// Nil = tanpa metrik.
type Metrics struct {
	inFlight atomic.Int64
	mu       sync.Mutex
	requests map[requestKey]uint64
	duration map[string]*histogram
}

type requestKey struct {
	route  string
	status int
}

// histogram menyimpan hitungan per bucket (tidak kumulatif); kumulatif dihitung saat ditulis.
type histogram struct {
	buckets []uint64
	sum     float64
	count   uint64
}

// NewMetrics membuat penampung metrik kosong.
func NewMetrics() *Metrics {
	return &Metrics{requests: map[requestKey]uint64{}, duration: map[string]*histogram{}}
}

func (m *Metrics) begin() {
	if m != nil {
		m.inFlight.Add(1)
	}
}

func (m *Metrics) end(route string, status int, elapsed time.Duration) {
	if m == nil {
		return
	}
	m.inFlight.Add(-1)
	seconds := elapsed.Seconds()
	m.mu.Lock()
	defer m.mu.Unlock()
	m.requests[requestKey{route, status}]++
	h := m.duration[route]
	if h == nil {
		h = &histogram{buckets: make([]uint64, len(durationBuckets))}
		m.duration[route] = h
	}
	for i, le := range durationBuckets {
		if seconds <= le {
			h.buckets[i]++
			break
		}
	}
	h.sum += seconds
	h.count++
}

// ServeHTTP menulis semua metrik, terurut agar deterministik.
func (m *Metrics) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	out := bufio.NewWriter(w)
	m.write(out)
	_ = out.Flush()
}

func (m *Metrics) write(w io.Writer) {
	m.mu.Lock()
	defer m.mu.Unlock()
	keys := make([]requestKey, 0, len(m.requests))
	for k := range m.requests {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].route != keys[j].route {
			return keys[i].route < keys[j].route
		}
		return keys[i].status < keys[j].status
	})
	io.WriteString(w, "# HELP anastrophe_http_requests_total Jumlah permintaan HTTP per pola rute dan status.\n")
	io.WriteString(w, "# TYPE anastrophe_http_requests_total counter\n")
	for _, k := range keys {
		io.WriteString(w, `anastrophe_http_requests_total{route="`+escapeLabel(k.route)+`",status="`+strconv.Itoa(k.status)+`"} `+strconv.FormatUint(m.requests[k], 10)+"\n")
	}
	routes := make([]string, 0, len(m.duration))
	for r := range m.duration {
		routes = append(routes, r)
	}
	sort.Strings(routes)
	io.WriteString(w, "# HELP anastrophe_http_request_duration_seconds Durasi permintaan HTTP per pola rute.\n")
	io.WriteString(w, "# TYPE anastrophe_http_request_duration_seconds histogram\n")
	for _, r := range routes {
		h, label := m.duration[r], escapeLabel(r)
		var cumulative uint64
		for i, le := range durationBuckets {
			cumulative += h.buckets[i]
			io.WriteString(w, `anastrophe_http_request_duration_seconds_bucket{route="`+label+`",le="`+strconv.FormatFloat(le, 'g', -1, 64)+`"} `+strconv.FormatUint(cumulative, 10)+"\n")
		}
		io.WriteString(w, `anastrophe_http_request_duration_seconds_bucket{route="`+label+`",le="+Inf"} `+strconv.FormatUint(h.count, 10)+"\n")
		io.WriteString(w, `anastrophe_http_request_duration_seconds_sum{route="`+label+`"} `+strconv.FormatFloat(h.sum, 'g', -1, 64)+"\n")
		io.WriteString(w, `anastrophe_http_request_duration_seconds_count{route="`+label+`"} `+strconv.FormatUint(h.count, 10)+"\n")
	}
	io.WriteString(w, "# HELP anastrophe_http_requests_in_flight Permintaan HTTP yang sedang dilayani.\n")
	io.WriteString(w, "# TYPE anastrophe_http_requests_in_flight gauge\n")
	io.WriteString(w, "anastrophe_http_requests_in_flight "+strconv.FormatInt(m.inFlight.Load(), 10)+"\n")
}

var labelEscaper = strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`)

// escapeLabel meng-escape nilai label menurut format teks Prometheus.
func escapeLabel(s string) string { return labelEscaper.Replace(s) }
