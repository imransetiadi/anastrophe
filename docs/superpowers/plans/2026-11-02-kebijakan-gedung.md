# Kebijakan Gedung (FR-55 sebagian) — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Operator mengatur masa berlaku sertifikat dan kanal per gedung lewat CLI; server menegakkan kanal gedung saat provisioning; app memilih kanal yang diizinkan gedung.

**Architecture:**
- **Store:** `sites.policy` dibaca dan diperbarui sebagian lewat store. Kanal efektif gedung = `policy.channels` ∩ kanal global.
- **HTTP:** lookup dan enrolment membawa `channels`, dan provisioning menolak kanal terlarang sesudah rahasia valid.
- **App:** `CardProvisioner` memakai kanal gedung sebelum dan sesudah enrolment.

**Tech Stack:** Go 1.27 + PostgreSQL 16 (pgx v5, testpg); Swift 6, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-02-kebijakan-gedung-design.md` (ADR-0049).

## Global Constraints

- **Kanal yang dikenal:** `ble` dan `nfcHCE` saja. `semua` menghapus `policy.channels`.
- **Masa berlaku:** 1–30 hari (ADR-0010). Pembaruan hanya menyentuh kunci yang diberikan; zona dan kunci lain dipertahankan.
- **Urutan pemeriksaan provisioning:** rahasia (404 `ENR-NOT-FOUND`) → status → kanal gedung (400 `ENR-INVALID-CHANNEL`).
- **Kompatibilitas:** respons tanpa `channels` = semua kanal global.
- **String:** semua teks app dalam ID dan EN.
- **Commit:** pesan berbahasa Indonesia dan diakhiri `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Hanya di `feat/r1-scaffold`, tanpa push.
- **Verifikasi:**
  - Go: `env ANASTROPHE_REQUIRE_PG=1 go -C backend test ./...`;
  - Swift host: `swift test --package-path Packages`;
  - simulator: `cd Packages && xcodebuild -scheme AnastropheKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`;
  - dokumen: `check_docs` exit 0.

## Review Focus

1. **Zona dan kunci lain tetap** setelah pembaruan sebagian. Test: Task 1 `TestPerbaruiKebijakanSebagian`.
2. **Kebijakan tidak bocor sebelum rahasia.** Test: Task 2 `TestKanalGedungDitolakSesudahRahasia`.
3. **Tanpa slot terbuang di jalur kartu.** Test: Task 4 `kanalGedungDiperiksaSebelumEnrolment`.
4. **Kompatibilitas tanpa `channels`.** Test: Task 2 `TestKanalEfektifTanpaKebijakan`, Task 4 `serverLamaTanpaKanalGedung`.
5. **Masa berlaku dari CLI dipakai.** Test: Task 2 `TestMasaBerlakuDariKebijakanGedung` (sudah ada) + Task 3 `TestPolicyMengubahMasaBerlaku`.

---

### Task 1: Store kebijakan gedung

**Files:**
- Create: `backend/internal/store/sitepolicy.go`, `backend/internal/store/sitepolicy_test.go`
- Modify: `backend/internal/store/store.go`, `backend/internal/store/sitecode.go`, `backend/internal/store/registry.go`, `backend/internal/store/invitation.go` (`Enrollment.Channels`, `SiteRef.Channels`, `CardEnrollment.Channels`)

**Interfaces:**
- Produces:
  - `type SitePolicy struct { CertValidityDays int; Channels []string; ZoneCount int }`;
  - `type PolicyUpdate struct { CertValidityDays *int; Channels *[]string }` (`&[]string{}` berarti semua);
  - `(*Store) SitePolicyOf(ctx, siteID) (SitePolicy, error)`;
  - `(*Store) UpdateSitePolicy(ctx, siteID, operator string, u PolicyUpdate, at time.Time) (SitePolicy, error)`;
  - galat `ErrInvalidPolicy`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `TestPerbaruiKebijakanSebagian`: zona dan kunci lain tetap; hanya kunci yang diberikan berubah; audit `site.policy_updated` dengan data nilai baru.
  - `TestKebijakanTidakValidDitolak`: 0, 31, kanal `wallet`/`x`, dan operator kosong; tanpa perubahan dan tanpa audit.
  - `TestKanalKebijakanTerbawaKeEnrolmentDanLookup`.
- [ ] **Step 2: Jalankan.** Expected: FAIL.
- [ ] **Step 3: Implementasikan** dengan `jsonb_set`/`policy - 'channels'` di satu transaksi `FOR UPDATE`, plus audit.
- [ ] **Step 4: Jalankan.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(store): kebijakan gedung — masa berlaku dan kanal per gedung (FR-55)`.

### Task 2: HTTP — kanal efektif dan penegakan provisioning

**Files:**
- Modify: `backend/internal/enroll/sites.go`, `backend/internal/enroll/credentials.go`
- Test: `backend/internal/enroll/policy_test.go`

**Interfaces:**
- Consumes: `SiteRef.Channels`, `CardEnrollment.Channels`, `Enrollment.Channels`.
- Produces: `func (h *Handler) effectiveChannels(policy []string) []string`, yang mengikuti urutan `h.EnabledChannels`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `TestLookupMembawaKanalGedung`;
  - `TestEnrolmentMembawaKanalGedung` (kartu + undangan);
  - `TestKanalEfektifTanpaKebijakan` (= kanal global);
  - `TestKanalGedungDitolakSesudahRahasia` (kanal terlarang + rahasia benar → 400 `ENR-INVALID-CHANNEL`; kanal terlarang tanpa rahasia → 404 `ENR-NOT-FOUND`).
- [ ] **Step 2: Jalankan.** Expected: FAIL.
- [ ] **Step 3: Implementasikan.** Pemeriksaan kanal gedung ada di `issue()` sesudah pemeriksaan rahasia dan status.
- [ ] **Step 4: Jalankan seluruh Go.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(enroll): kanal gedung di lookup/enrolment dan provisioning (FR-55, FR-05)`.

### Task 3: CLI `policy`

**Files:**
- Modify: `backend/cmd/anastrophe-registry/main.go`, `backend/cmd/anastrophe-registry/main_test.go`

- [ ] **Step 1: Tulis test yang gagal:**
  - `TestPolicyMembaca`;
  - `TestPolicyMengubahMasaBerlaku` (lalu enrolment + provisioning di store memakai masa berlaku baru);
  - `TestPolicyKanalDanSemua`;
  - `TestPolicyArgumenSalah` (0, 31, kanal tak dikenal, tanpa `--operator` saat mengubah → exit 2 tanpa perubahan).
- [ ] **Step 2: Jalankan.** Expected: FAIL.
- [ ] **Step 3: Implementasikan** subcommand dan usage.
- [ ] **Step 4: Jalankan.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(registry): CLI policy untuk kebijakan gedung (FR-55)`.

### Task 4: App — kanal gedung

**Files:**
- Modify:
  - `Packages/Sources/ANNetworking/APIClient.swift`: `SiteSummary.channels`, `EnrollmentStart.channels` (`Set<ChannelKind>?`).
  - `Packages/Sources/ANFeatures/CardProvisioner.swift`: `.automatic(availability, siteChannels:)` + pemilihan ulang sesudah enrolment.
  - `Packages/Sources/ANCore/ANError.swift`: `siteChannelUnavailable`.
  - `EnrollmentMessages`, `AddCardModel`, `Localizable.xcstrings`.
- Test: `CardProvisionerTests`, `SiteLookupTests`, `AddCardModelTests`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `kanalGedungDiperiksaSebelumEnrolment` (gedung hanya `nfcHCE`, perangkat tanpa HCE → `siteChannelUnavailable`, `paths == ["/v1/config"]`);
  - `kanalDipilihUlangSesudahEnrolment` (respons enrolment hanya `ble` → provisioning `ble`);
  - `tanpaKanalGedungSesudahEnrolmentTanpaProvisioning` (kunci dibuang, tanpa `/credentials`);
  - `serverLamaTanpaKanalGedung` (respons tanpa `channels` → perilaku lama);
  - `lookupMembawaKanalGedung`;
  - pesan baru di `EnrollmentMessagesTests`.
- [ ] **Step 2: Jalankan.** Expected: FAIL.
- [ ] **Step 3: Implementasikan.**
- [ ] **Step 4: Jalankan host dan simulator.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(app): memilih kanal yang diizinkan gedung (FR-55, FR-05)`.

### Task 5: Dokumen dan e2e

- [ ] **Step 1: Perbarui dokumen:** SDD (§8.1 `policy.channels`, §8.5 `channels`, §15, revisi), QA (hasil TC-ADM-13/14), README (`policy`).
- [ ] **Step 2: Jalankan e2e lab:**
  - `policy --channels nfcHCE` → Tambah Kartu di simulator menampilkan pesan, tanpa instance baru;
  - `policy --channels semua` → kartu aktif.
- [ ] **Step 3: Jalankan semua suite dan `check_docs`, lalu commit** `docs: kebijakan gedung (SDD, QA TC-ADM-13/14, README)`.
