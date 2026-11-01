# Perpanjangan Sertifikat (FR-45) — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kartu tetap aktif melewati masa berlaku sertifikat: backend memperpanjang sertifikat dengan bukti kepemilikan kunci, app memperpanjang setelah autentikasi tap tanpa prompt tambahan (ADR-0023).

**Architecture:** Backend menambah tabel nonce dan dua aksi pada `POST /v1/credentials/{cred}:challenge|:renew` di paket `enroll`, memakai ulang penerbitan `certs.Issue` dan helper idempotensi. App menambah `RenewalPolicy`, metode `APIClient`, `CredentialRenewer`, dan hook `prepare` di coordinator BLE/HCE yang dipakai `LivePresentationLauncher`.

**Tech Stack:** Go 1.24+ + PostgreSQL 16 (pgx), Swift 6 (Swift Testing), iOS Simulator.

**Spec:** [`docs/superpowers/specs/2026-11-01-perpanjangan-sertifikat-design.md`](../specs/2026-11-01-perpanjangan-sertifikat-design.md); ADR-0023; SDD §5.5, §8.4.2, §8.5, §15; QA TC-DEV-09/10/11.

## Global Constraints

- Pesan bukti kepemilikan = `"ANP1-RENEW"` ‖ `cred_id` (16 B) ‖ `nonce` (32 B); tanda tangan ECDSA P-256/SHA-256 raw r‖s 64 B.
- Nonce 32 B acak, berlaku 120 dtk, sekali pakai, terikat ke satu kredensial; ditandai terpakai hanya bila perpanjangan sukses.
- Kode error: `CRED-NOT-FOUND` 404, `CRED-NOT-RENEWABLE` 409, `CRED-CHALLENGE-INVALID` 400, `CRED-PROOF-INVALID` 400, `REQ-IDEMPOTENCY-KEY` 400 (RFC 9457, tanpa detail internal).
- Tidak pernah memperpanjang kredensial atau card instance yang tidak ACTIVE.
- Kunci kredensial tetap ADR-0009; tidak ada prompt kedua; tidak ada tanda tangan dari background.
- Batas tunggu perpanjangan wajib (sertifikat kedaluwarsa) = 5 dtk.
- Kode lab hanya di DEBUG. Tidak ada secret di repo. Setiap task: `go test ./...` + `go vet ./...` (backend) dan `swift test` (app) hijau.

## Review Focus

1. **Nonce dipakai ulang atau lintas kredensial.** Nonce kredensial A untuk renew kredensial B, atau nonce yang sudah terpakai → `CRED-CHALLENGE-INVALID`. Test: Task 1, `TestNonceKredensialLainDitolak`, `TestNonceSekaliPakai`.
2. **Kredensial ditangguhkan tetap diperpanjang.** Card instance SUSPENDED → 409 di kedua aksi. Test: Task 1, `TestKredensialDitangguhkanTidakDiperpanjang`.
3. **Respons server menimpa record yang salah.** Respons dengan `cred_id`/kanal berbeda → `ANError.invalidData`, record lama utuh. Test: Task 3, `responsCredIDBerbedaDitolak`.
4. **Record Keychain lama tidak terbaca setelah upgrade.** JSON record tanpa `notBefore`/`renewalURL` tetap ter-decode. Test: Task 2, `recordLamaTetapTerbaca`.
5. **Tap menggantung saat jaringan lambat.** Perpanjangan wajib yang melebihi 5 dtk dibatalkan dan tap tetap selesai (gagal tertutup). Test: Task 4, `perpanjanganWajibDibatasiWaktu`.

---

### Task 1: Backend — challenge & renew

**Files:** Create `backend/internal/store/migrations/0004_renewal_challenges.sql`, `backend/internal/enroll/renew.go`, `backend/internal/enroll/renew_test.go`; Modify `backend/internal/store/store.go`, `backend/internal/enroll/credentials.go` (`not_before` di respons, helper respons bersama).

**Interfaces:**
- Produces: `POST /v1/credentials/{cred}:challenge` dan `:renew` (kontrak di spec); respons provisioning/renew memuat `not_before`.
- Store: `(*Store).CreateRenewalChallenge(ctx, credID, nonce []byte, expiresAt time.Time) error`; `(*Tx).CredentialForRenewal(ctx, credID []byte) (RenewableCredential, error)` (FOR UPDATE; memuat status kredensial & card instance, pubkey, channel, kebijakan gedung); `(*Tx).ConsumeRenewalChallenge(ctx, credID, nonce []byte, now time.Time) (bool, error)`; `(*Tx).UpdateCredentialCert(ctx, credentialRowID string, cert []byte, notAfter time.Time) error`.

- [ ] Test gagal (testpg, `ANASTROPHE_REQUIRE_PG=1`): `TestTantanganPerpanjanganMengembalikanNonce` (201, nonce 32 B, `expires_at` = now + 120 dtk), `TestPerpanjanganMenerbitkanSertifikatBaru` (200; `cred_id` sama; `not_after` baru > lama; `certs.Verify` dengan CA lulus; DB diperbarui), `TestNonceSekaliPakai`, `TestNonceKedaluwarsaDitolak` (jam maju 121 dtk), `TestNonceKredensialLainDitolak`, `TestTandaTanganSalahDitolak` (400 `CRED-PROOF-INVALID`; nonce yang sama lalu sukses dengan tanda tangan benar), `TestKredensialDitangguhkanTidakDiperpanjang` (challenge & renew → 409), `TestKredensialTakDikenal` (404), `TestPerpanjanganTanpaIdempotencyKeyDitolak`, `TestProvisioningMengembalikanNotBefore`.
- [ ] Implementasikan; `go test ./...` & `go vet ./...` → LULUS.

### Task 2: App — kontrak, record, kebijakan

**Files:** Modify `Packages/Sources/ANNetworking/ProvisionedCredential.swift`, `Packages/Sources/ANNetworking/APIClient.swift`, `Packages/Sources/ANStorage/CredentialRecordStore.swift`; Create `Packages/Sources/ANCore/RenewalPolicy.swift`; Tests di `ANNetworkingTests`, `ANStorageTests`, `ANCoreTests`.

**Interfaces:**
- `ProvisionedCredential.notBefore: Date?` (`not_before`, opsional).
- `CredentialRecord.notBefore: Date?`, `CredentialRecord.renewalURL: URL?` (decodeIfPresent).
- `RenewalPolicy.need(notBefore: Date?, notAfter: Date, now: Date) -> RenewalNeed` dengan `enum RenewalNeed { case none, soon, expired }`.
- `APIClient.renewalChallenge(credentialID: Data) async throws -> RenewalChallenge` (`nonce: Data`, `expiresAt: Date`); `APIClient.renewCredential(credentialID: Data, nonce: Data, signature: Data, idempotencyKey: UUID) async throws -> ProvisionedCredential`; `RenewalChallenge.message(credentialID:)` = pesan bukti kepemilikan.

- [ ] Test gagal: `kebutuhanPerpanjangan` (tabel: baru → none; lewat tengah → soon; tanpa notBefore & sisa < 3,5 hari → soon; lewat notAfter → expired), `recordLamaTetapTerbaca`, `notBeforeOpsionalDiDecode`, `challengeMemakaiHexCredID` (path `/v1/credentials/<hex>:challenge`), `renewMengirimNonceDanTandaTangan` (body base64, header Idempotency-Key), `pesanBuktiKepemilikan` (byte persis).
- [ ] Implementasikan; `swift test` → LULUS.

### Task 3: App — `CredentialRenewer` + lab

**Files:** Create `Packages/Sources/ANFeatures/CredentialRenewer.swift`, `Packages/Tests/ANFeaturesTests/CredentialRenewerTests.swift`; Modify `Packages/Sources/ANFeatures/Lab/LabProvisioning.swift` (simpan `renewalURL`, `notBefore`).

**Interfaces:** `CredentialRenewer(keys:records:cards:transport:)`; `func renew(card: Card, channel: ChannelKind, context: AuthorizedContext, now: Date) async throws -> Card`. Melempar `ANError.invalidData` bila respons tidak cocok, `ANError.keyUnavailable` bila record/`renewalURL` tidak ada.

- [ ] Test gagal: `perpanjanganMemperbaruiRecordDanKartu` (tanda tangan diverifikasi dengan kunci publik kredensial atas pesan persis), `gagalJaringanRecordUtuh`, `responsCredIDBerbedaDitolak`, `tanpaRenewalURLTidakMenghubungiServer`, `provisionViaBackendMenyimpanRenewalURL`.
- [ ] Implementasikan; `swift test` → LULUS.

### Task 4: App — integrasi tap (hook `prepare`)

**Files:** Modify `Packages/Sources/ANChannelBLE/BLETapCoordinator.swift`, `Packages/Sources/ANChannelNFC/HCEPresentmentCoordinator.swift`, `Packages/Sources/ANFeatures/AppServices.swift`; Create `Packages/Sources/ANFeatures/RenewalScheduler.swift`; Tests di `ANChannelBLETests`, `ANChannelNFCTests`, `ANFeaturesTests`.

**Interfaces:** parameter coordinator `prepare: @escaping @Sendable (AuthorizedContext) async -> Void = { _ in }`; `RenewalScheduler` (MainActor) dengan `beforePresentation(card:channel:context:) async` (expired → tunggu ≤ 5 dtk) dan `afterPresentation() async` (soon → perpanjang dengan konteks tersimpan, lalu lepas).

- [ ] Test gagal: `prepareDipanggilSetelahAutentikasiSebelumProvider` (BLE & HCE), `prepareTidakDipanggilBilaAutentikasiGagal`, `kedaluwarsaDiperpanjangSebelumPresentasi`, `perpanjanganWajibDibatasiWaktu` (renewer menggantung → kembali ≤ 5 dtk ManualClock), `hampirHabisDiperpanjangSetelahTap`, `masihLamaTidakMenghubungiServer`.
- [ ] Implementasikan; `swift test` + `xcodebuild test` simulator → LULUS.

### Task 5: Lab end-to-end + dokumen

**Files:** Modify `Packages/Sources/ANFeatures/CardDetailView.swift` (aksi DEBUG "Perpanjang sekarang (lab)"), `docs/SDD.md` (§5.5, §8.4.2, §8.5, §15), `docs/QA_SUITE.md` (TC-DEV-09, §11.1), `README.md`.

- [ ] Simulator: provisioning via backend dev (kebijakan gedung `cert_validity_days` = 1), aksi perpanjang → layar menampilkan masa berlaku baru; DB: `cert` berubah dan `not_after` maju untuk `cred_id` yang sama; nonce terpakai.
- [ ] Build Release: tidak ada simbol aksi lab (`nm -a`/`strings -a`, pembanding Debug).
- [ ] `check_docs.py` 0 masalah; `jev_verify` klaim baru.
