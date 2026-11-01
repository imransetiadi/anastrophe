# Registri Kartu Fisik dan Pencocokan Enrolment — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrolment hanya untuk kartu fisik yang terdaftar di registri gedung (HMAC per gedung), dengan alasan spesifik bila tidak didukung dan aturan perangkat tambahan ADR-0032.

**Architecture:** Paket Go `internal/registry` (identitas kanonik, kontak, MAC per gedung), migrasi `0007`, fungsi store untuk registri dan enrolment, handler `POST /v1/enrollments` yang menerima identitas kartu, CLI `anastrophe-registry`, dan klien app yang mengirim identitas kartu.

**Tech Stack:** Go 1.27 (`crypto/hkdf`, `crypto/hmac`), PostgreSQL 16 (pgx), Swift 6.

**Spec:** [`docs/superpowers/specs/2026-11-01-registri-kartu-design.md`](../specs/2026-11-01-registri-kartu-design.md); ADR-0031, ADR-0032; FR-11, FR-13, FR-52; SDD §8.1, §8.4.1, §15.

## Global Constraints

- Identitas kartu dan kontak mentah tidak pernah disimpan atau dicatat: database, log, galat, audit, keluaran CLI (CLAUDE.md aturan 6). Kartu fisik hanya bukti kepemilikan saat enrolment (aturan 1).
- Masukan MAC kartu: `"ANP1-CARD-v1"` ‖ u8(kode tech) ‖ u8(panjang) ‖ id. Kontak: `"ANP1-CONTACT-v1"` ‖ kontak ternormalisasi. Kunci dev: HKDF-SHA256(master 32 B, salt kosong, info `"ANP1-REGISTRY-v1"` ‖ UUID gedung huruf kecil) → 32 B; MAC = HMAC-SHA256.
- Tech: `iso14443a`=1 (4/7/10 B), `iso15693`=2 (8 B), `felica`=3 (8 B), `iso7816`=4 (1–32 B).
- Card instance "aktif" = `PENDING_APPROVAL`, `PROVISIONING`, `ACTIVE`, `SUSPENDED`.
- `ANASTROPHE_REQUIRE_PG=1 go test ./...`, `go vet ./...`, dan `swift test` hijau di setiap task.

## Review Focus

1. **Identitas mentah bocor.** Test: Task 2 `TestRegistriTanpaNilaiMentah` (isi tabel tidak memuat byte identitas), Task 4 `TestImportTanpaNilaiMentah` (keluaran CLI dan audit).
2. **Dua perangkat bersamaan.** Tepat satu `PROVISIONING`, satu `PENDING_APPROVAL`. Test: Task 2 `TestEnrolmentBersamaanSatuProvisioning`.
3. **Kartu dihapus dari registri.** Dijawab sama dengan kartu tak dikenal. Test: Task 2 `TestKartuRemovedSamaDenganTakDikenal`.
4. **Zona fail-closed.** Kartu dengan bitmap 0 → sertifikat bitmap 0. Test: Task 3 `TestZonaDariKartuTerdaftar`.
5. **Tabrakan antarteknologi.** Byte sama, tech berbeda → HMAC berbeda; panjang salah ditolak. Test: Task 1 `TestIdentitasPerTeknologi`.

---

### Task 1: Paket `internal/registry`

**Files:** Create `backend/internal/registry/registry.go`, `backend/internal/registry/registry_test.go`.

**Interfaces (Produces):**
- `type Tech uint8` (`TechISO14443A`…`TechISO7816`); `type CardIdentity struct { Tech Tech; ID []byte }`; `ParseCardIdentity(tech, idHex string) (CardIdentity, error)`; `(CardIdentity).MACInput() []byte`.
- `NormalizeContact(raw string) (string, error)`; `ContactMACInput(normalized string) []byte`.
- `type MAC interface { MAC(ctx context.Context, siteID string, msg []byte) ([]byte, error) }`; `NewDevMAC(masterHex string) (*DevMAC, error)`.

- [ ] Test gagal: `TestIdentitasPerTeknologi` (panjang valid/invalid per tech; tech tak dikenal; hex rusak), `TestMACInputKanonik` (byte persis), `TestNormalisasiKontak` (email huruf kecil + trim; telepon `+62 812-3456-7890` → `+6281234567890`; tanpa `+`, < 8 atau > 15 digit ditolak), `TestDevMACVektor` (vektor dipatok, dihitung independen dengan Python `hmac`/HKDF), `TestDevMACPerGedung` (gedung berbeda → MAC berbeda).
- [ ] Implementasikan dengan `crypto/hkdf` dan `crypto/hmac` (tanpa dependensi baru).

### Task 2: Migrasi dan store

**Files:** Create `backend/internal/store/migrations/0007_physical_cards.sql`, `backend/internal/store/registry.go`, `backend/internal/store/registry_test.go`.

**Interfaces (Produces):**
- `type PhysicalCard struct { SiteID string; CardHMAC, ContactHMAC []byte; ZonesBitmap uint64 }`; `(*Store).UpsertPhysicalCards(ctx, siteID string, cards []PhysicalCard, at time.Time) (added, updated int, err error)` (satu transaksi, audit `registry.imported`).
- `(*Tx).StartCardEnrollment(ctx, deviceID, siteID string, cardHMAC []byte, at time.Time) (id, status string, err error)`; galat `ErrSiteUnsupported`, `ErrNotRegistered`, `ErrDuplicateEnrollment` (plus `ErrNotFound`, `ErrCardLimit` yang sudah ada).
- `(*Store).DecideEnrollment(ctx, cardInstanceID string, approve bool, operator string, at time.Time) error`.
- `Enrollment.ZonesBitmap` diambil dari kartu terdaftar bila tertaut.

- [ ] Test gagal: `TestEnrolmentKartuTerdaftar`, `TestKartuTakDikenalDitolak`, `TestKartuRemovedSamaDenganTakDikenal`, `TestGedungTanpaRegistri`, `TestPerangkatKeduaMenungguPersetujuan`, `TestPerangkatSamaDuplikat`, `TestEnrolmentBersamaanSatuProvisioning` (10 goroutine, 2 perangkat), `TestPersetujuanOperator` (approve → PROVISIONING, reject → REJECTED, status lain ditolak; audit), `TestImportUlangIdempoten`, `TestRegistriTanpaNilaiMentah`, `TestZonaEnrolmentDariKartu`.
- [ ] Implementasikan; perbarui SDD §8.1.

### Task 3: HTTP enrolment dan provisioning

**Files:** Modify `backend/internal/enroll/credentials.go`, `backend/cmd/anastrophe-api/main.go`; Test `backend/internal/enroll/registry_http_test.go`.

**Interfaces:** consumes Task 1–2. `Handler.Registry registry.MAC` (wajib). Permintaan `{device_id, site_id, card: {tech, id}}`; respons 201 `{enrollment_id, status}`.

- [ ] Test gagal: kode 400 `REQ-INVALID` (tanpa kartu, tech/panjang salah), 404 `ENR-NOT-REGISTERED`, 404 `ENR-SITE-UNSUPPORTED`, 409 `ENR-DUPLICATE`, 201 `PROVISIONING`/`PENDING_APPROVAL`; provisioning untuk `PENDING_APPROVAL` → 409 `ENR-PENDING-APPROVAL`; `TestZonaDariKartuTerdaftar`; respons galat tidak memuat id kartu; `anastrophe-api` menolak start tanpa `ANASTROPHE_DEV_REGISTRY_KEY`.
- [ ] Implementasikan; perbarui SDD §8.5 dan §15 (`ENR-DUPLICATE`).

### Task 4: CLI `anastrophe-registry` dan devseed

**Files:** Create `backend/cmd/anastrophe-registry/main.go`, `main_test.go`; Modify `backend/cmd/anastrophe-devseed/main.go`.

- [ ] Test gagal: `import` CSV (`tech,card_id,holder_contact,zones`) → laporan ditambah/diperbarui/ditolak dengan nomor baris; zona tak dikenal ditolak; `TestImportTanpaNilaiMentah` (stdout, stderr, audit); `approve`/`reject` dengan `--operator`; devseed mendaftarkan kartu lab (`-lab-card iso14443a:<hex>`).
- [ ] Implementasikan; QA (FR-11/FR-13/FR-52 → hasil).

### Task 5: Klien app

**Files:** Modify `Packages/Sources/ANNetworking/APIClient.swift`, `Packages/Sources/ANFeatures/Lab/LabBackendTarget.swift` (dan alur lab terkait), `Localizable.xcstrings`; Create `Packages/Sources/ANCore/CardIdentity.swift`; Test `APIClientTests`, `LabBackendLaunchTests`.

- [ ] Test gagal: body enrolment memuat `card` dengan tech dan hex huruf kecil; galat `ENR-NOT-REGISTERED`/`ENR-SITE-UNSUPPORTED`/`ENR-DUPLICATE` dipetakan ke teks ID/EN; status `PENDING_APPROVAL` → kartu "Menunggu persetujuan" tanpa provisioning; argumen `-ANLabCard`; protokol `CardIdentityReading` dengan mock.
- [ ] Implementasikan; suite host dan simulator; e2e lab simulator bila backend lokal tersedia.
