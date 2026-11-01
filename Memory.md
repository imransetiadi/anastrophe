# Memory — catatan perubahan Anastrophe

Log kronologis setiap perubahan di repo ini, entri terbaru di atas. Catatan per sesi, keputusan, dan pelajaran yang saling bertaut ada di vault Obsidian [`docs/agentmemory/`](docs/agentmemory/MOC.md).

**Aturan pencatatan**

- Setiap perubahan (commit, keputusan JEV/ADR, perbaikan hasil review) menambah satu entri di atas, dalam commit yang sama dengan perubahannya. Judul: `## AREA-YYYY-MM-DD-HHMM - Judul (Status)`.
- Isi entri: apa yang berubah dan mengapa, rujukan (FR/NFR/ADR/TC), hasil uji yang benar-benar dijalankan, dan catatan sesi Obsidian terkait. Catatan sesi dan [MOC](docs/agentmemory/MOC.md) diperbarui di commit yang sama.
- **Jangan** menulis secret, kunci, token, kontak pengguna, atau identitas kartu fisik (CLAUDE.md aturan 6 dan 9).
- Sumber kebenaran tetap `docs/` dan riwayat git; berkas ini ringkasannya.

## Status terkini

- Branch kerja: `feat/r1-scaffold`, satu-satunya branch lokal; belum di-merge dan belum di-push.
- Suite terakhir: Swift host 235 test (1 dilewati, tanpa gagal) dan simulator 233 test (1 dilewati). Backend Go 7 paket lulus pada iterasi hapus kartu; belum ada perubahan backend sejak itu.
- Menunggu keputusan pengguna:
  - ADR-0017 (entitas hukum untuk entitlement) dan ADR-0022 (bentuk reader uji BLE).
  - Tinjauan 5 gate JEV yang tereskalasi: lab, perpanjangan, audit, hapus kartu, riwayat tap (`docs/adr/jev-log/*-gate.json`).
  - Integrasi branch: merge ke `main` atau push + PR.
  - `DEVELOPMENT_TEAM` di `Config/Local.xcconfig`, serta iPhone dan reader untuk uji bertipe H.

### Ringkasan kemampuan

| Area | Isi | Rujukan |
|---|---|---|
| App iOS R1 | ANP/1, kanal N-HCE dan B, penyimpanan SwiftData/Keychain, UI Daftar Kunci, detail, dan lembar presentasi | ADR-0002, ADR-0003, ADR-0009 |
| BLE | Pindai paralel saat lembar dibuka, dengan early exit | ADR-0019 |
| Backend | Go + PostgreSQL: enrolment, provisioning, idempotensi, problem RFC 9457 | ADR-0020, ADR-0021 |
| Perpanjangan | Sertifikat diperpanjang memakai autentikasi tap; kill switch hanya di `:renew` | ADR-0023 |
| Audit | Rantai hash per gedung, append-only, pseudonim sejak ditulis, perintah `anastrophe-audit` | ADR-0024, ADR-0025 |
| Hapus kartu | Bukti kepemilikan, kartu ditangguhkan, kartu tanpa kunci | ADR-0026, ADR-0027, ADR-0028, FR-31 |
| Riwayat tap | Log lokal 30 hari: lima terbaru di detail, "Lihat semua" ke riwayat penuh, store pulih sendiri bila rusak | FR-30, ADR-0029, ADR-0030 |

## IOS-2026-11-01-1820 - Perbaikan review riwayat tap: store pulih sendiri dan "Lihat semua" (Selesai, commit lokal; gate tereskalasi)

Review akhir oleh subagent baru atas `de10af4..284762c` tidak menemukan Critical, tetapi menemukan dua Important. I1: store riwayat yang gagal dibuka membuat seluruh app masuk mode "penyimpanan tidak tersedia". I2: detail hanya menampilkan 20 baris di bawah judul "30 hari". JEV memutuskan ADR-0029 `reset_on_corruption_only` (0,87) dan ADR-0030 `inline_recent_plus_all` (0,95).

`SwiftDataTapHistoryStore.openRecovering(directory:)` tidak pernah gagal. Store dibuat ulang sekali hanya bila berkasnya rusak (galat Cocoa 259) atau skemanya tidak cocok dengan model, yang dibaca dari metadata Core Data. Galat lain memakai riwayat sementara di memori tanpa menghapus berkas. `AppServices.live()` memakai fungsi ini. Detail menampilkan lima tap terbaru dan baris "Lihat semua" (dengan jumlah entri) ke layar riwayat 30 hari penuh. String baru ID/EN `detail.history.see_all`; demo mengisi delapan entri.

Bukti:
- RED kompilasi lalu GREEN untuk `TapHistoryRecoveryTests` (4), `TapHistoryPreviewTests` (2), dan test penjaga `riwayatLebihDariDuaPuluhTetapDimuatSemua`.
- Mutasi `isUnusable` (false dan true) serta batas 20 tertangkap.
- Host 235 test (1 dilewati, tanpa gagal); simulator 233 (`TEST SUCCEEDED`).
- Screenshot mode terang, mode gelap (build sementara batas 2), dan AX5.
- `check_docs.py` 0 masalah.

Dokumen: SDD 2.7 (§5.3). QA TC-MGT-01 diperbarui dan dipindah ke atas TC-MGT-02. Status SDD kini menyebut ADR-0017 dan ADR-0022 sebagai yang menunggu.

`jev_gate` dua run tereskalasi (composite 0,662 lalu 0,6885). Pada run kedua, empat klaim *unsupported* karena log uji hanya dikirim di kolom `tests`. Gate ini masuk daftar tinjauan di README. Minor tertunda M1–M8 dan badge status "Ac-tive" pada AX5 dicatat di ledger.

Obsidian: `sessions/2026-11-01-perbaikan-riwayat-tap.md`, `decisions/ADR-0029-pemulihan-store-riwayat-tap.md`, `decisions/ADR-0030-tampilan-riwayat-tap.md`, `lessons/swiftdata-galat-tersembunyi.md`, `lessons/jev-gate-butir-evidence.md`, dan MOC. Tidak push, tidak merge.

## DOC-2026-11-01-1805 - Memory.md dan vault Obsidian docs/agentmemory (Selesai)

Permintaan pengguna: berkas `Memory.md` untuk menyimpan setiap perubahan, lalu integrasi dengan Obsidian. `Memory.md` di root menjadi log kronologis dengan format entri yang sama seperti proyek lain milik pengguna. Riwayat sebelumnya diisi dari git (tabel di bawah).

Vault Obsidian `docs/agentmemory/` berisi `MOC.md`, `sessions/`, `decisions/`, dan `lessons/`:
- `.obsidian/app.json` di-commit agar tautan baru tetap Markdown relatif, sehingga terbaca di GitHub dan diperiksa `check_docs.py`.
- `workspace*.json`, `cache`, dan `.trash/` di-ignore, begitu pula `/.obsidian/` bila root repo dibuka sebagai vault.
- Vault didaftarkan ke daftar vault Obsidian lokal.

Obsidian: `sessions/2026-11-01-memory-dan-obsidian.md`.

## IOS-2026-11-01-1449 - Riwayat tap lokal 30 hari (FR-30), commit 284762c (Selesai; review: 2 Important)

Store SwiftData terpisah (`taps.store`, proteksi `.complete`, tidak ikut backup). `RecordingLauncher` hanya mencatat hasil diizinkan atau ditolak, tanpa nama reader, lokasi, atau identitas kartu. Riwayat dipangkas setelah 30 hari, dihapus bersama kartu, dan tampil di detail kartu. Suite saat itu: host 228 test (227 lulus, 1 dilewati), simulator 226 (225 lulus, 1 dilewati). Review akhir: tanpa Critical, dua Important (I1, I2), delapan minor. Obsidian: `sessions/2026-11-01-riwayat-tap.md`.

## Riwayat commit sebelum Memory.md

Terbaru di atas; semua di `feat/r1-scaffold`, 2026-11-01.

| Commit | Ringkasan |
|---|---|
| `284762c` | feat(app): riwayat tap lokal 30 hari di detail kartu (FR-30) |
| `de10af4` | docs(jev): gate penutupan rencana hapus kartu (eskalasi) dan daftar gate di README |
| `255656f` | fix(delete): perbaikan review akhir hapus kartu (C1, I1–I4, M2, M5; ADR-0027/0028) |
| `eb2cd45` | docs(adr): ADR-0027 hapus kartu ditangguhkan (0,94) dan ADR-0028 hapus kartu tanpa kunci (1,0) |
| `475ef29` | feat(backend): perintah operator anastrophe-audit untuk verifikasi rantai audit |
| `47e7a7b` | feat(app): hapus kartu — Detail → Pengaturan → Hapus dengan konfirmasi + autentikasi (FR-31) |
| `a56705a` | feat(backend): DELETE /v1/cards/{id} dengan bukti kepemilikan kunci (FR-31, ADR-0026) |
| `f81d27a` | docs: ADR-0026 hapus kartu dengan bukti kepemilikan (JEV 0,98), spesifikasi dan rencana FR-31 |
| `115b0db` | feat(app): peringatan "Perlu terhubung ke internet" untuk kartu yang perlu diperbarui (TC-DEV-10) |
| `127afa7` | fix(renewal): pekerjaan perpanjangan terikat ke tap tertentu (minor review M3) |
| `39087f4` | test(l10n): penjaga katalog string ID/EN dan kunci localized() yang dipakai kode |
| `b2ed49c` | fix(audit): waktu event tidak mundur sepanjang seq (minor review audit 3) |
| `38dcf56` | docs(readme): daftar gate penutupan yang menunggu tinjauan |
| `3e1ed60` | docs(jev): gate penutupan rencana audit (eskalasi, semua klaim verified) |
| `a06ba99` | fix(audit): perbaikan review akhir audit (C1, I1, I2, I3) + ADR-0025 |
| `a77d7c2` | fix(renewal): minor review perpanjangan (M1, M4–M9) |
| `1d93435` | docs(jev): gate penutupan rencana perpanjangan (eskalasi, semua klaim verified) |
| `a5c2cd4` | fix(renewal): perbaikan review akhir perpanjangan (C1 teks, I1, I2, I3) |
| `f9e6cff` | feat(backend): catat audit enrolment, provisioning, dan perpanjangan dalam transaksi yang sama |
| `433704a` | feat(backend): log audit append-only berantai hash per gedung (FR-54, ADR-0024) |
| `25b37c6` | docs(plan): spesifikasi dan rencana audit log berantai hash per gedung (FR-54, ADR-0024) |
| `6c8c498` | docs(adr): ADR-0024 rantai hash audit per gedung (JEV per_site_chain 0,95) |
| `51dfc4b` | docs(glossary): istilah perpanjangan (ADR-0023), reader uji (ADR-0022), dan lab |
| `7f59abb` | fix(app): kartu kedaluwarsa yang bisa diperpanjang tetap bisa di-tap; status "Perlu diperbarui" |
| `61717f6` | fix(lab): minor review lab (M3-nit, M4c, M5, M6, M7) |
| `2c9f986` | fix(ui): separator detail kartu rata dan tombol utama nonaktif terlihat redup |
| `7d66e39` | docs(jev): gate lab run 3 dengan bukti e2e pasca-perbaikan (tetap eskalasi) |
| `00df0d3` | feat(lab): perpanjangan lab (-ANLabRenew, tombol detail) + dokumen ADR-0023, terverifikasi e2e |
| `5577855` | feat(app): perpanjangan sertifikat di alur tap (hook prepare + RenewalScheduler, ADR-0023) |
| `965f922` | feat(app): CredentialRenewer — perpanjangan sertifikat dengan bukti kepemilikan kunci (FR-45) |
| `f663eaf` | feat(app): kontrak perpanjangan sertifikat (RenewalPolicy, not_before, renewalURL, API challenge/renew) |
| `b4f3505` | docs(jev): catat jev_gate penutupan rencana lab (eskalasi, semua klaim verified) |
| `6de92c2` | fix(lab): perbaikan review akhir lab (I1, M1–M4): slot server, moveKey, pemulihan devseed |
| `8716785` | docs(adr): ADR-0022 reader uji BLE (eskalasi) dan ADR-0023 perpanjangan via autentikasi tap |
| `ff2b184` | feat(backend): perpanjangan sertifikat FR-45 (challenge + renew, ADR-0023) |
| `6b4b8be` | feat(lab): pemicu DEBUG -ANLabBackend + form "Backend dev", terverifikasi end-to-end |
| `f71b5f5` | feat(lab): provisioning lab lewat backend dev (moveKey + provisionViaBackend) |
| `20ce1db` | feat(backend): perintah dev anastrophe-devseed untuk lab end-to-end |
| `a8d32fd` | fix(backend): idempotency enrolment tracer, test DB tak lagi dilewati diam-diam (minor 5, 11, 12) |
| `353a655` | fix(backend): migrasi aman antar-replika, zona fail-closed, kebijakan gedung (minor 2, 6, 7) |
| `eb9f747` | docs(adr): ADR-0021 CBOR/COSE minimal (amandemen ADR-0020) |
| `79cc24f` | fix(backend): decoder CBOR & verifier COSE ketat (minor review 3) |
| `260907d` | fix(backend): pengerasan lapisan HTTP (minor review 1, 8, 9, 10, 13) |
| `094a812` | fix(backend): idempotency satu transaksi, cek status kartu, test race deterministik |
| `c9f1ea7` | feat(networking): APIClient.createEnrollment untuk endpoint tracer backend |
| `460fbf1` | feat(backend): provisioning kredensial POST /v1/enrollments/{id}/credentials |
| `a02de72` | feat(backend): skema PostgreSQL R1 dan invarian 8 kartu per perangkat |
| `5154b30` | feat(backend): penerbitan CredentialCert COSE_Sign1 ES256 (SDD §7.3) |
| `d57aab2` | test(backend): kesesuaian test vector ANP/1 v1 di Go (TC-PROTO-01) |
| `bd9d4ba` | feat(backend): pondasi API Go, RFC 9457, dan GET /v1/config |
| `065d097` | docs(adr): ADR-0020 backend Go (provisional) dan topologi diterima di SDD §12 |
| `507fca8` | feat(ble): pindai paralel dengan autentikasi (ADR-0019) |
| `0130f47` | feat(ios): R1 tracer bullet — ANP/1, kanal N-HCE & B, penyimpanan, UI |
| `400719d` | docs: dokumen produk Anastrophe, ADR, design system, dan aturan proyek |
