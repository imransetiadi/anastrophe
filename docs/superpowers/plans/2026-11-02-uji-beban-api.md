# Uji Beban API — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Alat uji beban stdlib untuk skenario config, lookup, enrol, dan renew, beserta baseline lab TC-PERF-05.

**Architecture:**
- `internal/loadtest` berisi `Runner` (pekerja, durasi, laju bersama), `Recorder` (latensi per langkah), dan `Scenario` (fungsi iterasi yang memanggil langkah HTTP).
- `cmd/anastrophe-loadtest` berisi `gen-cards` dan `run`, dengan penjaga loopback dan pembacaan `/metrics`.

**Tech Stack:** Go 1.27 stdlib (`net/http`, `crypto/ecdsa`, `sync`, `time`).

**Spec:** `docs/superpowers/specs/2026-11-02-uji-beban-api-design.md` (ADR-0055).

## Global Constraints

- **Dependensi:** tidak ada dependensi baru.
- **Keluaran:** tanpa rahasia, kunci, identitas kartu, atau kontak di log dan laporan. Identitas kartu hanya sintetis dengan awalan `084C54`.
- **Target:** hanya host loopback kecuali `-allow-remote`.
- **Commit:** pesan berbahasa Indonesia dan diakhiri `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Tanpa push.
- **Verifikasi:** `go -C backend vet ./...`, `env ANASTROPHE_REQUIRE_PG=1 go -C backend test ./... -race`, dan `check_docs` exit 0 (exit code).

## Review Focus

1. **Persentil.** Test: `TestPersentil`.
2. **Laju dan durasi.** Test: `TestRunnerLaju`, `TestRunnerBerhentiSaatDurasiHabis`.
3. **Format protokol skenario.** Test: `TestSkenarioTerhadapAPI` (integrasi, 0 galat; renew memakai kredensial dari enrol).
4. **Tanpa rahasia di keluaran.** Test: `TestLaporanTanpaRahasia`.
5. **Penjaga loopback.** Test: `TestTolakHostNonLoopback`.

---

### Task 1: Runner, perekam, dan laporan

**Files:**
- Create: `backend/internal/loadtest/runner.go`, `backend/internal/loadtest/report.go`, `backend/internal/loadtest/runner_test.go`

**Interfaces:**
- Produces:
  - `type Step func(ctx context.Context) (status int, err error)`;
  - `type Iteration func(ctx context.Context, rec *Recorder) error`;
  - `type Recorder` dengan method `Observe(step string, d time.Duration, status int, err error)`, `Summary() []StepSummary`, dan `Measure(step string, fn Step)`;
  - `type StepSummary struct{ Step string; Count, Errors int; ByStatus map[int]int; P50, P95, P99, Max time.Duration }`;
  - `func Percentile(sorted []time.Duration, p float64) time.Duration` (nearest-rank);
  - `type Runner struct{ Concurrency int; Duration time.Duration; Rate float64 }` dengan method `Run(ctx, Iteration) *Recorder`;
  - `func Report(w io.Writer, summaries []StepSummary, elapsed time.Duration)`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `TestPersentil`: [1..100] ms → p50 = 50, p95 = 95, p99 = 99; satu sampel; kosong → 0.
  - `TestRunnerBerhentiSaatDurasiHabis`: 4 pekerja, durasi 200 ms, iterasi 1 ms → selesai < 400 ms dan jumlah > 0.
  - `TestRunnerLaju`: laju 50/dtk selama 1 dtk → jumlah iterasi ≤ 50 + 4 (toleransi start).
  - `TestRecorderGalatPerStatus`: status 500 dan galat jaringan terhitung sebagai galat dengan status masing-masing.
  - `TestLaporanTanpaRahasia`: laporan hanya memuat nama langkah, angka, dan status.
- [ ] **Step 2: Jalankan.** Expected: FAIL.
- [ ] **Step 3: Implementasikan.** Laju bersama memakai satu ticker yang membagikan token ke pekerja lewat channel.
- [ ] **Step 4: Jalankan.** Expected: PASS (`-race`).
- [ ] **Step 5: Commit** `feat(loadtest): runner, perekam latensi, dan laporan (TC-PERF-05, ADR-0055)`.

### Task 2: Skenario dan pool kartu sintetis

**Files:**
- Create: `backend/internal/loadtest/scenarios.go`, `backend/internal/loadtest/cards.go`, `backend/internal/loadtest/scenarios_test.go`, `backend/internal/loadtest/cards_test.go`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `type Client struct{ Base string; HTTP *http.Client; SiteID, JoinCode string; Cards *CardPool; Creds *CredPool }`;
  - `func (c *Client) Config(ctx, rec) error`, `Lookup`, `Enrol`, dan `Renew` (bertipe `Iteration`);
  - `func GenerateCards(w io.Writer, n int) error` (CSV impor registri, awalan `084C54`);
  - `func LoadCards(r io.Reader) (*CardPool, error)`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `TestKartuSintetis`: CSV ber-header `tech,card_id,holder_contact,zones`, n baris unik dengan awalan `084C54`, `holder_contact` kosong; `LoadCards` membaca ulang semuanya.
  - `TestSkenarioTerhadapAPI` (testpg, API in-process lewat `httptest.NewServer`):
    - gedung dan kartu didaftarkan (HMAC lewat `registry.DevMAC`) dan kode gedung dirotasi;
    - masing-masing 3 iterasi `Config` dan `Lookup`, 3 `Enrol`, dan 3 `Renew` → 0 galat;
    - `Renew` memakai kredensial dari `Enrol`;
    - status: provisioning 200, challenge 201, renew 200.
  - `TestRenewTanpaKredensialGagalJelas`: pool kredensial kosong → galat eksplisit.
- [ ] **Step 2: Jalankan.** Expected: FAIL.
- [ ] **Step 3: Implementasikan.**
  - Format mengikuti handler: body JSON enrolment/provisioning, `Bearer` base64url rahasia, `Idempotency-Key` acak, tanda tangan perpanjangan.
  - Pool kartu dan kredensial aman dipakai bersamaan.
- [ ] **Step 4: Jalankan seluruh Go dengan `-race`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(loadtest): skenario config, lookup, enrol, dan renew dengan kartu sintetis (ADR-0055)`.

### Task 3: CLI, pembacaan `/metrics`, dan baseline lab

**Files:**
- Create: `backend/cmd/anastrophe-loadtest/main.go`, `backend/cmd/anastrophe-loadtest/main_test.go`, `backend/internal/loadtest/promtext.go`, `backend/internal/loadtest/promtext_test.go`

**Interfaces:**
- Consumes: Task 1–2.
- Produces:
  - `func ParseDurationShares(before, after string, le string) map[string]Share` (porsi ≤ batas per rute dari selisih bucket);
  - CLI `gen-cards -n` dan `run …`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `TestPorsiDariMetrik`: dua teks eksposisi → porsi per rute benar, termasuk rute baru di teks kedua.
  - `TestTolakHostNonLoopback`: `-base https://api.contoh.id` tanpa `-allow-remote` → galat; `http://127.0.0.1:8080` dan `http://localhost:8080` → ok.
  - `TestGenCardsCLI`: keluaran CSV valid.
- [ ] **Step 2: Jalankan.** Expected: FAIL.
- [ ] **Step 3: Implementasikan** CLI dan pembaca teks eksposisi (hanya baris bucket/count untuk batas yang diminta).
- [ ] **Step 4: Baseline lab:**
  - impor kartu sintetis ke PostgreSQL lab, lalu jalankan API dengan `ANASTROPHE_METRICS_ADDR`;
  - tiap skenario dijalankan 20 dtk pada konkurensi 8 dan 32;
  - simpan laporan di scratchpad dan ringkas di dokumen.
- [ ] **Step 5: Commit** `feat(loadtest): CLI uji beban dengan penjaga loopback dan porsi SLO dari /metrics (ADR-0055)`.

### Task 4: Dokumen

**Files:**
- Modify:
  - `docs/QA_SUITE.md`: hasil baseline lab TC-PERF-05 di §11.1 (lingkungan, angka, batasan);
  - `docs/SDD.md`: catatan alat uji beban di §14 dan revisi;
  - `README.md`: perintah uji beban;
  - `docs/agentmemory/backlog.md`: titik panas yang ditemukan.

- [ ] **Step 1: Perbarui dokumen**, lalu jalankan `check_docs` (exit 0).
- [ ] **Step 2: Commit** `docs: uji beban API dan baseline lab (QA TC-PERF-05, SDD §14)`.
