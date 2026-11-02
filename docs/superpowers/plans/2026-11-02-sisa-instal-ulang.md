# Sisa Keychain Instal Ulang — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Peluncuran pertama sesudah instal ulang menghapus semua item Keychain sisa instalasi lama sebelum layanan dipakai, tanpa pernah menyentuh kunci kartu yang masih ada.

**Architecture:** `SecretStore.deleteAll()`, lalu `KeychainDeviceIdentityStore.purgeLeftoversIfFreshInstall(hasCards:)`, lalu `AppServices.prepareInstall()`, yang dipanggil `AppEnvironment.makeServices()` sesudah `live()`.

**Tech Stack:** Swift 6, Swift Testing, Security (Keychain), SwiftData.

**Spec:** `docs/superpowers/specs/2026-11-02-sisa-instal-ulang-design.md` (ADR-0053).

## Global Constraints

- **Ruang lingkup penghapusan:** hanya item service app, dengan query kelas + service tanpa account.
- **Kartu yang masih ada:** tidak pernah kehilangan kunci. Store yang gagal dibaca dianggap berisi kartu.
- **Penanda:** dibuat hanya sesudah penghapusan berhasil, dan dikecualikan dari backup.
- **Commit:** pesan berbahasa Indonesia dan diakhiri `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Tanpa push.
- **Verifikasi:**
  - host: `swift test --package-path Packages`;
  - simulator: `cd Packages && xcodebuild -scheme AnastropheKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`;
  - build app: Debug;
  - dokumen: `check_docs` exit 0 (exit code, bukan keluaran yang di-pipe).

## Review Focus

1. **Kartu ada atau store gagal dibaca → tidak ada yang dihapus.** Test: `kartuAdaTidakDibersihkan`, `storeKartuGagalTidakDibersihkan`, `kartuMasihAdaTidakDibersihkan`.
2. **Penanda tidak dibuat bila penghapusan gagal.** Test: `gagalHapusTidakMembuatPenanda`.
3. **Pembersihan sebelum UI.** Bukti: `makeServices()` memanggil `prepareInstall()` sebelum `return` (ulasan kode, build app).
4. **Query hanya service app.** Test: `hapusSemuaHanyaServiceIni`.
5. **TC-ENR-23 tetap lulus.** Test: `instalasiBaruMembuatIDBaru`, `instalUlangMembersihkanSisaKeychain` (id baru stabil).

---

### Task 1: Penghapusan Keychain dan pembersihan instal ulang (ANStorage)

**Files:**
- Modify: `Packages/Sources/ANStorage/SecretStore.swift`, `Packages/Sources/ANStorage/DeviceIdentityStore.swift`, `Packages/Tests/ANStorageTests/KeychainSecretStoreTests.swift`, `Packages/Tests/ANStorageTests/DeviceIdentityStoreTests.swift`, `Packages/Tests/ANStorageTests/CardStoreTests.swift`, `Packages/Tests/ANStorageTests/CredentialKeyStoreTests.swift`

**Interfaces:**
- Produces:
  - `SecretStore.deleteAll() throws`, sebagai requirement protokol;
  - `KeychainDeviceIdentityStore.purgeLeftoversIfFreshInstall(hasCards: Bool) throws -> Bool`;
  - `DeviceIdentityStore.purgeLeftoversIfFreshInstall(hasCards:)`, sebagai requirement protokol dengan bawaan `false` di extension.

- [ ] **Step 1: Tulis test yang gagal:**
  - `hapusSemuaHanyaServiceIni`: dua `KeychainSecretStore` (service "a" dan "b") di satu `FakeKeychain`; `deleteAll()` pada "a" menghapus semua item "a", dan item "b" utuh.
  - `hapusSemuaKosongTidakGagal`: tidak throw.
  - `hapusSemuaGagalDilaporkan`: `failDeletes` → throw.
  - `instalUlangMembersihkanSisaKeychain`: item `cred.key.aa`, `cred.record.aa`, `status-token.x`, dan device id; penanda tidak ada; `hasCards: false` → true; `storedKeyCount == 0`; penanda ada dan dikecualikan dari backup; `deviceID()` id baru dan stabil; panggilan kedua → false.
  - `kartuMasihAdaTidakDibersihkan`: `hasCards: true` → false; item utuh; penanda tidak ada.
  - `penandaAdaTidakDibersihkan`: false; item utuh.
  - `gagalHapusTidakMembuatPenanda`: store dengan `deleteAll` yang throw → throw; penanda tidak ada.
- [ ] **Step 2: Jalankan** `swift test --package-path Packages --filter 'KeychainSecretStore|DeviceIdentity'`. Expected: FAIL (build).
- [ ] **Step 3: Implementasikan.**
  - `FakeKeychain` dikunci per service+account, dan query tanpa account menghapus semua item service itu.
  - Test double `FailingSecretStore` dan `DeleteFailingSecretStore` ikut mengimplementasikan `deleteAll`.
- [ ] **Step 4: Jalankan.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(storage): bersihkan sisa Keychain saat instal ulang (FR-43, ADR-0053)`.

### Task 2: `AppServices.prepareInstall` dan pemanggilan saat start

**Files:**
- Modify: `Packages/Sources/ANFeatures/AppServices.swift` (`prepareInstall()`, `SimulatorSecretStore.deleteAll`), `App/AppEnvironment.swift`
- Create: `Packages/Tests/ANFeaturesTests/InstallCleanupTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces: `AppServices.prepareInstall() async`.

- [ ] **Step 1: Tulis test yang gagal** (layanan dengan `InMemorySecretStore` yang sama untuk kunci dan identitas, penanda di direktori sementara):
  - `instalUlangMembersihkanSisa`: store kartu kosong → sesudah `prepareInstall()`, `storedKeyCount == 0` dan penanda ada.
  - `kartuAdaTidakDibersihkan`: satu kartu di store → item utuh.
  - `storeKartuGagalTidakDibersihkan`: store yang `all()`-nya throw → item utuh.
- [ ] **Step 2: Jalankan.** Expected: FAIL.
- [ ] **Step 3: Implementasikan** `prepareInstall()` dan panggil di `makeServices()` sesudah `live()` berhasil, sebelum `return`.
- [ ] **Step 4: Jalankan host dan simulator, lalu build app Debug.** Expected: PASS / BUILD SUCCEEDED.
- [ ] **Step 5: Commit** `feat(app): pembersihan instal ulang sebelum layanan dipakai (FR-43, ADR-0053)`.

### Task 3: Dokumen

**Files:**
- Modify:
  - `docs/SDD.md`: §5.3, catatan instal ulang di bawah "Deteksi restore", dan revisi;
  - `docs/QA_SUITE.md`: TC-DEV-13 di katalog, hasil di §11.1, dan §14 FR-43;
  - `docs/agentmemory/backlog.md`: "Sisa instal ulang" dipindah ke "Sudah selesai".

- [ ] **Step 1: Perbarui dokumen**, lalu jalankan `check_docs` (exit 0).
- [ ] **Step 2: Commit** `docs: pembersihan sisa Keychain saat instal ulang (SDD §5.3, QA TC-DEV-13)`.
