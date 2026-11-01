# Siklus hidup kartu oleh operator dan status kartu di app — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Operator bisa menangguhkan, memulihkan, dan mencabut card instance lewat CLI, dan app menampilkan status itu tanpa push dan tanpa prompt autentikasi.

**Architecture:** Store Go menambah transisi status beraudit, denylist, dan hash token baca status (migrasi 0010). HTTP menerima hash token saat provisioning/perpanjangan dan menjawab `GET /v1/cards/{id}/status` dengan bearer token. App membuat token, menyimpannya di Keychain tanpa kehadiran pengguna, dan menyegarkan status saat foreground.

**Tech Stack:** Go 1.27 + PostgreSQL 16 (pgx v5), Swift 6 / SwiftUI / Swift Testing, CryptoKit.

**Spec:** [`docs/superpowers/specs/2026-11-01-siklus-hidup-kartu-design.md`](../specs/2026-11-01-siklus-hidup-kartu-design.md); ADR-0036, ADR-0037; FR-38, FR-50, FR-51; SDD §8.1, §8.4.3, §8.5; QA TC-ADM-03, TC-MGT-11, TC-MGT-12 (baru).

## Global Constraints

- Token baca status: 32 byte acak; server hanya menyimpan SHA-256; app menyimpan di Keychain `afterFirstUnlockThisDeviceOnly` (SDD §5.3). Token mentah tidak pernah di-log, diaudit, atau disimpan server (ADR-0037).
- `GET /v1/cards/{id}/status`: id bukan UUID/tak dikenal, header hilang/rusak, token salah, atau instance tanpa token → 404 `CARD-NOT-FOUND` dengan body identik.
- Transisi: `suspend` ACTIVE→SUSPENDED, `resume` SUSPENDED→ACTIVE, `revoke` {ACTIVE, SUSPENDED, PROVISIONING}→REVOKED; status lain ditolak tanpa perubahan dan tanpa audit. Audit `card.suspended`, `card.resumed`, `card.revoked {reason, credentials}`, aktor `operator:<pegangan>`.
- Alasan pencabutan `[a-z_]{1,32}`, default `operator`.
- Kredensial yang dicabut (operator maupun hapus kartu ADR-0026) masuk `denylist_entries` dengan `expires_at = not_after`.
- Status refresh di app paling sering sekali per 60 dtk; tidak pernah memakai `LAContext`; presentasi tidak menunggunya (FR-25).
- Batas 8 kartu di app dan server tetap (aturan 8). Teks UI ID dan EN. Dokumen dalam Bahasa Indonesia; `check_docs.py` 0 masalah.

## Review Focus

1. **Endpoint status identik.** Tak dikenal vs token salah vs tanpa token. Test: Task 2 `TestStatusKartuTidakBerlakuIdentik`.
2. **Token mentah bocor.** Test: Task 1 `TestHashTokenStatusSaja`, Task 2 `TestTokenStatusTidakBocor`.
3. **Transisi ilegal.** Test: Task 1 `TestTransisiIlegalDitolak`.
4. **Revoke konsisten.** Kredensial, denylist, slot, perpanjangan. Test: Task 1 `TestCabutKartuOperator`, Task 2 `TestPerpanjanganDitolakSetelahDitangguhkan`.
5. **Status app tidak menimpa status lokal yang lebih kuat; offline tetap.** Test: Task 5 `statusServerTidakMenimpaPerluDipindahkan`, `offlineMempertahankanStatus`.

---

### Task 1: Migrasi 0010 dan store

**Files:** Create `backend/internal/store/migrations/0010_card_lifecycle.sql`, `backend/internal/store/lifecycle.go`, `backend/internal/store/lifecycle_test.go`; Modify `backend/internal/store/store.go` (helper pencabutan bersama untuk `RevokeCard`).

**Interfaces — Produces:**
- `var ErrInvalidTransition = errors.New("store: transisi status tidak diizinkan")`
- `func (s *Store) SuspendCard(ctx, cardInstanceID, operator string, at time.Time) error`
- `func (s *Store) ResumeCard(ctx, cardInstanceID, operator string, at time.Time) error`
- `func (s *Store) RevokeCardInstance(ctx, cardInstanceID, reason, operator string, at time.Time) (int, error)` (jumlah kredensial dicabut)
- `type CardInstanceSummary struct { ID, Status, Origin string; Channels []string; CreatedAt time.Time }` dan `func (s *Store) ListCardInstances(ctx, siteID, status string) ([]CardInstanceSummary, error)`
- `func (t *Tx) SetStatusTokenHash(ctx, cardInstanceID string, hash []byte) error`
- `func (s *Store) CardStatusByToken(ctx, cardInstanceID string, tokenHash []byte) (string, error)` (`ErrNotFound` untuk semua kegagalan)

- [ ] Test gagal (`ANASTROPHE_REQUIRE_PG=1 go test ./internal/store -run 'TestTangguhkan|TestTransisi|TestCabut|TestDaftar|TestHashTokenStatus|TestStatusKartuDenganToken'`):
  - `TestTangguhkanDanPulihkan`: ACTIVE + 2 kredensial ACTIVE → suspend → instance dan kredensial SUSPENDED, audit `card.suspended`; resume → ACTIVE semua, audit `card.resumed`.
  - `TestTransisiIlegalDitolak`: resume dari ACTIVE, suspend dari PENDING_APPROVAL, suspend/resume/revoke dari REVOKED, alasan `Bukan Kode` → `ErrInvalidTransition` (alasan: `ErrInvalidReason`), tanpa perubahan status dan tanpa audit baru.
  - `TestCabutKartuOperator`: instance ACTIVE (1 kredensial) → revoke `hilang` → instance dan kredensial REVOKED (`revoke_reason = 'hilang'`), satu baris `denylist_entries` dengan `expires_at = not_after`, audit `card.revoked {reason: hilang, credentials: 1}`, perangkat bisa mendaftar kartu ke-8 lagi; revoke PROVISIONING tanpa kredensial → 0.
  - `TestHapusKartuMasukDenylist`: `RevokeCard` (hapus kartu ADR-0026) menulis denylist untuk kredensialnya.
  - `TestDaftarCardInstance`: daftar per gedung, filter status, asal `kartu`/`undangan`/`-`, kanal kredensial ACTIVE/SUSPENDED; tidak ada kolom HMAC/token.
  - `TestHashTokenStatusSaja` dan `TestStatusKartuDenganToken`: `SetStatusTokenHash` menyimpan 32 byte; `CardStatusByToken` benar → status; salah, tanpa hash, atau id tak dikenal → `ErrNotFound`; hash lain menimpa yang lama.
- [ ] Implementasi; mutasi untuk penjaga status dan denylist; `go test ./...` hijau; commit.

### Task 2: HTTP

**Files:** Modify `backend/internal/enroll/credentials.go` (route + provisioning), `backend/internal/enroll/renew.go`; Create `backend/internal/enroll/status.go`, `backend/internal/enroll/status_test.go`.

**Interfaces — Consumes:** Task 1 `SetStatusTokenHash`, `CardStatusByToken`. **Produces:** `GET /v1/cards/{id}/status` → 200 `{"status": "..."}` / 404 `CARD-NOT-FOUND`; field opsional `status_token_hash` (base64, 32 byte) di body provisioning dan `:renew`.

- [ ] Test gagal:
  - `TestProvisioningMenyimpanHashTokenStatus` dan `TestPerpanjanganMenggantiHashTokenStatus`: token dari app → status 200 `ACTIVE`; hash bukan 32 byte → 400 `REQ-INVALID`; pengulangan Idempotency-Key dengan hash berbeda → 422.
  - `TestStatusKartuTidakBerlakuIdentik`: id bukan UUID, id tak dikenal, tanpa header, skema bukan Bearer, token base64 rusak, token salah, instance tanpa token → status dan body identik 404 `CARD-NOT-FOUND`.
  - `TestPerpanjanganDitolakSetelahDitangguhkan`: setelah `SuspendCard`, `:renew` → 409 `CRED-NOT-RENEWABLE`; endpoint status → `SUSPENDED`.
  - `TestTokenStatusTidakBocor`: token (base64url dan hex) tidak ada di slog, semua tabel, maupun baris idempotency.
- [ ] Implementasi; suite Go hijau; commit.

### Task 3: CLI operator

**Files:** Modify `backend/cmd/anastrophe-registry/main.go`, `main_test.go`, README.

**Interfaces — Consumes:** Task 1 `SuspendCard`, `ResumeCard`, `RevokeCardInstance`, `ListCardInstances`.

- [ ] Test gagal: `TestListCardInstance` (keluaran memuat id/status/asal, tanpa HMAC), `TestSuspendResumeRevoke` (kode keluar 0 dan status DB), `TestTransisiCLIDitolak` (kode keluar 2, pesan tanpa nilai rahasia), `TestRevokeAlasanTidakValid`.
- [ ] Implementasi; suite Go hijau; QA TC-ADM-03; commit.

### Task 4: App — token baca status

**Files:** Create `Packages/Sources/ANStorage/StatusTokenStore.swift`; Modify `Packages/Sources/ANNetworking/APIClient.swift`, `Packages/Sources/ANFeatures/Lab/LabProvisioning.swift`, `Packages/Sources/ANFeatures/CredentialRenewer.swift`, `Packages/Sources/ANFeatures/CardRemover.swift`, `Packages/Sources/ANFeatures/AppServices.swift`; Tests.

**Interfaces — Produces:**
- `public protocol StatusTokenStore: Sendable { func token(forCard id: String) throws -> Data?; func save(_ token: Data, forCard id: String) throws; func delete(forCard id: String) throws }` dan `KeychainStatusTokenStore(store: any SecretStore)` (`afterFirstUnlockThisDeviceOnly`).
- `public enum StatusToken { static func generate() throws -> Data; static func hash(_ token: Data) -> Data }`
- `APIClient.submitCredentialKey(..., statusTokenHash: Data? = nil, ...)`, `APIClient.renewCredential(..., statusTokenHash: Data? = nil, ...)`, `APIClient.cardStatus(cardID: String, token: Data) async throws -> String`.

- [ ] Test gagal: penyimpanan token memakai `afterFirstUnlockThisDeviceOnly`; body provisioning/perpanjangan memuat `status_token_hash` = SHA-256 token; `cardStatus` mengirim `Authorization: Bearer <base64url>` dan memetakan 404 ke `ProblemDetails`; provisioning lab menyimpan token di bawah id instance server; perpanjangan tanpa token membuat dan menyimpan token baru; hapus kartu menghapus token.
- [ ] Implementasi; suite host dan simulator; commit.

### Task 5: App — penyegar status, e2e lab, QA

**Files:** Create `Packages/Sources/ANFeatures/CardStatusRefresher.swift`, tests; Modify `Packages/Sources/ANFeatures/KeysView.swift`, `AppServices.swift`, `docs/QA_SUITE.md`, `docs/SDD.md`, README.

**Interfaces — Consumes:** Task 4. **Produces:** `CardStatusRefresher.refresh(now: Date) async -> Bool` (true bila ada kartu berubah), interval minimum 60 dtk.

- [ ] Test gagal: `statusServerMenangguhkanKartu`, `statusServerMemulihkanKartu`, `statusServerMencabutKartu`, `statusServerTidakMenimpaPerluDipindahkan`, `offlineMempertahankanStatus`, `refreshDibatasiSekaliPerMenit`, `kartuTanpaTokenDilewati`.
- [ ] Implementasi; panggil saat app masuk foreground dan pemuatan pertama layar Kunci, lalu muat ulang daftar bila berubah.
- [ ] Suite host dan simulator; e2e lab: provisioning → `suspend` → buka ulang app → Ditangguhkan dan presentasi diblokir → `resume` → Aktif → `revoke` → Dicabut; denylist terisi; token tidak di log/DB.
- [ ] QA TC-MGT-12 baru (FR-38, FR-51) + traceability §14; SDD §8.1/§8.4.3/§8.5; commit.
