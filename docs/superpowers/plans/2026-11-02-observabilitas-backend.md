# Observabilitas Backend — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backend menulis log akses terstruktur tanpa data pribadi, dengan request id yang ikut di log galat, dan mengekspos metrik permintaan di listener internal.

**Architecture:** middleware `httpapi`, dengan susunan `accessLog → recoverer → withDeadline → capturePattern → mux`.
- Pola rute dicatat ke struct di context oleh `capturePattern` sesudah mux berjalan.
- `Metrics` menyimpan hitungan dan histogram dalam memori, lalu menulis format teks Prometheus.
- Handler slog pembungkus menambahkan `request_id` dari context.

**Tech Stack:** Go 1.27 stdlib (`log/slog`, `net/http`, `sync`, `crypto/rand`).

**Spec:** `docs/superpowers/specs/2026-11-02-observabilitas-backend-design.md` (ADR-0054).

## Global Constraints

- **Log dan label:** tanpa path mentah, query, body, header, IP, identitas kartu, kontak, token, atau rahasia. `route` hanya pola ServeMux.
- **Dependensi:** tidak ada dependensi baru.
- **`/metrics`:** hanya di listener internal (`ANASTROPHE_METRICS_ADDR`). Port publik → 404.
- **Commit:** pesan berbahasa Indonesia dan diakhiri `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Tanpa push.
- **Verifikasi:** `go -C backend vet ./...`, `env ANASTROPHE_REQUIRE_PG=1 go -C backend test ./... -race`, dan `check_docs` exit 0 (exit code).

## Review Focus

1. **Tanpa data pribadi di log, termasuk jalur galat dan panic.** Test: `TestLogAksesTanpaDataPribadi`, `TestPanicTercatat`.
2. **Pola rute walau request disalin.** Test: `TestLogAksesTanpaDataPribadi` (route = pola dengan `{id}`).
3. **Kardinalitas terbatas.** Test: `TestMetrikPerRuteDanStatus` (rute tak dikenal → `/`).
4. **`/metrics` tidak di port publik.** Test: `TestMetrikTidakDiPortPublik`.
5. **Konkurensi.** Test: `TestMetrikBersamaan` dengan `-race`.

---

### Task 1: Log akses, request id, dan korelasi galat

**Files:**
- Create: `backend/internal/httpapi/observe.go`, `backend/internal/httpapi/observe_test.go`
- Modify: `backend/internal/httpapi/server.go` (susunan middleware, `Deps.Logger`, panic memakai pola rute)

**Interfaces:**
- Produces:
  - `type Deps struct{ Routes func(*http.ServeMux); Metrics *Metrics; Logger *slog.Logger }`;
  - `func RequestID(ctx context.Context) string`;
  - `func WithRequestID(h slog.Handler) slog.Handler`;
  - header `X-Request-ID`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `TestLogAksesTanpaDataPribadi`: rute uji `POST /v1/uji/{id}` (201) dipanggil dengan path id UUID, query `site=RAHASIA-QUERY&card=04A1B2C3`, body identitas kartu, dan `RemoteAddr` `203.0.113.7:5000`. Log (JSON ke buffer) memuat `msg="http request"`, `route="POST /v1/uji/{id}"`, `status=201`, `duration_ms`, `bytes`, dan `request_id` = header `X-Request-ID`. Log tidak memuat UUID, `RAHASIA-QUERY`, `04A1B2C3`, isi body, atau `203.0.113.7`.
  - `TestRequestIDUnik`: dua permintaan → id berbeda, `^[0-9a-f]{16}$`; header klien `X-Request-ID: palsu` diabaikan.
  - `TestLogGalatMembawaRequestID`: handler memanggil `slog.ErrorContext(r.Context(), "gagal")` lewat logger dari `WithRequestID` → record memuat `request_id` yang sama.
  - `TestPanicTercatat`: handler panic → respons 500, log akses `status=500`, dan log panic memakai pola rute tanpa path mentah.
- [ ] **Step 2: Jalankan** `go -C backend test ./internal/httpapi/`. Expected: FAIL.
- [ ] **Step 3: Implementasikan:**
  - `statusRecorder` (status dan bytes);
  - `requestInfo` di context (id dan pola);
  - `capturePattern` membaca `r.Pattern` sesudah mux;
  - `accessLog` mencatat sesudah handler;
  - `WithRequestID` menambahkan atribut dari context.
- [ ] **Step 4: Ubah titik log galat** di `internal/enroll` (`writeResult`, sites, status, renew) ke `slog.ErrorContext(r.Context(), …)`. Jalankan seluruh Go. Expected: PASS.
- [ ] **Step 5: Commit** `feat(backend): log akses terstruktur dan request id (NFR-O01, ADR-0054)`.

### Task 2: Metrik dan listener internal

**Files:**
- Create: `backend/internal/httpapi/metrics.go`, `backend/internal/httpapi/metrics_test.go`
- Modify: `backend/internal/httpapi/server.go` (merekam metrik di `accessLog`), `backend/cmd/anastrophe-api/main.go` (`ANASTROPHE_METRICS_ADDR`, `ANASTROPHE_LOG_FORMAT`, shutdown)

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `func NewMetrics() *Metrics`;
  - `(*Metrics).ServeHTTP` (eksposisi teks);
  - `func newMetricsServer(addr string, m *httpapi.Metrics) *http.Server` (nil bila addr kosong);
  - `func loggerFromEnv(getenv func(string) string, w io.Writer) *slog.Logger` di main.

- [ ] **Step 1: Tulis test yang gagal:**
  - `TestMetrikPerRuteDanStatus`: tiga permintaan, masing-masing ke rute terdaftar (201), rute tak dikenal (404), metode salah (405), dan panic (500). Teks memuat `anastrophe_http_requests_total{route="POST /v1/uji/{id}",status="201"} 1`, `{route="/",status="404"} 1`, dan baris 405 serta 500. Bucket histogram kumulatif; `le="+Inf"` = `_count`; ada `le="0.3"`; `anastrophe_http_requests_in_flight 0`.
  - `TestEscapeLabel`: `"`, `\`, dan newline di-escape.
  - `TestMetrikTidakDiPortPublik`: handler publik `GET /metrics` → 404.
  - `TestMetrikBersamaan`: 50 goroutine × 20 permintaan → total 1000 (`-race`).
  - `TestListenerMetrikOpsional` (main): addr kosong → nil; addr diisi → server dengan `/metrics`, path lain 404.
  - `TestFormatLog` (main): `json` → baris JSON; selain itu teks.
- [ ] **Step 2: Jalankan.** Expected: FAIL.
- [ ] **Step 3: Implementasikan** (mutex + map, histogram kumulatif saat ditulis; listener kedua ikut shutdown).
- [ ] **Step 4: Jalankan seluruh Go dengan `-race`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(backend): metrik permintaan di listener internal (NFR-O01, ADR-0054)`.

### Task 3: Dokumen

**Files:**
- Modify:
  - `docs/SDD.md`: catatan observabilitas di §12 (operasional) atau §8.5, plus revisi;
  - `docs/QA_SUITE.md`: TC-OPS-01 di katalog bila belum ada, hasil di §11.1, §14 NFR-O01;
  - README backend/root: variabel lingkungan baru bila ada daftarnya.

- [ ] **Step 1: Perbarui dokumen**, lalu jalankan `check_docs` (exit 0).
- [ ] **Step 2: Commit** `docs: observabilitas backend (SDD, QA)`.
