# QA Suite — Anastrophe

| Item | Nilai |
|---|---|
| Versi dokumen | 2.0 (Draft untuk review) |
| Tanggal | 2026-11-01 |
| Dokumen terkait | [PRD](PRD.md) · [SDD](SDD.md) · [ADR](adr/README.md) · [Research Evidence](research/RESEARCH_EVIDENCE.md) · [Glosarium](../GLOSSARY.md) · [Design system iOS](design-system/anastrophe/pages/ios-app.md) |
| Gerbang rilis | Bukti uji + `jev_gate` (JEV) atas klaim penyelesaian (§4, ADR-0018) |

### Riwayat versi

| Versi | Tanggal | Ringkasan perubahan |
|---|---|---|
| 1.0 | 2026-11-01 | Draft awal: satu jalur NFC in-app. |
| 2.0 | 2026-11-01 | Disusun ulang untuk tiga kanal (W/N/B) dan PRD v2.1/SDD v2.0. Ditambah: matriks perangkat iOS 26/27, matriks reader R1–R7, konformansi ANP/1 + test vector, reader/gateway, privasi, DR, upgrade, acceptance test Gherkin, pemetaan OWASP MASVS v2, kriteria keluar per milestone dengan gerbang `jev_gate`, dan traceability lengkap FR/NFR → TC. |

---

## 1. Tujuan & ruang lingkup

Memastikan Anastrophe memenuhi PRD v2.1 (FR/NFR) dan desain SDD v2.0 di tiga kanal:
- **N** (NFC in-app: N-SE `CredentialSession`, N-HCE `CardSession`), **B** (BLE), dan **W** (Apple Wallet Access, rilis R2);
- backend, portal admin, reader referensi, dan Edge Gateway.

**Sasaran kualitas:** keamanan (0 temuan kritis terbuka), keandalan tap (≥ 95% percobaan pertama), privasi (tidak ada identitas kartu mentah tersimpan), aksesibilitas (WCAG AA), dan kepatuhan Apple (App Review, program Apple).

## 2. Strategi uji (berbasis risiko)

Prioritas risiko tertinggi: (1) pemalsuan/replay/relay kredensial, (2) pembajakan enrolment, (3) kegagalan tap di reader nyata, (4) pelanggaran pedoman Apple yang memblokir rilis, (5) kebocoran data pribadi.

| Level | Cakupan | Alat | Lingkungan |
|---|---|---|---|
| Unit | Codec ANP/1 & framing BLE, state machine presentasi, kripto (HKDF/GCM), view model, validasi security code | Swift Testing / XCTest | CI (macOS; Simulator untuk logika non-NFC) |
| Integrasi app | `CredentialChannel` dengan mock `CardSession`/`CredentialSession`/Core Bluetooth/PassKit; API client dengan stub | Swift Testing + stub HTTP | CI |
| Kontrak API | OpenAPI, RFC 9457, idempotency, App Attest | Schemathesis | CI |
| Backend | Invarian DB (maks 8, satu PRIMARY), lockout, lifecycle, denylist, sengketa | Test container PostgreSQL | CI |
| **Konformansi protokol** | Test vector ANP/1 bersama (app ↔ firmware reader ↔ gateway) | Harness Python + vektor JSON | CI + lab |
| **HIL** | iPhone fisik ↔ reader nyata (NFC & BLE); enrolment kartu fisik | Rig servo + reader R1–R7 + skrip pyscard/BLE | Lab NFC |
| E2E | Alur pengguna lengkap per kanal | XCUITest + operator untuk tap | Lab + pilot |
| Keamanan | Replay, relay, skimming, MITM, brute-force, jailbreak, pentest | Proxmark3, mitmproxy, OWASP MASTG, REA (`open_bundle_resources`) | Lab keamanan |
| Privasi | Minimisasi data, hapus akun, Privacy Manifest | Kueri DB/log, review | Staging |
| Kinerja & beban | Latensi tap, cold start, beban API | Instruments, k6 | Lab + Load env |
| DR | Failover, RTO/RPO | Drill terjadwal | Staging/Load |
| Aksesibilitas & lokalisasi | VoiceOver, Dynamic Type, kontras, bahasa | Accessibility Inspector, checklist design system | Perangkat |
| Kepatuhan | App Review, NFC & SE, Apple Wallet Access Program | Checklist §13 | — |

**Catatan platform:** `CardSession` dan `CredentialSession` tidak berjalan di Simulator dan butuh reader fisik (O-A16), sehingga kasus bertipe **H** wajib di perangkat nyata. Uji HCE di luar EEA memerlukan iOS 18.2+ dan perangkat uji terdaftar, maksimal 100 (O-A13).

## 3. Lingkungan & matriks

### 3.1 Lingkungan

Dev · QA · Load · Staging · Production (O-W13). Untuk kanal W (R2), ditambah lingkungan QA Apple Access Platform dan uji E2E bersama Apple di properti (O-W18).

### 3.2 Matriks perangkat (iOS 26/27, ADR-0006)

| Perangkat | iOS | Peran |
|---|---|---|
| iPhone 11 | 26.x | Batas bawah kinerja (NFR-P01, NFR-P03) |
| iPhone SE (gen 2) | 26.x | Touch ID, layar kecil |
| iPhone SE (gen 3) | 27.x | Touch ID, iOS terbaru |
| iPhone 13 mini | 27.x | Layar kecil, posisi antena |
| iPhone 15 | 26.x | Perangkat utama N-1 |
| iPhone 17 Pro | 27.x | Perangkat utama |
| iPhone 18 Pro | 27.x terbaru | Terbaru |
| iPhone Duo | 27.x | Form factor baru: posisi antena & ergonomi (U10) |
| Apple Watch (berpasangan) | watchOS terbaru | Kanal W saja (R2) |

### 3.3 Matriks reader

| ID | Reader | Kanal | Tujuan |
|---|---|---|---|
| R1 | PC/SC (mis. ACR1252U) + skrip referensi ANP/1 (pyscard) | N | Lab, otomasi, injeksi kesalahan |
| R2 | **Reader referensi Anastrophe** (NFC + BLE + SE, OSDP ke panel uji) | N, B | Konfigurasi pilot (ADR-0016) |
| R3 | Reader OSDP Transparent Mode + **Edge Gateway** | N | Jalur retrofit (I-12) |
| R4 | Reader legacy UID/CSN & 125 kHz | — | Uji negatif (NG2) |
| R5 | Terminal pembayaran (Apple Pay) | — | Uji koeksistensi |
| R6 | Reader vendor Aliro + ECP v2.3 + TCI | W | Kanal W (R2) |
| R7 | Peripheral BLE uji (dev board) dengan firmware ANP/1 yang bisa diinjeksi kesalahan | B | Fuzzing & kasus tepi BLE |

### 3.4 Sampel kartu & wilayah

- **Kartu:** MIFARE Classic 1K, MIFARE DESFire EV2/EV3 (UID tetap dan *random ID*), MIFARE Ultralight, ISO 15693, FeliCa, prox 125 kHz (negatif), kartu tidak dikenal.
- **Akun & storefront:** SG, MY, HK, DE (EEA), ID, TH.

## 4. Kriteria masuk & keluar per milestone

| Milestone | Masuk | Keluar |
|---|---|---|
| M1 Prototype | Entitlement HCE development aktif; R1/R7 siap | TC-PROTO-01..05 lulus; TC-PRSN-01 dan TC-PRSB-01 lulus di lab |
| M2 MVP (R1) | Semua P0 R1 terimplementasi; build TestFlight; R2 tersedia | 100% P0 lulus, ≥ 95% P1 lulus; 0 defect S1/S2 terbuka; TC-PERF-01..05 memenuhi target; review kriptografi ANP/1 selesai |
| M3 Pilot | Kriteria M2 + pentest eksternal tanpa high/critical terbuka | Metrik G1/G2 pilot tercapai; 0 defect S1/S2 baru |
| M4 GA (R1) | Kriteria M3 + checklist App Review §13.1 | App Review lulus |
| M5 Kanal W (R2) | Diterima Apple Wallet Access Program; reader R6 bersertifikat IOT | TC-PRSW-* lulus; uji E2E & DR bersama Apple lulus; checklist §13.2 |

**Gerbang penyelesaian (JEV, ADR-0018):** sebelum milestone dinyatakan selesai, klaim penyelesaian (mis. "semua P0 lulus", "tidak ada S1/S2 terbuka") diverifikasi dengan `jev_gate` terhadap bukti nyata (laporan uji, ekspor defect tracker). Bila `jev_gate` mengembalikan `review`/`escalate`, milestone belum boleh ditutup sampai temuan ditangani manusia.

## 5. Katalog kasus uji

Format ID: `TC-<AREA>-<NN>`. **Prio:** P0/P1/P2. **Tipe:** U unit · I integrasi · C kontrak · H HIL · E E2E · S keamanan · P kinerja · D DR · A aksesibilitas · M kepatuhan/review. **Kanal:** W/N/B/Semua.

### 5.1 Kelayakan & gating (ELG)

| ID | Judul | Langkah / kondisi | Hasil diharapkan | Req | Prio | Tipe | Kanal |
|---|---|---|---|---|---|---|---|
| TC-ELG-01 | Perangkat & wilayah eligible | iPhone 11+ iOS 26, akun SG | Kanal N-SE dan B tersedia; fitur presentasi tampil | FR-01, FR-04 | P0 | E | N, B |
| TC-ELG-02 | `CardSession.isEligible` = false | Mock eligibility false | Fitur N-HCE disembunyikan dengan alasan; `CardSession()` **tidak** dipanggil (spy) | FR-01 | P0 | I | N |
| TC-ELG-03 | Entitlement tidak ada | Build tanpa entitlement HCE/SE | App tidak crash (tanpa `fatalError`); status `entitlementMissing`/`notEligible` | FR-01 | P0 | I | N |
| TC-ELG-04 | Wilayah Indonesia | Akun/storefront ID | Hanya kanal B aktif; kanal N tidak ditampilkan; pesan wilayah jelas | FR-04, NFR-C02 | P0 | E | Semua |
| TC-ELG-05 | Versi iOS di bawah minimum | Perangkat iOS 18 | App tidak dapat diinstal dari App Store (deployment target 26.0) | FR-02, NFR-CP01 | P0 | M | Semua |
| TC-ELG-06 | Pemilihan kanal otomatis | Gedung mengizinkan N-SE + B di SG | Kartu mendapat kredensial N-SE dan B; detail kartu menampilkan kedua kanal | FR-05 | P0 | E | N, B |
| TC-ELG-07 | Kebijakan gedung membatasi kanal | Gedung hanya mengizinkan B | Hanya kredensial B yang diterbitkan meski perangkat eligible N | FR-05, FR-55 | P1 | I | Semua |
| TC-ELG-08 | Kill switch kanal | `/config` mematikan N-HCE | Fitur N-HCE hilang setelah refresh config; kartu lain tetap jalan | FR-04 | P1 | I | N |

### 5.2 Akun (ACC)

| ID | Judul | Langkah / kondisi | Hasil diharapkan | Req | Prio | Tipe | Kanal |
|---|---|---|---|---|---|---|---|
| TC-ACC-01 | Sign in with Apple | Login baru | Akun dibuat; token di Keychain `ThisDeviceOnly` | FR-03 | P0 | E | Semua |
| TC-ACC-02 | OTP autofill & paste | Terima OTP via SMS; coba autofill lalu paste | Kedua cara berhasil; tanpa batas waktu ketik ketat (WCAG 2.2) | FR-03, NFR-A01 | P0 | A | Semua |
| TC-ACC-03 | Rate-limit OTP | Kirim OTP 6× dalam 10 menit | Dibatasi dengan pesan jelas | FR-03 | P1 | C | Semua |
| TC-ACC-04 | Persetujuan privasi | Onboarding pertama | Kebijakan privasi & ketentuan wajib disetujui; analitik default **off** | FR-07, NFR-PR04 | P0 | E | Semua |
| TC-ACC-05 | Hapus akun dari app | Pengaturan → Hapus akun → konfirmasi + autentikasi | Semua kredensial REVOKED; pass W dinonaktifkan; data pribadi terhapus ≤ 30 hari (TC-PRIV-02) | FR-06, NFR-C04 | P0 | E | Semua |
| TC-ACC-06 | Hapus akun saat masih PRIMARY dengan anggota | Pemilik dengan 2 anggota menghapus akun | Kepemilikan → "menunggu pemilik"; admin dinotifikasi; anggota tetap aktif sampai admin memutuskan | FR-06 | P1 | E | Semua |

### 5.3 Enrolment (ENR)

| ID | Judul | Langkah / kondisi | Hasil diharapkan | Req | Prio | Tipe | Kanal |
|---|---|---|---|---|---|---|---|
| TC-ENR-01 | PRIMARY dengan kontak cocok | Kartu terdaftar; kontak OTP = pemegang registri | Role PRIMARY → buat code → kartu Aktif ≤ 90 dtk; identitas kartu mentah tidak ada di DB/log | FR-10, FR-11, FR-14, FR-16, FR-18, NFR-PR02 | P0 | H | Semua |
| TC-ENR-02 | Kontak tidak cocok → persetujuan | Kartu terdaftar; kontak berbeda | Status "Menunggu persetujuan"; admin menyetujui → push → Aktif | FR-17, FR-18 | P0 | E | Semua |
| TC-ENR-03 | Sengketa klaim | Pengguna X sudah PRIMARY (disetujui admin); pemegang sah melapor | Antrean sengketa; keputusan REASSIGN → PRIMARY pindah, kredensial X dicabut, code dibuat ulang | FR-18, FR-59 | P0 | E | Semua |
| TC-ENR-04 | Kartu tidak terdaftar | Tempel kartu asing | `ENR-NOT-REGISTERED`; tidak ada kredensial dibuat | FR-13 | P0 | H | Semua |
| TC-ENR-05 | Kartu 125 kHz | Tempel kartu prox 125 kHz | `ENR-UNREADABLE` + tawaran undangan | FR-13 | P0 | H | Semua |
| TC-ENR-06 | Gedung belum mendukung | Pilih/scan gedung non-mitra | `ENR-SITE-UNSUPPORTED` + "Usulkan gedung saya" | FR-13, FR-64 | P1 | E | Semua |
| TC-ENR-07 | Enrolment via undangan | Buka Universal Link undangan valid | Kartu terdaftar tanpa kartu fisik | FR-12 | P0 | E | Semua |
| TC-ENR-08 | Undangan kedaluwarsa/terpakai | Buka link lama | Ditolak; tidak membocorkan info kartu | FR-12 | P0 | C | Semua |
| TC-ENR-09 | Konfirmasi code tidak cocok | Dua code berbeda | Diminta ulang; tidak dikirim ke server | FR-14 | P0 | U | Semua |
| TC-ENR-10 | Code lemah | `000000`, `123456`, `111111` | Ditolak | FR-14 | P1 | U | Semua |
| TC-ENR-11 | Batas 8 kartu | Tambah kartu ke-9 | Ditolak di app dan server (409 `ENR-LIMIT`) | FR-15 | P0 | I | Semua |
| TC-ENR-12 | Race batas 8 | 2 permintaan paralel saat ada 7 kartu | Hanya 1 berhasil (invarian DB) | FR-15 | P0 | I | Semua |
| TC-ENR-13 | Kunci di Secure Enclave | Coba ekspor/kueri kunci | Tidak dapat diekspor; atribut `WhenPasscodeSetThisDeviceOnly` + `.userPresence` | FR-16, NFR-S01 | P0 | S | N, B |
| TC-ENR-14 | MIFARE Classic 1K | Tempel kartu 1K | Hasil dicatat (U05); bila tidak terbaca → undangan | FR-11 | P0 | H | Semua |
| TC-ENR-15 | DESFire *random ID* | Tempel DESFire dengan random UID | Identitas dibaca via SELECT AID aplikasi (bukan UID); cocok dengan registri | FR-11 | P0 | H | Semua |
| TC-ENR-16 | Lanjutkan enrolment terputus | Tutup app setelah baca kartu, buka lagi < 15 menit | Enrolment dilanjutkan; setelah 15 menit kedaluwarsa tanpa kredensial yatim | FR-19 | P1 | I | Semua |
| TC-ENR-17 | App Attest gagal | Assertion dimanipulasi/jailbreak | Provisioning ditolak (403) | NFR-S03 | P0 | S | Semua |
| TC-ENR-18 | Personalisasi applet N-SE | Enrolment di SG dengan N-SE | `provisionCredential` + mode wired + relai APDU sukses; jeda < 15 dtk antar `transceive` | FR-16 | P0 | H | N |

### 5.4 Presentasi NFC in-app (PRSN)

| ID | Judul | Langkah / kondisi | Hasil diharapkan | Req | Prio | Tipe | Kanal |
|---|---|---|---|---|---|---|---|
| TC-PRSN-01 | Tap sukses N-HCE | Pilih kartu → Face ID → tempel ke R1/R2 | Grant; `.success` + haptic; pintu terbuka | FR-20, FR-26 | P0 | H | N |
| TC-PRSN-02 | Tap sukses N-SE | Pilih kartu → otorisasi sistem → tempel ke R2 | Grant; sesi kembali ke management | FR-20 | P0 | H | N |
| TC-PRSN-03 | Autentikasi dibatalkan | Batalkan Face ID/otorisasi | Emulasi tidak dimulai; tidak ada assertion | FR-20 | P0 | H | N |
| TC-PRSN-04 | Timeout 60 dtk (HCE) | Mulai emulasi, jangan tempel | `PRS-TIMEOUT` pada 60 dtk; tombol "Coba lagi" | FR-22 | P0 | H | N |
| TC-PRSN-05 | Cooldown assertion (HCE) | Mulai, batal, mulai lagi < 15 dtk | Menunggu cooldown dengan indikator; tidak spam acquire | FR-21 | P0 | H | N |
| TC-PRSN-06 | Batas 2 assertion/80 dtk (SE) | 3 presentasi beruntun < 80 dtk | Presentasi ke-3 ditunda dengan pesan; tanpa error sistem | FR-21 | P0 | H | N |
| TC-PRSN-07 | App ke background saat sesi SE | Mulai presentasi, pindah app, kembali | Sesi diinvalidasi sistem; UI pulih; presentasi berikutnya sukses | FR-22 | P0 | H | N |
| TC-PRSN-08 | Koeksistensi Apple Pay | Kartu dipilih, tempel ke R2 | Apple Pay tidak muncul | FR-21, FR-28 | P0 | H | N |
| TC-PRSN-09 | Apple Pay tetap normal | App di background, tempel ke R5 | Apple Pay berfungsi normal | FR-28 | P0 | H | N |
| TC-PRSN-10 | Offline | Mode pesawat (NFC aktif), tap | Grant (reader offline dengan cache) | FR-25 | P0 | H | N |
| TC-PRSN-11 | iPhone terkunci | Kunci iPhone, tempel ke R2 | Tidak ada presentasi tanpa membuka app & autentikasi | FR-27 | P0 | H | N |
| TC-PRSN-12 | Pemilihan via reader group | 3 kartu dari 3 gedung; tap di gedung B | Kredensial gedung B dipakai; ponsel tidak mengungkap gedung lain | FR-29 | P1 | H | N |
| TC-PRSN-13 | Kartu ditangguhkan | Admin suspend → tap | Ditolak; `PRS-SUSPENDED` | FR-51 | P0 | H | N |
| TC-PRSN-14 | Zona tidak diizinkan | Kredensial zona A di reader zona B | Ditolak; `PRS-DENIED-ZONE` tercatat | FR-26 | P0 | H | N |
| TC-PRSN-15 | Tarik iPhone di tengah pertukaran | Jauhkan sebelum RESULT | `readerDeselected` ditangani; UI "Coba lagi"; tidak crash | FR-22, FR-26 | P0 | H | N |
| TC-PRSN-16 | Retry `transmissionError` | Injeksi error pada `respond` (mock) | Retry sekali lalu gagal bersih | FR-20 | P1 | I | N |
| TC-PRSN-17 | Teks tanpa jargon | Periksa string presentasi | Tidak ada "NFC"/"HCE"/"APDU" | FR-26 | P1 | U | N |

### 5.5 Presentasi BLE (PRSB)

| ID | Judul | Langkah / kondisi | Hasil diharapkan | Req | Prio | Tipe | Kanal |
|---|---|---|---|---|---|---|---|
| TC-PRSB-01 | Tap BLE sukses | Buka widget → autentikasi → dekatkan ke R2 | Grant ≤ 1,5 dtk p95 | FR-80, NFR-P04 | P0 | H | B |
| TC-PRSB-02 | Bluetooth mati | Matikan Bluetooth, coba buka | `CH-BT-OFF` + panduan | FR-82 | P0 | E | B |
| TC-PRSB-03 | Izin Bluetooth ditolak | Tolak izin | `CH-BT-DENIED` + tautan Pengaturan | FR-82 | P0 | E | B |
| TC-PRSB-04 | Dua reader berdekatan | R2-A (−50 dBm) dan R2-B (−60 dBm) | Hanya R2-A yang diproses | FR-83 | P1 | H | B |
| TC-PRSB-05 | Di bawah ambang RSSI | Berdiri 2 m dari reader | Tidak ada transaksi; status "Dekatkan iPhone" | FR-80, FR-83 | P1 | H | B |
| TC-PRSB-06 | Rate-limit per reader | Dua transaksi < 3 dtk | Transaksi kedua ditunda | FR-83 | P1 | H | B |
| TC-PRSB-07 | Tidak ada unlock di background | App di background, lewat di depan reader | Tidak ada transaksi (ADR-0012) | FR-81 | P0 | H | B |
| TC-PRSB-08 | Fragmentasi MTU | Paksa MTU kecil (R7) | Frame difragmentasi & disusun ulang benar; grant | FR-80 | P1 | H | B |

### 5.6 Apple Wallet (PRSW, R2)

| ID | Judul | Langkah / kondisi | Hasil diharapkan | Req | Prio | Tipe | Kanal |
|---|---|---|---|---|---|---|---|
| TC-PRSW-01 | Add to Apple Wallet | Akhir enrolment → tombol resmi | Pass ter-provision; status di app = aktif | FR-70 | P0 | E | W |
| TC-PRSW-02 | Express Mode, iPhone terkunci | Tempel iPhone terkunci ke R6 | Grant tanpa Face ID | FR-23 | P0 | H | W |
| TC-PRSW-03 | Power reserve | Baterai habis (model didukung) | Pass Express tetap berfungsi | FR-23, FR-27 | P1 | H | W |
| TC-PRSW-04 | Auto-presentment via TCI | 2 pass gedung berbeda; tap di gedung B | Pass B otomatis dipilih | FR-23 | P0 | H | W |
| TC-PRSW-05 | TRA | Reader zona lab ber-TRA | Diminta autentikasi walau Express aktif | FR-23 | P0 | H | W |
| TC-PRSW-06 | Apple Watch | Provisioning dengan Watch berpasangan | Watch mendapat kredensial terpisah; tercatat di audit | FR-46 | P1 | E | W |
| TC-PRSW-07 | Lost Mode | Aktifkan Lost Mode via Find My | Pass suspend; server menerima notifikasi; status app sinkron | FR-42, FR-71 | P0 | E | W |
| TC-PRSW-08 | Suspend oleh CM | Admin suspend | Hanya CM yang dapat resume; pengguna tidak bisa | FR-51, FR-71 | P0 | E | W |
| TC-PRSW-09 | Easy Provisioning | iPhone baru → tambah dari Wallet | Pass aktif di perangkat baru; batas perangkat dipatuhi | FR-41 | P0 | E | W |
| TC-PRSW-10 | Sharing nonaktif | Coba bagikan pass dari Wallet | Opsi share tidak tersedia (ADR-0013) | FR-35 | P0 | E | W |
| TC-PRSW-11 | Update pass | Admin mengubah nama gedung/zona | Pass diperbarui (pass update) | FR-71, FR-72 | P1 | E | W |
| TC-PRSW-12 | Web Provisioning | Tambah pass dari web | Pass ter-provision tanpa app | FR-73 | P2 | E | W |

### 5.7 Manajemen kartu & anggota (MGT)

| ID | Judul | Langkah / kondisi | Hasil diharapkan | Req | Prio | Tipe | Kanal |
|---|---|---|---|---|---|---|---|
| TC-MGT-01 | Detail kartu | Buka kartu | Nama, gedung, zona, status, kanal, masa berlaku, riwayat tampil | FR-30 | P0 | E | Semua |
| TC-MGT-02 | Hapus kartu | Detail → Hapus → konfirmasi + autentikasi | Kunci dihapus; REVOKED; reader menolak setelah sinkron; pass W dinonaktifkan | FR-31 | P0 | E | Semua |
| TC-MGT-03 | Anggota bergabung | B tempel kartu yang sama → code A | B jadi MEMBER; A menerima push | FR-32, FR-62 | P0 | E | Semua |
| TC-MGT-04 | Code salah 5× | B salah 5 kali | Terkunci 30 menit; sisa waktu ditampilkan | NFR-S05 | P0 | S | Semua |
| TC-MGT-05 | Code salah 10×/24 jam | Lanjutkan percobaan | Terkunci + notifikasi pemilik | NFR-S05 | P0 | S | Semua |
| TC-MGT-06 | Hapus anggota | A → Anggota → hapus B | Kredensial B REVOKED; B menerima push; tap B ditolak | FR-33 | P0 | E | Semua |
| TC-MGT-07 | Ganti code | A ganti code (autentikasi + code lama) | Code baru berlaku; code lama ditolak untuk anggota baru; anggota lama tetap aktif | FR-34 | P0 | E | Semua |
| TC-MGT-08 | Anggota tidak bisa kelola | B membuka menu anggota | Kelola tidak tersedia | FR-33 | P0 | E | Semua |
| TC-MGT-09 | Tidak ada share | Cari share/AirDrop/ekspor | Tidak ada; Share Sheet tanpa data kredensial | FR-35 | P0 | E | N, B |
| TC-MGT-10 | Batas anggota | Tambah anggota ke-5 (default 4) | Ditolak dengan pesan | FR-36 | P1 | I | Semua |
| TC-MGT-11 | Status kartu | Paksa tiap status | Label + ikon + teks benar untuk Aktif/Menunggu/Ditangguhkan/Perlu diperbarui/Dicabut | FR-38 | P0 | E | Semua |
| TC-MGT-12 | Widget & shortcut | Ketuk widget "Lobi"; jalankan App Shortcut | App terbuka ke presentasi kartu Lobi; tetap minta autentikasi | FR-24 | P1 | E | N, B |
| TC-MGT-13 | Rename & warna | Ubah nama/warna kartu | Tersimpan lokal; tidak memengaruhi pass Wallet | FR-37 | P2 | E | N, B |
| TC-MGT-14 | Info kartu fisik | Buka Detail → Info | Kebijakan kartu fisik ditampilkan | FR-39 | P2 | E | Semua |

### 5.8 Perangkat, kehilangan, lifecycle (DEV)

| ID | Judul | Langkah / kondisi | Hasil diharapkan | Req | Prio | Tipe | Kanal |
|---|---|---|---|---|---|---|---|
| TC-DEV-01 | Tidak ikut backup | Backup iCloud → restore ke iPhone lain | Kartu "Perlu dipindahkan" (`DEV-KEY-MISSING`); tidak dapat dipakai | FR-40 | P0 | E | N, B |
| TC-DEV-02 | Transfer perangkat | iPhone baru: SIWA + OTP → Pindahkan | Kredensial baru ACTIVE; lama REVOKED; tap di iPhone lama ditolak | FR-41 | P0 | E | N, B |
| TC-DEV-03 | Suspend semua via portal | Portal → Tangguhkan semua | Reader online menolak ≤ 60 dtk | FR-42, NFR-R04 | P0 | H | Semua |
| TC-DEV-04 | Propagasi ke reader offline | Reader offline → online | Denylist diterapkan ≤ interval sinkron | FR-42, NFR-R04 | P0 | H | N, B |
| TC-DEV-05 | Find My Erase | Erase perangkat uji | Kunci hilang; server UNREACHABLE setelah TTL | FR-42, FR-43 | P1 | E | N, B |
| TC-DEV-06 | Reinstall app | Hapus & pasang ulang app | Kartu lama tidak dapat dipakai; tawarkan transfer | FR-43 | P0 | E | N, B |
| TC-DEV-07 | Passcode dimatikan | Matikan passcode perangkat | Kunci in-app terhapus; app mendeteksi & menawarkan pemulihan | FR-44 | P0 | E | N, B |
| TC-DEV-08 | Face ID didaftarkan ulang | Reset & daftar ulang Face ID | Kredensial **tetap** berfungsi (ADR-0009) | FR-44 | P0 | E | N, B |
| TC-DEV-09 | Perpanjangan otomatis | Majukan jam hingga sisa < 50%; app online; lakukan tap | Sertifikat diperpanjang setelah tap tanpa prompt tambahan (ADR-0023) | FR-45 | P0 | I | N, B |
| TC-DEV-10 | Peringatan perlu online | Sisa < 24 jam, perangkat offline | Peringatan "Perlu terhubung ke internet"; status "Perlu diperbarui" | FR-45, FR-38 | P0 | E | N, B |
| TC-DEV-11 | Sertifikat kedaluwarsa | Offline > 7 hari, tap | Ditolak `CRED-EXPIRED`; setelah online → diperpanjang → grant | FR-45, NFR-R04 | P0 | H | N, B |
| TC-DEV-12 | Satu kredensial per kartu per iPhone | Coba enrolment ganda kartu sama di iPhone sama | Ditolak/idempoten | FR-46 | P1 | I | Semua |

### 5.9 Portal admin (ADM)

| ID | Judul | Hasil diharapkan | Req | Prio | Tipe |
|---|---|---|---|---|---|
| TC-ADM-01 | RBAC antar gedung | Admin gedung A tidak dapat melihat gedung B (403) | FR-50, FR-56 | P0 | I |
| TC-ADM-02 | SSO + MFA wajib | Login tanpa MFA ditolak; idle 15 menit → logout | FR-56, NFR-S10 | P0 | S |
| TC-ADM-03 | Approve/suspend/resume/revoke | Status & sinkron reader sesuai; tercatat di audit | FR-51 | P0 | E |
| TC-ADM-04 | Impor registri CSV | Identitas kartu & kontak tersimpan sebagai HMAC; duplikat ditolak | FR-52, NFR-PR02 | P0 | I |
| TC-ADM-05 | Undangan | Token sekali pakai, kedaluwarsa | FR-53 | P0 | E |
| TC-ADM-06 | Audit hash-chain | Modifikasi baris → verifikasi rantai gagal | FR-54 | P0 | S |
| TC-ADM-07 | Audit tanpa GPS | Tidak ada field lokasi pengguna | FR-54, NFR-PR01 | P0 | I |
| TC-ADM-08 | Kebijakan gedung | Ubah maks anggota, masa berlaku sertifikat (1–30), kanal, TRA → berlaku | FR-55 | P0 | E |
| TC-ADM-09 | Armada reader | Status online, firmware, sinkron terakhir tampil; rotasi kunci group | FR-57 | P1 | E |
| TC-ADM-10 | Laporan & ekspor | Ekspor kredensial aktif per kanal & adopsi | FR-58 | P1 | E |
| TC-ADM-11 | Antrean sengketa | Keputusan tercatat; REASSIGN berjalan (lihat TC-ENR-03) | FR-59 | P0 | E |
| TC-ADM-12 | Alert aksi massal | Revoke > 50 kredensial dalam 5 menit | Konfirmasi tambahan + alert Security Officer | NFR-S10 | P1 | S |

### 5.10 Konformansi protokol ANP/1 (PROTO)

| ID | Judul | Hasil diharapkan | Req | Prio | Tipe |
|---|---|---|---|---|---|
| TC-PROTO-01 | Test vector bersama | App, firmware R2, dan gateway R3 menghasilkan output identik untuk vektor uji (`Packages/Tests/ANCryptoTests/Resources/anp1-v1.json`) | NFR-S02 | P0 | U |
| TC-PROTO-02 | FCI tanpa identitas | SELECT hanya mengembalikan versi & kapabilitas | NFR-S02 | P0 | U |
| TC-PROTO-03 | Alur AUTH0/AUTH1 sukses | Grant dengan R1 referensi | FR-20 | P0 | I |
| TC-PROTO-04 | Reader group tak dikenal | Respons `6982` dan tidak ada data lain | NFR-S02 | P0 | S |
| TC-PROTO-05 | `sig_R` salah | Respons identik dengan TC-PROTO-04 (format & timing setara) | NFR-S02 | P0 | S |
| TC-PROTO-06 | Replay transcript lama | Ditolak (ephemeral & `txn_id` baru) | NFR-S02 | P0 | S |
| TC-PROTO-07 | Ciphertext dimodifikasi | Tag GCM gagal → tolak | NFR-S02 | P0 | S |
| TC-PROTO-08 | Jalur GET_CERT | Cache reader kosong → GET_CERT → grant | FR-25 | P0 | I |
| TC-PROTO-09 | Ukuran pesan | Semua APDU < 255 B (tanpa extended length, U08) | NFR-CP02 | P0 | U |
| TC-PROTO-10 | Negosiasi versi | Reader v1 ↔ app v1/v2 → versi tertinggi yang sama; tanpa kecocokan → `6D00` | NFR-CP02 | P1 | I |
| TC-PROTO-11 | Counter anomali | Counter mundur → reader/backend menandai anomali | NFR-S02 | P1 | I |
| TC-PROTO-12 | TLV rusak | `6700`/`6A80`, tanpa crash | NFR-S09 | P0 | U |
| TC-PROTO-13 | Fuzzing APDU & frame BLE | 10.000 input acak → tanpa crash, tanpa kebocoran | NFR-S09 | P1 | S |
| TC-PROTO-14 | Framing BLE | Frame `type/seq/flags/len` benar; reassembly benar | FR-80 | P0 | U |

### 5.11 Reader & Edge Gateway (RDR)

| ID | Judul | Hasil diharapkan | Req | Prio | Tipe |
|---|---|---|---|---|---|
| TC-RDR-01 | Keputusan offline | Reader tanpa jaringan memberi grant/deny benar dari cache | FR-25 | P0 | H |
| TC-RDR-02 | Push denylist ≤ 60 dtk | Revoke → reader online menolak ≤ 60 dtk | NFR-R04 | P0 | H |
| TC-RDR-03 | Bundel dimodifikasi | Tanda tangan bundel tidak valid → ditolak, bundel lama dipertahankan | NFR-S08 | P0 | S |
| TC-RDR-04 | Toleransi jam | Jam reader menyimpang 4 menit → OK; 10 menit → alarm | NFR-R04 | P1 | H |
| TC-RDR-05 | Rotasi kunci reader group | Aktifkan kunci "next" → tidak ada pengguna yang terkunci | NFR-S08 | P0 | H |
| TC-RDR-06 | Output ke panel | Grant → `acs_card_number` terkirim via OSDP/Wiegand; panel membuka pintu | FR-25 | P0 | H |
| TC-RDR-07 | Jalur gateway transparan | R3 + gateway: tap N sukses | NFR-CP02 | P1 | H |
| TC-RDR-08 | Update firmware | Firmware bertanda tangan → sukses; tanpa tanda tangan → ditolak; rollback A/B | NFR-S09 | P1 | S |
| TC-RDR-09 | Alarm tamper | Buka casing → alarm ke backend | FR-57 | P2 | H |

### 5.12 Keamanan (SEC)

| ID | Judul | Hasil diharapkan | Req | Prio | Tipe |
|---|---|---|---|---|---|
| TC-SEC-01 | Relay (2 perangkat, +latensi) | Ditolak pada ambang timing terkalibrasi; ambang tercatat (U06) | NFR-S07 | P0 | S |
| TC-SEC-02 | Certificate pinning | MITM dengan CA kustom → koneksi gagal | NFR-S06 | P0 | S |
| TC-SEC-03 | Token kedaluwarsa | 401 → refresh → sukses; refresh dicabut → logout | NFR-S06 | P0 | S |
| TC-SEC-04 | Security code tidak lokal | Inspeksi sandbox app (perangkat dev) | NFR-S04 | P0 | S |
| TC-SEC-05 | Jailbreak | Provisioning ditolak | NFR-S03 | P1 | S |
| TC-SEC-06 | OWASP MASVS v2 | Semua kontrol dalam pemetaan §7.3 lulus | NFR-S09 | P0 | S |
| TC-SEC-07 | Audit build `.ipa` (REA) | Entitlement sesuai; tanpa rahasia ter-embed; Privacy Manifest ada | NFR-S09, NFR-PR04 | P1 | S |
| TC-SEC-08 | Skimming oleh reader asing | Reader tanpa kunci group tidak mendapatkan `cred_id`/sertifikat | NFR-S02 | P0 | S |
| TC-SEC-09 | Enrolment hijack | Peminjam kartu tidak bisa jadi PRIMARY tanpa persetujuan | FR-18 | P0 | S |
| TC-SEC-10 | Brute-force terdistribusi | Banyak akun menebak code satu kartu → lockout per kepemilikan + alert | NFR-S05 | P0 | S |
| TC-SEC-11 | Pemindaian secret & dependensi | Tidak ada secret di repo/build; tidak ada CVE kritis terbuka | NFR-S09 | P0 | S |
| TC-SEC-12 | Pentest eksternal | Tidak ada temuan high/critical terbuka saat pilot/GA | NFR-S09 | P0 | S |
| TC-SEC-13 | Rotasi Site CA | CA baru → perpanjangan menerbitkan sertifikat dari CA baru; transisi tanpa lockout | NFR-S08 | P1 | S |
| TC-SEC-14 | Pembaruan sertifikat layanan | Alert ≥ 30 hari sebelum kedaluwarsa; perpanjangan otomatis | NFR-S08 | P1 | I |

### 5.13 Privasi (PRIV)

| ID | Judul | Hasil diharapkan | Req | Prio | Tipe |
|---|---|---|---|---|---|
| TC-PRIV-01 | Tidak ada identitas kartu mentah | Kueri DB, log, trace → hanya HMAC | NFR-PR02 | P0 | S |
| TC-PRIV-02 | Kelengkapan hapus akun | ≤ 30 hari: data pribadi hilang; audit dipseudonimkan | FR-06, NFR-PR03 | P0 | I |
| TC-PRIV-03 | Privacy Manifest & Nutrition Label | Sesuai data yang benar-benar dikumpulkan; tanpa tracking | NFR-PR04 | P0 | M |
| TC-PRIV-04 | Tanpa GPS/ATT | App tidak meminta lokasi atau ATT di R1 | NFR-PR01 | P0 | M |
| TC-PRIV-05 | Payload push | Tidak memuat nama gedung/zona/identitas | FR-62 | P0 | I |
| TC-PRIV-06 | Ekspor diagnostik | Tanpa token, kunci, atau identitas kartu | FR-63 | P1 | S |
| TC-PRIV-07 | Retensi log & metrik | Log 30 hari; metrik 18 bulan; audit sesuai kebijakan | NFR-PR03, NFR-O01 | P1 | I |

### 5.14 Kinerja, keandalan, DR (PERF, DR)

| ID | Metrik / skenario | Target | Req | Prio | Tipe |
|---|---|---|---|---|---|
| TC-PERF-01 | SELECT → RESULT (N, iPhone 11, R2) | ≤ 500 ms p95 | NFR-P01 | P0 | P |
| TC-PERF-02 | Ketuk kartu → siap ditempel (N) | ≤ 2 dtk p95 | NFR-P02 | P0 | P |
| TC-PERF-03 | Cold start (iPhone 11) | ≤ 1,5 dtk p95 | NFR-P03 | P0 | P |
| TC-PERF-04 | Intent → keputusan (B) | ≤ 1,5 dtk p95 | NFR-P04 | P0 | P |
| TC-PERF-05 | Beban API (config/renew/enrol) 1.000 rps | p95 ≤ 300 ms, error < 0,1% | NFR-P05, NFR-R02 | P0 | P |
| TC-PERF-06 | Endpoint Apple Access (R2) | p90 < 2,2 dtk | NFR-P05 | P0 | P |
| TC-PERF-07 | 500 tap per kanal per reader tersertifikasi | ≥ 95% percobaan pertama, ≥ 99% dalam 2 | NFR-R01 | P0 | P |
| TC-PERF-08 | Propagasi revoke | ≤ 60 dtk (reader online) | NFR-R04 | P0 | P |
| TC-DR-01 | Drill failover region | RTO ≤ 30 menit, RPO ≤ 5 menit | NFR-R03 | P0 | D |
| TC-DR-02 | Backend mati total | Tap tetap berfungsi (offline-first); enrolment menampilkan `NET-OFFLINE` | NFR-R02 | P0 | D |
| TC-DR-03 | Reader terputus 8 hari | Kredensial yang dicabut pada hari ke-1 ditolak paling lambat saat sertifikat kedaluwarsa (≤ 7 hari) | NFR-R04 | P0 | D |
| TC-DR-04 | Ketersediaan | Pemantauan uptime bulanan ≥ 99,9% (R1) / 99,99% (R2) | NFR-R02 | P1 | D |

### 5.15 Aksesibilitas, lokalisasi, UX (UX)

| ID | Judul | Hasil diharapkan | Req | Prio | Tipe |
|---|---|---|---|---|---|
| TC-UX-01 | VoiceOver di alur tambah & presentasi | Semua kontrol berlabel; hasil presentasi diumumkan | NFR-A01 | P0 | A |
| TC-UX-02 | Dynamic Type AX5 | Tidak ada teks terpotong | NFR-A01 | P0 | A |
| TC-UX-03 | Kontras token | Sesuai tabel design system (≥ 4,5:1) di mode terang & gelap | NFR-A01 | P0 | A |
| TC-UX-04 | Target sentuh | Semua ≥ 44 pt; jarak ≥ 8 pt | NFR-A01 | P0 | A |
| TC-UX-05 | Reduce Motion | Tanpa animasi dekoratif saat aktif | NFR-A01 | P1 | A |
| TC-UX-06 | Bahasa ID & EN | Semua string diterjemahkan; format tanggal lokal | FR-61 | P0 | E |
| TC-UX-07 | zh-Hant & ms | Wajib bila pilot di HK/MY | FR-61 | P1 | E |
| TC-UX-08 | FAQ in-app | Mencakup semua topik FR-60, per kanal | FR-60 | P0 | E |
| TC-UX-09 | Checklist design system | Checklist `pages/ios-app.md` §9 terpenuhi | NFR-A01, NFR-C01 | P0 | M |
| TC-UX-10 | Pesan error | Setiap kode katalog SDD §15 menampilkan pesan + langkah lanjut | FR-26 | P1 | E |

### 5.16 Kepatuhan (CMP) & upgrade (UPG)

| ID | Judul | Hasil diharapkan | Req | Prio | Tipe |
|---|---|---|---|---|---|
| TC-CMP-01 | Tanpa tiruan Wallet/Apple Pay | Review desain lulus; tombol Wallet memakai aset resmi | NFR-C01 | P0 | M |
| TC-CMP-02 | Assertion hanya saat intent | Review kode + log: tidak ada acquire otomatis/background | FR-21 | P0 | M |
| TC-CMP-03 | Fitur tidak eligible disembunyikan | Lihat TC-ELG-02/04 | NFR-C02 | P0 | M |
| TC-CMP-04 | Materi App Review kanal N | Checklist §13.1 lengkap | NFR-C01 | P0 | M |
| TC-CMP-05 | Persyaratan Apple Wallet Access Program | Checklist §13.2 lengkap | NFR-C03 | P0 | M |
| TC-CMP-06 | Hapus akun sesuai 5.1.1(v) | Inisiasi dari dalam app tersedia | NFR-C04 | P0 | M |
| TC-UPG-01 | Update app | Update app tidak menghilangkan kredensial/kunci | FR-40 | P0 | E |
| TC-UPG-02 | Migrasi skema SwiftData | Data lokal termigrasi tanpa kehilangan | FR-30 | P1 | I |
| TC-UPG-03 | Kompatibilitas protokol | App baru ↔ reader lama (dan sebaliknya) berfungsi sesuai negosiasi versi | NFR-CP02 | P1 | H |

## 6. Acceptance test (Gherkin)

```gherkin
# AT-01 ↔ US-01
Scenario: Pemegang utama menambah kartu fisik terdaftar
  Given saya login dengan kontak yang cocok dengan registri gedung
  And kartu fisik saya terdaftar di gedung pilot
  When saya menempelkan kartu ke iPhone dan membuat security code 6 digit
  Then kartu berstatus "Aktif" dalam 90 detik
  And identitas kartu mentah tidak tersimpan di server

# AT-02 ↔ US-02
Scenario: Kartu 125 kHz ditolak dengan alasan jelas
  When saya menempelkan kartu 125 kHz
  Then saya melihat "Kartu tidak dapat dibaca iPhone"
  And saya ditawari meminta undangan dari pengelola

# AT-03 ↔ US-03
Scenario: Peminjam kartu tidak menjadi pemegang utama
  Given kontak saya tidak cocok dengan pemegang di registri
  When saya menambah kartu tersebut
  Then status kartu "Menunggu persetujuan"
  And pemegang sah dapat mengajukan sengketa

# AT-04 ↔ US-04
Scenario: Anggota terkunci setelah 5 kode salah
  Given kartu sudah memiliki pemegang utama
  When saya memasukkan security code salah 5 kali
  Then saya terkunci 30 menit
  And pemegang utama tidak menerima anggota baru dari saya

# AT-05 ↔ US-05
Scenario: Membuka pintu dengan NFC in-app
  Given saya berada di gedung kanal N dan kartu saya aktif
  When saya memilih kartu, mengautentikasi, dan menempelkan iPhone ke reader
  Then reader memberi akses dalam 500 ms (p95)
  And Apple Pay tidak muncul

# AT-06 ↔ US-06
Scenario: Membuka pintu dengan BLE di Indonesia
  Given akun saya di Indonesia dan Bluetooth aktif
  When saya membuka widget dan mendekatkan iPhone ke reader
  Then reader memberi akses dalam 1,5 detik (p95)

# AT-07 ↔ US-07
Scenario: Express Mode di Apple Wallet
  Given pass saya di Apple Wallet dengan Express Mode
  When saya menempelkan iPhone yang terkunci ke reader biasa
  Then akses diberikan tanpa Face ID
  But reader zona TRA meminta autentikasi

# AT-08 ↔ US-08
Scenario: Pindah ke iPhone baru
  When saya login di iPhone baru dan memilih "Pindahkan kartu"
  Then kartu aktif di iPhone baru
  And iPhone lama ditolak oleh reader

# AT-09 ↔ US-09
Scenario: Menangguhkan semua kartu dari web
  When saya memilih "Tangguhkan semua kartu" di portal
  Then reader online menolak kartu saya dalam 60 detik

# AT-10 ↔ US-10
Scenario: Menghapus akun dari dalam app
  When saya menghapus akun dan mengonfirmasi
  Then semua kredensial saya dicabut
  And data pribadi saya dihapus dalam 30 hari

# AT-11 ↔ US-11
Scenario: Admin mencabut akses penghuni yang pindah
  When admin mencabut kredensial penghuni
  Then reader online menolak dalam 60 detik
  And aksi tercatat di audit log

# AT-12 ↔ US-12
Scenario: Peringatan perpanjangan sertifikat
  Given sertifikat kartu saya tersisa kurang dari 24 jam dan saya offline
  Then saya melihat peringatan "Perlu terhubung ke internet"
  When saya kembali online
  Then sertifikat diperpanjang otomatis
```

## 7. Rencana uji non-fungsional

### 7.1 Kinerja & beban

Skenario k6 di lingkungan Load:
- (a) lonjakan enrolment 20 rps × 30 menit;
- (b) perpanjangan sertifikat 1.000 rps × 10 menit;
- (c) `/config` 1.000 rps;
- (d) R2: simulasi panggilan Apple Access Platform dengan target p90 < 2,2 dtk.

Instruments di perangkat untuk TC-PERF-01..04 (iPhone 11 sebagai batas bawah).

### 7.2 DR

Drill per kuartal: matikan region primer, lalu ukur RTO/RPO (TC-DR-01). Uji offline-first: backend mati dan tap tetap jalan (TC-DR-02). Untuk R2 dilakukan juga uji DR bersama Apple (O-W14).

### 7.3 Pemetaan OWASP MASVS v2

| Kategori MASVS | Kontrol Anastrophe | Kasus uji |
|---|---|---|
| MASVS-STORAGE | Kunci di Secure Enclave/SE; Keychain `ThisDeviceOnly`; SwiftData dikecualikan dari backup; tanpa code di perangkat | TC-ENR-13, TC-DEV-01, TC-SEC-04 |
| MASVS-CRYPTO | ECDH/ECDSA P-256, HKDF, AES-GCM; test vector; review eksternal | TC-PROTO-01..07 |
| MASVS-AUTH | SIWA + OTP; `.userPresence`; App Attest; re-auth aksi sensitif | TC-ACC-01..03, TC-ENR-17, TC-DEV-08 |
| MASVS-NETWORK | TLS 1.3 + pinning; mTLS reader | TC-SEC-02, TC-RDR-03 |
| MASVS-PLATFORM | Entitlement minimum; assertion hanya saat intent; tanpa ekstensi presentasi | TC-CMP-02, TC-SEC-07 |
| MASVS-CODE | Pemindaian dependensi; fuzzing | TC-SEC-11, TC-PROTO-13 |
| MASVS-RESILIENCE | Deteksi jailbreak; App Attest | TC-SEC-05, TC-ENR-17 |
| MASVS-PRIVACY | Minimisasi data; hapus akun; Privacy Manifest | TC-PRIV-01..07 |

### 7.4 Rig HIL

- Lengan servo menempelkan iPhone ke reader dengan jarak dan sudut terkontrol.
- Skrip pyscard (R1) atau log reader (R2) mencatat waktu setiap APDU.
- Untuk BLE, peripheral R7 dapat menyuntikkan delay, drop, dan fragmentasi.
- Output: CSV latensi per langkah protokol, tingkat sukses per perangkat × reader.

### 7.5 Sertifikasi kompatibilitas reader (internal)

Reader baru masuk daftar tersertifikasi bila lulus: TC-PROTO-01..09, TC-RDR-01..06, dan TC-PERF-07 pada 3 perangkat (iPhone 11, iPhone 17 Pro, iPhone SE gen 2). Untuk kanal W, sertifikasi IOT Apple tetap wajib (O-W07).

## 8. Regresi & otomasi

| Tahap | Isi | Pemicu |
|---|---|---|
| PR | Unit + integrasi P0, lint, pemindaian secret, test vector protokol | Setiap PR |
| Nightly | Kontrak API, backend, fuzzing ringkas, cek dokumen (link, ID traceability, render Mermaid) | Setiap malam |
| Pra-rilis | Semua P0 bertipe H/E/S di matriks minimum (iPhone 11 + iPhone 17 Pro × R2 + R3) | Release branch |
| Release candidate | Matriks penuh §3.2 × §3.3, keamanan, privasi, aksesibilitas, lalu gerbang `jev_gate` (§4) | Sebelum submit App Store |

**Kebijakan flaky:** tes yang gagal intermiten dikarantina maksimal 7 hari dengan tiket; kasus P0 tidak boleh dikarantina.

## 9. Data uji

- Gedung uji "LAB-01" (3 zona, satu zona TRA) dan "LAB-02" (gedung kedua untuk uji multi-kartu), masing-masing dengan Site CA uji, bukan produksi.
- 20 kartu fisik terdaftar dan 5 tidak terdaftar; registri memuat kontak yang cocok dan yang tidak cocok.
- Akun uji: PRIMARY (A), MEMBER (B), penyerang (C), pemegang sah untuk sengketa (D), admin gedung, admin gedung lain, Security Officer.
- Kartu/akun produksi **tidak boleh** dipakai di lab.

## 10. Manajemen defect

| Severity | Definisi | Contoh | SLA perbaikan |
|---|---|---|---|
| S1 Blocker | Akses tidak sah mungkin, atau kebocoran kunci/data pribadi | Replay berhasil, identitas bocor ke reader asing | Hotfix ≤ 24 jam |
| S2 Critical | Fitur P0 gagal tanpa workaround | Tap gagal di reader tersertifikasi | ≤ 3 hari kerja |
| S3 Major | Fitur gagal dengan workaround / P1 gagal | Widget tidak membuka kartu | Rilis berikutnya |
| S4 Minor | Kosmetik, teks | Typo terjemahan | Backlog |

Triase 2× seminggu; seluruh S1/S2 ditinjau Security + Product.

## 11. Pelaporan & metrik kualitas

Laporan per milestone memuat: pass rate per area & kanal, cakupan traceability (FR/NFR tanpa TC = 0), defect per severity dan tren, escape rate dari pilot, latensi p95 per perangkat × reader, serta hasil `jev_gate`.

### 11.1 Hasil verifikasi — M1 tracer bullet sisi app (2026-11-01)

Lingkungan: branch `feat/r1-scaffold`, Xcode 27.2 (27B52), host macOS dan iOS Simulator 27.2 (iPhone 17 Pro); backend Go 1.27 + PostgreSQL 16 sementara (`go test ./...` di `backend/`). Hasil (setelah putaran perbaikan review akhir, iterasi 2 dan 3, lab end-to-end, dan perpanjangan sertifikat): 206 unit test lulus di host (termasuk 2 lint katalog string khusus host) dan 204 di simulator, dengan 1 test khusus perangkat dilewati; `python3 -I -m unittest discover -s scripts/anp1` 7 OK. "Logika lulus" berarti alur diuji terhadap reader ANP/1 perangkat lunak dan sesi/link palsu, **bukan** perangkat keras. Kasus bertipe H tetap tertunda sampai diuji di iPhone fisik dan reader.

| Kasus | Hasil | Bukti |
|---|---|---|
| TC-PROTO-01 | Lulus (sisi app dan backend Go) | `TestVectorTests` 7/7 (Swift) dan `internal/anp1` (Go) terhadap `anp1-v1.json` dari implementasi Python independen; uji mutasi HKDF/nonce gagal sesuai harapan di kedua sisi |
| TC-PROTO-02, TC-PROTO-09, TC-PROTO-12, TC-PROTO-14 | Lulus | `APDUTests`, `BLEFrameTests`, ukuran APDU vector < 255 B |
| TC-PROTO-03, TC-PROTO-08 | Logika lulus; I dengan reader referensi tertunda | `PhoneSessionTests.transaksiLengkapGranted`, `jalurGetCert` |
| TC-PROTO-04, TC-PROTO-05 | Lulus (respons identik, jumlah verifikasi ECDSA sama); ukur timing di HIL tertunda | `groupTakDikenalDanTandaTanganSalahIdentik`, `groupTakDikenalSamaBeratDenganTandaTanganSalah` |
| TC-PROTO-06, TC-PROTO-07 | Lulus | `replayAuth1DariTransaksiLamaDitolak`, `resultDimodifikasiDitolak` |
| TC-PROTO-13 | Sebagian: 10.000 APDU acak tanpa crash; fuzzing frame BLE belum | `fuzzApduTidakCrash` |
| TC-PRSN-01, TC-PRSN-03, TC-PRSN-04, TC-PRSN-05, TC-PRSN-15, TC-PRSN-16 | Logika lulus; H **tertunda** (entitlement HCE belum ada — D1, ADR-0017) | `HCEPresentmentTests` (11 test, 15× ulang tanpa gagal) |
| TC-PRSB-01 | **Tertunda** (H: butuh reader uji BLE) | — |
| TC-PRSB-02, TC-PRSB-03 | Logika lulus (panduan Bluetooth mati/izin ditolak); H tertunda | `bluetoothTidakTersediaMemberiPanduan`, `bluetoothDimatikanDiTengahTransaksiMemberiPanduan`, `bluetoothMatiAtauDitolakMemberiAlasanSpesifik` |
| TC-PRSB-04, TC-PRSB-05, TC-PRSB-06, TC-PRSB-07 | Logika lulus (termasuk pindai paralel dengan autentikasi, ADR-0019); H tertunda | `BLETapTests`, `BLESelectionTests`, `ScanWindowTests`, `pemindaianBerjalanSelamaAutentikasi` |
| TC-PRSB-08 | Logika lulus di link palsu (MTU 23); adapter live memotong frame sesuai ATT MTU − 3 (`.withoutResponse`). Uji di perangkat dengan MTU kecil tertunda | `mtuKecilTetapGrant` |
| TC-ELG-02 | Logika lulus | `GatingTests`, `gatingGagalTidakMembuatSesi` |
| TC-ELG-03 | Logika lulus: tanpa entitlement, gating mengembalikan `entitlementMissing` tanpa menyentuh API CardSession, dan build default (`AN_NFC_EMULATION = NO`) tidak mengaktifkan kanal N. Uji build tanpa entitlement di perangkat tertunda | `tanpaEntitlementTidakMenyentuhCardSession` |
| TC-ENR-11 | Lulus di app dan backend Go (409 `ENR-LIMIT`) | `kartuKesembilanDitolak`, `problemJsonDipetakan`, `TestBatasDelapanKartu`, `TestBatasKartuMenjadiENRLIMIT` |
| TC-ENR-12 | Lulus di backend: race dua permintaan saat 7 kartu → tepat satu sukses (`SELECT … FOR UPDATE`, PostgreSQL 16) | `TestRaceBatasDelapan` (10× ulang tanpa gagal) |
| TC-ENR-13 | **Tertunda** (iPhone fisik, `AN_DEVICE_TESTS=1`) | test tersedia, dilewati di simulator |
| Lab end-to-end app ↔ backend (bukan TC formal: langkah provisioning FR-16 dari TC-ENR-01, tanpa kartu fisik, OTP, dan App Attest) | Lulus di simulator: kartu dari backend dev tampil Aktif; DB berisi tepat 1 credential BLE `ACTIVE` untuk perangkat seed (sertifikat 188 B, berlaku 7 hari); peluncuran ulang tidak menambah kartu; build Release tanpa simbol lab (string katalog lab tetap ikut bundel sumber daya, tanpa efek runtime) | `provisionViaBackendMembuatKartuAktif`, `provisionViaBackendGagalTidakMenyisakanKunci`, `provisionViaBackendDitolakLokalSaatDelapanKartu`, `LabBackendLaunchTests`; `nm -a`/`strings -a` Debug vs Release |
| TC-DEV-09 | Logika lulus (ADR-0023): kedaluwarsa diperpanjang sebelum presentasi dengan batas 5 dtk lalu gagal tertutup; sisa < 50% diperpanjang setelah tap; backend menolak nonce terpakai, kedaluwarsa, atau lintas kredensial dan kredensial ditangguhkan. Lab simulator: sertifikat 1 hari diperpanjang menjadi 7 hari pada baris kredensial yang sama (jumlah kredensial tetap 1, sertifikat berganti), 1 nonce terpakai. Uji dengan Face ID nyata di perangkat tertunda | `RenewalSchedulerTests`, `CredentialRenewerTests`, `TestPerpanjanganMenerbitkanSertifikatBaru`, `TestNonceKredensialLainDitolak`, `TestKredensialDitangguhkanTidakDiperpanjang` |
| TC-DEV-10 | Logika lulus: kartu aktif dengan sisa < 24 jam atau yang sudah lewat tampil "Perlu diperbarui" (FR-38). Saat offline (`NWPathMonitor`), detail kartu menampilkan "Perlu terhubung ke internet"; saat online, petunjuk "diperbarui otomatis saat dipakai". Uji E di perangkat tertunda | `statusTampilanPerluDiperbarui`, `peringatanOfflineSaatPerluDiperbarui`, `tanpaPeringatanBilaMasihLama`, screenshot demo "Ruang Rapat 7" |
| TC-DEV-11 | Logika lulus: kartu kedaluwarsa yang punya backend penerbit tetap bisa di-tap, diperpanjang setelah autentikasi, lalu dipresentasikan; bila perpanjangan gagal (mis. offline) tap gagal tertutup. Kartu tanpa backend penerbit tetap nonaktif. Uji H tertunda | `kartuKedaluwarsaDariBackendBisaDipakai`, `kartuKedaluwarsaTanpaBackendTetapDitolak`, `kedaluwarsaYangBisaDiperpanjangTetapBisaDipakai`, `kedaluwarsaDiperpanjangSebelumPresentasi` |
| TC-ADM-06 | Lulus di backend (ADR-0024): baris yang diubah atau dihapus di tengah rantai (trigger dimatikan oleh DBA) terdeteksi di seq yang tepat; pemotongan ekor dan penghitungan ulang hash oleh pemegang akses tulis **tidak** terdeteksi tanpa anchoring (head per jam di log terpusat sebagai anchor parsial); data numerik/escape tetap terverifikasi (`TestAuditDataNumerikTetapTerverifikasi`); UUID huruf besar tidak membelah rantai (`TestEnrolmentHurufBesarSatuRantai`); UPDATE/DELETE/TRUNCATE lewat aplikasi ditolak; penambahan paralel di satu gedung tetap satu rantai; audit gagal membatalkan provisioning | `TestAuditManipulasiTerdeteksi`, `TestAuditTidakBisaDiubah`, `TestAuditBersamaanTetapBerantai`, `TestAuditGagalMembatalkanProvisioning`, `TestHashAuditVektor` |
| TC-ADM-07 | Lulus di backend: event enrolment, provisioning, dan perpanjangan hanya memuat `channel` dan `not_after`, tanpa lokasi atau data pribadi | `TestAuditTanpaDataPribadi`, `TestProvisioningDanRenewMencatatAudit` |
| TC-PRSN-17 | Lulus | `teksPresentasiTanpaJargon` |
| Temuan review C1/I1 (Face ID membuat scene `.inactive`; "Coba lagi") | Lulus: presentasi hanya dibatalkan saat `.background`; ganti item lembar tidak membatalkan presentasi baru | `inactiveTidakMembatalkanPresentasi`, `cobaLagiTidakMembatalkanPresentasiBaru`, `ketukGandaHanyaMemulaiSatuPresentasi` |

Kriteria keluar M1 (§2) **belum terpenuhi**: TC-PRSN-01 dan TC-PRSB-01 harus lulus di lab dengan perangkat keras.

## 12. Peran & jadwal

| Peran | Tanggung jawab |
|---|---|
| QA Lead | Rencana, gerbang milestone, laporan |
| QA Engineer (iOS) | Unit/integrasi/XCUITest, HIL |
| QA Engineer (backend) | Kontrak, beban, DR |
| Security Engineer | Pentest, MASVS, review kriptografi |
| Hardware QA | Reader R2/R3/R7, rig HIL, sertifikasi reader |
| Product | Acceptance test (AT-xx), keputusan risiko residual |

Jadwal mengikuti milestone PRD §13; uji pilot mencakup 2 lokasi (ADR-0011).

## 13. Checklist kepatuhan Apple

### 13.1 App Review — kanal N (O-A11)

- [ ] Build TestFlight pra-rilis
- [ ] Detail login uji
- [ ] ≥ 1 kredensial uji yang dapat di-provision dan dipakai untuk transaksi NFC
- [ ] Video/screenshot app dipakai di reader
- [ ] Video implementasi Presentment Intent Assertion
- [ ] Detail entitlement cocok dengan binary: AID `F0414E415354524F01` (HCE); konfigurasi applet di ABR (SE)
- [ ] Penghapusan akun dapat diinisiasi di app (5.1.1(v))
- [ ] Privacy Manifest & Nutrition Label akurat

### 13.2 Apple Wallet Access Program — kanal W (O-W12–O-W18)

- [ ] Provisioning In-App (dan/atau Web), transaksi NFC, lifecycle lengkap
- [ ] Semua reader terkait menerima mobile pass **dan** kartu fisik
- [ ] Reader: firmware dapat diperbarui, Aliro, ECP v2.3, TCI dari Apple, sertifikasi IOT
- [ ] s2s JWT/mTLS, TLS ≥ 1.2; lingkungan QA/Load/Prod
- [ ] DR multi-region, failover ≤ 30 menit, diuji bersama Apple
- [ ] SLA p90 < 2,2 dtk; uptime 99,99% production
- [ ] Log ≥ 25 hari; metrik 13–18 bulan; pembaruan sertifikat ≥ 30 hari; on-call P1 ≤ 15 menit
- [ ] Peran tim (sponsoring exec, signing authority, technical, prod technical, on-call) terisi
- [ ] Dukungan pelanggan & tooling untuk operator

## 14. Matriks traceability (PRD → kasus uji)

| Req | Kasus uji |
|---|---|
| FR-01 | TC-ELG-01, TC-ELG-02, TC-ELG-03 |
| FR-02 | TC-ELG-05 |
| FR-03 | TC-ACC-01, TC-ACC-02, TC-ACC-03 |
| FR-04 | TC-ELG-01, TC-ELG-04, TC-ELG-08 |
| FR-05 | TC-ELG-06, TC-ELG-07 |
| FR-06 | TC-ACC-05, TC-ACC-06, TC-PRIV-02 |
| FR-07 | TC-ACC-04 |
| FR-10 | TC-ENR-01 |
| FR-11 | TC-ENR-01, TC-ENR-14, TC-ENR-15 |
| FR-12 | TC-ENR-07, TC-ENR-08 |
| FR-13 | TC-ENR-04, TC-ENR-05, TC-ENR-06 |
| FR-14 | TC-ENR-01, TC-ENR-09, TC-ENR-10 |
| FR-15 | TC-ENR-11, TC-ENR-12 |
| FR-16 | TC-ENR-01, TC-ENR-13, TC-ENR-18 |
| FR-17 | TC-ENR-02 |
| FR-18 | TC-ENR-01, TC-ENR-02, TC-ENR-03, TC-SEC-09 |
| FR-19 | TC-ENR-16 |
| FR-20 | TC-PRSN-01, TC-PRSN-02, TC-PRSN-03, TC-PRSN-16, TC-PROTO-03 |
| FR-21 | TC-PRSN-05, TC-PRSN-06, TC-PRSN-08, TC-CMP-02 |
| FR-22 | TC-PRSN-04, TC-PRSN-07, TC-PRSN-15 |
| FR-23 | TC-PRSW-02, TC-PRSW-03, TC-PRSW-04, TC-PRSW-05 |
| FR-24 | TC-MGT-12 |
| FR-25 | TC-PRSN-10, TC-PROTO-08, TC-RDR-01, TC-RDR-06 |
| FR-26 | TC-PRSN-01, TC-PRSN-14, TC-PRSN-15, TC-PRSN-17, TC-UX-10 |
| FR-27 | TC-PRSN-11, TC-PRSW-03 |
| FR-28 | TC-PRSN-08, TC-PRSN-09 |
| FR-29 | TC-PRSN-12 |
| FR-30 | TC-MGT-01, TC-UPG-02 |
| FR-31 | TC-MGT-02 |
| FR-32 | TC-MGT-03 |
| FR-33 | TC-MGT-06, TC-MGT-08 |
| FR-34 | TC-MGT-07 |
| FR-35 | TC-MGT-09, TC-PRSW-10 |
| FR-36 | TC-MGT-10 |
| FR-37 | TC-MGT-13 |
| FR-38 | TC-MGT-11, TC-DEV-10 |
| FR-39 | TC-MGT-14 |
| FR-40 | TC-DEV-01, TC-UPG-01 |
| FR-41 | TC-DEV-02, TC-PRSW-09 |
| FR-42 | TC-DEV-03, TC-DEV-04, TC-DEV-05, TC-PRSW-07 |
| FR-43 | TC-DEV-05, TC-DEV-06 |
| FR-44 | TC-DEV-07, TC-DEV-08 |
| FR-45 | TC-DEV-09, TC-DEV-10, TC-DEV-11 |
| FR-46 | TC-DEV-12, TC-PRSW-06 |
| FR-50 | TC-ADM-01 |
| FR-51 | TC-ADM-03, TC-PRSN-13, TC-PRSW-08 |
| FR-52 | TC-ADM-04 |
| FR-53 | TC-ADM-05 |
| FR-54 | TC-ADM-06, TC-ADM-07 |
| FR-55 | TC-ADM-08, TC-ELG-07 |
| FR-56 | TC-ADM-01, TC-ADM-02 |
| FR-57 | TC-ADM-09, TC-RDR-09 |
| FR-58 | TC-ADM-10 |
| FR-59 | TC-ADM-11, TC-ENR-03 |
| FR-60 | TC-UX-08 |
| FR-61 | TC-UX-06, TC-UX-07 |
| FR-62 | TC-MGT-03, TC-PRIV-05 |
| FR-63 | TC-PRIV-06 |
| FR-64 | TC-ENR-06 |
| FR-70 | TC-PRSW-01 |
| FR-71 | TC-PRSW-07, TC-PRSW-08, TC-PRSW-11 |
| FR-72 | TC-PRSW-11 |
| FR-73 | TC-PRSW-12 |
| FR-80 | TC-PRSB-01, TC-PRSB-05, TC-PRSB-08, TC-PROTO-14 |
| FR-81 | TC-PRSB-07 |
| FR-82 | TC-PRSB-02, TC-PRSB-03 |
| FR-83 | TC-PRSB-04, TC-PRSB-05, TC-PRSB-06 |
| NFR-P01 | TC-PERF-01 |
| NFR-P02 | TC-PERF-02 |
| NFR-P03 | TC-PERF-03 |
| NFR-P04 | TC-PERF-04, TC-PRSB-01 |
| NFR-P05 | TC-PERF-05, TC-PERF-06 |
| NFR-R01 | TC-PERF-07 |
| NFR-R02 | TC-PERF-05, TC-DR-02, TC-DR-04 |
| NFR-R03 | TC-DR-01 |
| NFR-R04 | TC-DEV-03, TC-DEV-04, TC-DEV-11, TC-RDR-02, TC-RDR-04, TC-PERF-08, TC-DR-03 |
| NFR-S01 | TC-ENR-13 |
| NFR-S02 | TC-PROTO-01, TC-PROTO-02, TC-PROTO-04, TC-PROTO-05, TC-PROTO-06, TC-PROTO-07, TC-PROTO-11, TC-SEC-08 |
| NFR-S03 | TC-ENR-17, TC-SEC-05 |
| NFR-S04 | TC-SEC-04 |
| NFR-S05 | TC-MGT-04, TC-MGT-05, TC-SEC-10 |
| NFR-S06 | TC-SEC-02, TC-SEC-03 |
| NFR-S07 | TC-SEC-01 |
| NFR-S08 | TC-RDR-03, TC-RDR-05, TC-SEC-13, TC-SEC-14 |
| NFR-S09 | TC-SEC-06, TC-SEC-07, TC-SEC-11, TC-SEC-12, TC-PROTO-12, TC-PROTO-13, TC-RDR-08 |
| NFR-S10 | TC-ADM-02, TC-ADM-12 |
| NFR-PR01 | TC-ADM-07, TC-PRIV-04 |
| NFR-PR02 | TC-ENR-01, TC-ADM-04, TC-PRIV-01 |
| NFR-PR03 | TC-PRIV-02, TC-PRIV-07 |
| NFR-PR04 | TC-ACC-04, TC-PRIV-03, TC-SEC-07 |
| NFR-O01 | TC-PRIV-07 |
| NFR-O02 | TC-PERF-05 |
| NFR-CP01 | TC-ELG-05 |
| NFR-CP02 | TC-PROTO-09, TC-PROTO-10, TC-RDR-07, TC-UPG-03 |
| NFR-A01 | TC-UX-01, TC-UX-02, TC-UX-03, TC-UX-04, TC-UX-05, TC-UX-09, TC-ACC-02 |
| NFR-C01 | TC-CMP-01, TC-CMP-04, TC-UX-09 |
| NFR-C02 | TC-ELG-04, TC-CMP-03 |
| NFR-C03 | TC-CMP-05 |
| NFR-C04 | TC-ACC-05, TC-CMP-06 |
