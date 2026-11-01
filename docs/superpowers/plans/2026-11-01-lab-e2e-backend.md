# Lab End-to-End App ↔ Backend — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App (build DEBUG) mendapat kartu langsung dari backend Go lokal — enrolment tracer + provisioning kredensial — sehingga alur lab tidak lagi bergantung pada `scripts/anp1/lab_ca.py`, dan alurnya terbukti end-to-end di simulator.

**Architecture:** Backend mendapat perintah dev `cmd/anastrophe-devseed` yang membuat organisasi, gedung (kebijakan zona), reader group, dan perangkat lalu mencetak ID-nya. App menambah `LabProvisioning.provisionViaBackend` yang membuat kunci, memanggil `APIClient.createEnrollment` + `submitCredentialKey`, memindahkan kunci ke `cred_id` dari server, lalu menyimpan record dan kartu. Argumen peluncuran DEBUG memicu alur ini otomatis agar bisa diverifikasi tanpa ketukan.

**Tech Stack:** Go (backend), Swift 6 (app), PostgreSQL 16 sementara, iOS Simulator.

**Spec:** SDD §5.3, §8.4.1, §8.5; rencana R1 tracer bullet (Task 9 provisioning lab) dan backend R1.

## Global Constraints

- Semua kode lab hanya ada di build DEBUG (app) atau perintah dev terpisah (backend); tidak ada di build Release / biner `anastrophe-api`.
- `cred_id` ditetapkan server; kunci perangkat dipindah ke `cred_id` itu tanpa pernah mengekspor kunci privat.
- Gagal di tengah tidak meninggalkan kunci, record, atau kartu yatim (FR-19).
- Tidak ada secret di repo; kunci reader group lab berasal dari `scripts/anp1/.lab/site.json` (di-ignore) atau dibuat saat seed.

## Review Focus

1. **Kunci yatim saat backend menolak.** 409/400/jaringan putus setelah kunci dibuat → kunci dihapus, tidak ada kartu. Test: Task 2, `provisionViaBackendGagalTidakMenyisakanKunci`.
2. **`cred_id` server ≠ id lokal.** Kunci harus bisa dipakai menandatangani setelah dipindah. Test: Task 2, `kunciDipindahKeCredIDServer`.
3. **Release bersih.** Argumen `-ANLabBackend` tidak ada efeknya di Release. Bukti: Task 3, `nm`/`strings` pada build Release.

---

### Task 1: `cmd/anastrophe-devseed`

**Files:** Create `backend/cmd/anastrophe-devseed/main.go`, `backend/internal/store/seed.go`, `backend/internal/store/seed_test.go`.

- [ ] Test gagal `TestSeedLab`: `SeedLab(ctx, SeedInput{SiteCode, SiteName, Zones, GroupID, GroupKey})` membuat org/site (policy `zones` + `zones_bitmap`), reader group, dan perangkat; mengembalikan `SeedOutput{SiteID, DeviceID}`; dipanggil dua kali dengan site code sama → error yang jelas (bukan duplikat diam-diam).
- [ ] Implementasikan; perintah mencetak JSON `{"site_id","device_id"}`. Jalankan `go test` → LULUS.

### Task 2: `LabProvisioning.provisionViaBackend` (app)

**Files:** Modify `Packages/Sources/ANStorage/CredentialKeyStore.swift` (`moveKey(from:to:)`), `Packages/Sources/ANFeatures/Lab/LabProvisioning.swift`; Test `Packages/Tests/ANFeaturesTests/LabProvisioningTests.swift`, `Packages/Tests/ANStorageTests/CredentialKeyStoreTests.swift`.

**Interfaces:** `CredentialKeyStore.moveKey(from: Data, to: Data) throws`; `LabProvisioning.provisionViaBackend(api: APIClient, deviceID: String, siteID: String, channel: ChannelKind, keys:, records:, cards:) async throws -> Card`.

- [ ] Test gagal: `kunciDipindahKeCredIDServer`, `provisionViaBackendMembuatKartuAktif` (transport palsu: 201 enrolment → 200 kredensial), `provisionViaBackendGagalTidakMenyisakanKunci` (409 ENR-LIMIT dan 400 ENR-INVALID-KEY).
- [ ] Implementasikan; `swift test` → LULUS.

### Task 3: Pemicu DEBUG + verifikasi end-to-end di simulator

**Files:** Modify `Packages/Sources/ANFeatures/AppServices.swift` / `KeysView.swift` (argumen `-ANLabBackend <url> -ANLabDevice <id> -ANLabSite <id>`), `Packages/Sources/ANFeatures/Lab/LabView.swift` (bagian "Backend dev").

- [ ] Jalankan backend lokal (PostgreSQL sementara + devseed + `anastrophe-api`), luncurkan app di simulator dengan argumen lab, ambil screenshot: kartu dari backend tampil aktif. Verifikasi di database: satu credential tersimpan untuk perangkat seed.
- [ ] Build Release: `nm`/`strings` tidak memuat `ANLabBackend`/`provisionViaBackend`.
