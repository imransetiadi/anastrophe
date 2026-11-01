# PRD — Anastrophe: Kartu Akses NFC untuk iPhone

| Item | Nilai |
|---|---|
| Nama produk | **Anastrophe** (identitas visual in-app tidak boleh mirip Apple Wallet/Apple Pay — O-A10) |
| Versi dokumen | 2.1 (Draft untuk review) |
| Tanggal | 2026-11-01 |
| Pemilik dokumen | Product Owner — TBD |
| Referensi fitur | Samsung Wallet *NFC Access Card* (E01) |
| Dokumen terkait | [SDD](SDD.md) · [QA Suite](QA_SUITE.md) · [Research Evidence](research/RESEARCH_EVIDENCE.md) · [ADR](adr/README.md) · [Glosarium](../GLOSSARY.md) · [Design system](design-system/anastrophe/MASTER.md) |
| Lapisan keputusan | **JEV** (`jev_decide`, TypeSafe) — keputusan desain beserta probabilitas & cek requirement di `docs/adr/` (ADR-0018) |

### Riwayat versi

| Versi | Tanggal | Ringkasan perubahan |
|---|---|---|
| 1.0 | 2026-11-01 | Draft awal: model kredensial diterbitkan operator, satu jalur NFC in-app. |
| 2.0 | 2026-11-01 | Strategi **tiga kanal** (Apple Wallet/Aliro, NFC in-app, BLE); min. iOS 26; requirement baru: hapus akun (5.1.1(v)), perlindungan klaim pemilik, perpanjangan sertifikat, perubahan passcode/biometrik, SSO/MFA admin, armada reader; user story + kriteria penerimaan; roadmap per rilis (R1/R2); risiko & metrik diperbarui. |
| 2.1 | 2026-11-01 | Keputusan terbuka diputuskan lewat **JEV** (ADR-0002–ADR-0017): pilot ganda ID + SG/MY, reader referensi, pengajuan Apple Wallet Access Program di M0. Dua keputusan dieskalasi ke manusia: entitas hukum (ADR-0017) dan topologi backend (ADR-0014). Ditambahkan design system (skill UI/UX Pro Max) dan glosarium domain. |
| 2.2 | 2026-11-01 | ADR-0014 dan ADR-0019 (strategi pindai BLE) diterima atas keputusan pengguna; FR-01 diselaraskan dengan SDK (O-A24). Tersisa satu eskalasi: ADR-0017. |

> **Konvensi (metode REA):**
> `OBS` = meniru perilaku Samsung yang teramati di sumber (ID observation disebut).
> `DES` = keputusan desain untuk iOS (bukan perilaku Samsung), biasanya karena batasan platform.
> ID bukti (E/O/I/U) merujuk ke `docs/research/RESEARCH_EVIDENCE.md`.
> Kode kanal: **W** = Apple Wallet Access pass, **N** = NFC dalam aplikasi (**N-SE** `CredentialSession` / **N-HCE** `CardSession`), **B** = BLE dalam aplikasi.

---

## 1. Ringkasan eksekutif

Samsung Wallet memungkinkan pengguna Galaxy menyimpan hingga 8 kartu akses NFC (gedung, apartemen, kampus, lift, parkir) dengan menempelkan kartu fisik ke ponsel (O-S01, O-S04, O-S05). **Anastrophe** menghadirkan pengalaman setara untuk iPhone.

Hasil riset yang membentuk produk ini:

1. **iPhone tidak bisa meng-clone kartu fisik.** UID iPhone diacak per tap, dan app hanya dapat mengemulasikan ISO 7816-4 lewat AID terdaftar (I-02, I-11). Karena itu Anastrophe menerbitkan **kredensial digital baru yang disetujui operator gedung**. Kartu fisik dipakai sebagai **bukti kepemilikan** saat enrolment (I-04).
2. **Ada tiga kanal resmi** untuk mempresentasikan kredensial dari iPhone. Masing-masing punya syarat dan cakupan wilayah berbeda (§5):
   - **W — Apple Wallet Access pass** (Aliro/DESFire/Seos). UX paling mirip Samsung, bahkan lebih baik: Express Mode, power reserve, Apple Watch (I-08). Syaratnya kemitraan dengan Apple.
   - **N — NFC dalam aplikasi**: `CredentialSession` di wilayah eligible (HK/MY/SG/TW/VN, dll.) atau `CardSession` di EEA (O-A01, O-A08, O-A17).
   - **B — BLE dalam aplikasi**: berlaku di semua wilayah, **termasuk Indonesia** (I-06, I-13).
3. **Indonesia belum eligible** untuk NFC in-app (cek live 2026-11-01, E13), dan Apple Pay belum tersedia di Indonesia (O-P02).

**Keputusan (via JEV):** platform dibangun agnostik kanal. **Rilis R1 (MVP)** = kanal N + B (ADR-0002), dengan **pilot ganda**: Indonesia (B) dan Singapura/Malaysia (N + B) (ADR-0011). **Rilis R2** = kanal W (Apple Wallet Access Program + Aliro); pengajuan ke Apple dimulai **sekarang** di M0 (ADR-0008).

> ⚠️ **Butuh keputusan manusia:** entitlement NFC & SE mensyaratkan pengembang *established* di wilayah eligible (E03). Perusahaan Indonesia perlu entitas, misalnya di Singapura/Malaysia, atau publisher mitra. JEV memilih *escape* `investigate` (ADR-0017).

## 2. Latar belakang & masalah

- Penghuni/karyawan membawa banyak kartu plastik, sering lupa atau kehilangan, dan cetak ulang kartu ada biayanya.
- Pengguna iPhone tidak punya padanan fitur Samsung ini. Apple Wallet badge hanya tersedia bila operator bekerja sama dengan mitra program Apple (O-A15, E09, E21).
- Operator gedung ingin mengurangi biaya kartu fisik dan mendapat kontrol jarak jauh (suspend/revoke, audit) yang tidak dimiliki kartu plastik.
- Ekosistem reader terfragmentasi. Standar **Aliro 1.0** (Feb 2026) mulai menyatukannya (O-L01, O-L02), sehingga ada momentum bagi gedung untuk memperbarui reader.

## 3. Tujuan, metrik, dan non-tujuan

### 3.1 Tujuan & metrik keberhasilan

| ID | Tujuan | Metrik | Sumber data | Target |
|---|---|---|---|---|
| G1 | Pengguna iPhone membuka akses dengan iPhone | Tap berhasil pada percobaan pertama (per kanal, reader tersertifikasi) | Log ACS/reader | ≥ 95% |
| G2 | Enrolment cepat | Median waktu "Tambah kartu" → kartu aktif (tanpa persetujuan admin) | Event app `enroll_*` | ≤ 90 detik |
| G3 | Aman | Insiden kredensial terkloning; brute-force security code yang lolos | Pentest, audit, rate-limit log | 0 / 0 |
| G4 | Kontrol operator | Waktu efektif pencabutan: reader online / offline | Event revoke vs penolakan pertama di reader | ≤ 60 dtk / ≤ interval sinkron (default 15 mnt), selalu ≤ masa berlaku sertifikat |
| G5 | Adopsi | Penghuni pemilik iPhone di gedung pilot yang aktif (≥ 1 tap/minggu) | Event backend + ACS | ≥ 30% dalam 90 hari |
| G6 | Kualitas app | Crash-free sessions | MetricKit/crash reporting | ≥ 99,8% |

### 3.2 Non-tujuan

- **NG1 —** Tidak meng-clone UID / MIFARE Classic / data sektor kartu fisik ke iPhone (I-02, I-11). Selain tidak didukung iOS, ini juga berisiko secara keamanan dan legal.
- **NG2 —** Tidak mendukung reader yang hanya membaca UID/CSN atau reader 125 kHz. Gedung seperti itu diarahkan ke penggantian reader atau reader transparan + gateway (I-11, I-12).
- **NG3 —** Tidak ada pembayaran, transit, atau kartu identitas pemerintah.
- **NG4 —** Tidak ada Android di proyek ini (Android sudah punya HCE terbuka dan Wallet sendiri).
- **NG5 —** Tidak ada aplikasi Apple Watch untuk kanal N/B (`CardSession` tidak tersedia di watchOS). Apple Watch hanya didukung lewat kanal W, karena Wallet mem-provision Watch otomatis (O-W05).
- **NG6 —** Tidak menjamin dukungan di gedung tanpa kerja sama operator. Anastrophe adalah produk B2B2C.

## 4. Persona

| Persona | Deskripsi | Kebutuhan utama |
|---|---|---|
| P1 Pemegang utama (Primary) | Penghuni/karyawan pemilik kartu fisik | Tambah kartu cepat, buka pintu dengan iPhone, kelola anggota |
| P2 Anggota (Member) | Keluarga/rekan yang berhak memakai kartu yang sama | Bergabung dengan security code dari P1 |
| P3 Admin gedung | Building management / facility | Menyetujui, suspend, revoke, audit, kebijakan |
| P4 Security officer | Tim keamanan operator | Audit read-only, investigasi insiden |
| P5 Integrator / vendor ACS | Pemasok reader & controller | Integrasi API, konfigurasi reader, armada perangkat |
| P6 Tim dukungan Anastrophe | Helpdesk | Diagnostik, sengketa klaim |

## 5. Strategi kanal kredensial

### 5.1 Perbandingan kanal

| Aspek | **W — Apple Wallet Access** | **N — NFC in-app** | **B — BLE in-app** |
|---|---|---|---|
| Teknologi | Access pass di Wallet; kredensial Aliro (disarankan), DESFire, atau Seos di Secure Element (O-W01, O-W02) | N-SE: applet Anastrophe di Secure Element via `CredentialSession` (O-A17–O-A21). N-HCE: `CardSession` (O-A01) | GATT kustom + kunci di Secure Enclave |
| Protokol ke reader | Aliro (atau DESFire/Seos) + ECP v2.3/TCI | **ANP/1** (protokol Anastrophe, AID `F0414E415354524F01`) | ANP/1 lewat GATT |
| UX pemakaian | Tanpa buka app: Express Mode, Auto-Presentment, power reserve, Apple Watch (O-W06) | Buka app/widget → pilih kartu → autentikasi → tempel | Buka app/widget → dekatkan (jarak pendek); hands-free opsional (P2) |
| Saat terkunci/baterai rendah | Ya (Express, power reserve) | Tidak | Tidak (kecuali hands-free opt-in, P2) |
| Syarat Apple | Diterima di Apple Wallet Access Program + ABR + sertifikasi IOT reader + SLA 99,99% (O-W12–O-W18) | Entitlement NFC & SE Platform (N-SE) atau HCE (N-HCE) + perjanjian dengan operator (O-A07) | Tidak ada entitlement khusus |
| Syarat reader | ECP v2.3 + TCI Apple + teknologi kredensial (O-W07) | ISO 14443-4 + AID ANP/1 (native atau transparan + gateway, I-12) | Modul BLE + firmware ANP/1 |
| Wilayah | Belum diketahui (U07); Indonesia berisiko (I-14) | N-SE: wilayah eligible (O-A08); N-HCE: EEA | Semua |
| Waktu ke pasar | Panjang (diligence + sertifikasi) | Sedang (entitlement, review applet untuk N-SE) | Cepat |

### 5.2 Ketersediaan per wilayah (per 2026-11-01)

| Wilayah | W | N-SE | N-HCE | B |
|---|---|---|---|---|
| Singapura, Malaysia, Hong Kong, Taiwan | U07 | ✓ (O-A08) | — | ✓ |
| Vietnam | U07 | ✓ | — | ✓ |
| EEA (mis. Jerman, Belanda) | U07 | — | ✓ (O-A01) | ✓ |
| AU, JP, UK, US, CA, NZ | U07 | ✓ | — | ✓ |
| **Indonesia** | U07 (berisiko, I-14) | — (U02) | — | ✓ |
| Thailand, Filipina | U07 | — | — | ✓ |

### 5.3 Keputusan rilis

| Rilis | Kanal | Pasar | Alasan |
|---|---|---|---|
| **R1 (MVP)** | **N + B** (ADR-0002) | Pilot ganda: 1 gedung Indonesia (B) + 1 gedung Singapura/Malaysia (N + B) (ADR-0011) | Bisa dikendalikan tim, tidak bergantung jadwal program Apple Wallet, dan mencakup Indonesia lewat B |
| **R2** | **W** (Aliro) | Wilayah tempat Apple menerima Anastrophe | Paritas UX tertinggi (I-08); diajukan ke Apple sejak M0 (ADR-0008) |

Pemilihan kanal per kartu otomatis (FR-05) dengan prioritas **W > N > B**, mengikuti ketersediaan dan kebijakan gedung.

## 6. Requirement fungsional

Prioritas: **P0** wajib untuk rilisnya, **P1** sebaiknya ada, **P2** pasca-rilis. Kolom "Kanal": W/N/B/Semua.

### 6.1 Akun, onboarding, kelayakan

| ID | Requirement | Kanal | Asal | Prio |
|---|---|---|---|---|
| FR-01 | App memeriksa kelayakan per kanal sebelum menampilkan fitur: `NFCReaderSession.readingAvailable`; `CardSession.isSupported` + `await CardSession.isEligible` (N-HCE); `try await CredentialSession.isEligible` (N-SE, O-A24); kemampuan menambah pass Secure Element (W); status & izin Bluetooth (B). Fitur yang tidak eligible disembunyikan, dan alasannya ditampilkan dengan bahasa awam. | Semua | DES (O-A10, O-A17, O-W20) | P0 |
| FR-02 | Minimum **iOS 26.0**, iPhone 11 ke atas dan iPhone SE gen 2 ke atas (ADR-0006). Daftar perangkat ada di halaman Bantuan (padanan daftar perangkat Samsung). | Semua | OBS O-S02 → DES (O-D01, O-D02) | P0 |
| FR-03 | Akun: Sign in with Apple, lalu verifikasi OTP nomor telepon/email. OTP mendukung autofill (`oneTimeCode`) dan paste sesuai WCAG 2.2 *Accessible Authentication*. Kontak terverifikasi dipakai untuk mencocokkan registri pemegang kartu (FR-18). | Semua | DES | P0 |
| FR-04 | Gating wilayah & kanal dari server (`/config`), berdasarkan storefront, wilayah akun, kebijakan gedung, dan status entitlement/program. | Semua | DES (O-A08, O-P02, I-06) | P0 |
| FR-05 | Satu alur "Tambah kartu". App memilih kanal terbaik yang tersedia (W > N > B) per kartu, sesuai kebijakan gedung dan kemampuan perangkat. Kanal aktif terlihat di detail kartu. | Semua | DES | P0 |
| FR-06 | **Hapus akun** dapat diinisiasi dari dalam app. Semua kredensial dicabut, pass Wallet dinonaktifkan, dan data pribadi dihapus/dipseudonimkan sesuai NFR-PR03. | Semua | DES (O-P01) | P0 |
| FR-07 | Persetujuan kebijakan privasi & ketentuan saat onboarding; analitik bersifat opt-in. | Semua | DES | P0 |

### 6.2 Tambah kartu (enrolment)

| ID | Requirement | Kanal | Asal | Prio |
|---|---|---|---|---|
| FR-10 | Menu "Tambah Kartu Akses" di tab **Kunci**. | Semua | OBS O-S05 | P0 |
| FR-11 | **Enrolment via kartu fisik.** Pengguna menempelkan kartu ke bagian atas iPhone. App membaca identitas kartu via `NFCTagReaderSession`: UID untuk ISO 14443A/15693/FeliCa, atau ID aplikasi via `SELECT` AID untuk kartu ISO 7816/DESFire yang terdaftar. Identitas dicocokkan dengan registri gedung (HMAC di server), lalu server menerbitkan **kredensial baru**. Kartu tidak di-clone. | Semua | OBS O-S05 (UX) + DES (I-02, I-04) | P0 |
| FR-12 | **Enrolment via undangan** (link/QR, token sekali pakai) dari admin, untuk kartu yang tidak terbaca atau gedung tanpa registri kartu. App Clip untuk undangan bersifat P2. | Semua | DES | P0 |
| FR-13 | Kartu yang tidak didukung disaring **saat penambahan**, dengan alasan spesifik: tidak terdaftar, tidak terbaca, kartu 125 kHz/tidak ada respons, atau gedung belum mendukung. Pengguna lalu ditawari jalur undangan. | Semua | OBS O-S03 + DES (I-11) | P0 |
| FR-14 | Pemegang pertama membuat **security code 6 digit** (konfirmasi 2×; kode lemah seperti `000000`/`123456` ditolak). | Semua | OBS O-S05 | P0 |
| FR-15 | Maksimum **8 kartu aktif per perangkat**, ditegakkan di app **dan** server. Untuk kanal W, batas perangkat per pass = 1 iPhone, ditambah Apple Watch yang berpasangan. | Semua | OBS O-S04 + DES (O-W05) | P0 |
| FR-16 | Provisioning kredensial per kanal. W: *Add to Apple Wallet* (In-App Provisioning). N-SE: instal applet lalu personalisasi lewat mode wired. N-HCE/B: kunci di Secure Enclave + sertifikat dari Site CA. | Semua | DES (O-A19, O-W05) | P0 |
| FR-17 | Persetujuan admin opsional per gedung. Status kartu "Menunggu persetujuan" sampai disetujui. | Semua | DES | P1 |
| FR-18 | **Perlindungan klaim pemegang utama** (ADR-0004). Peran PRIMARY hanya diberikan bila kontak terverifikasi pengguna cocok dengan pemegang di registri. Jika tidak cocok, kartu masuk persetujuan admin. Pemegang sah dapat melapor "Saya pemilik kartu ini" sebagai sengketa (FR-59). | Semua | DES (ancaman *enrolment hijack*) | P0 |
| FR-19 | Enrolment yang terputus dapat dilanjutkan dalam 15 menit. Tidak boleh ada kredensial yatim. | Semua | DES | P1 |

### 6.3 Pemakaian (presentasi ke reader)

| ID | Requirement | Kanal | Asal | Prio |
|---|---|---|---|---|
| FR-20 | Kanal N: dari daftar kartu, pengguna memilih kartu, lalu otorisasi berjalan. N-SE memakai UI otorisasi sistem (O-A20); N-HCE memakai Face ID/Touch ID/passcode oleh app. Setelah itu emulasi dimulai dan pengguna menempelkan iPhone ke reader. | N | OBS O-S07 (adaptasi) + DES | P0 |
| FR-21 | Presentment intent assertion hanya diambil saat ada intent aktif pengguna. Batasnya dipatuhi: 15 detik + cooldown 15 detik (N-HCE, O-A05), dan maks 2 assertion per 80 detik (N-SE, O-A21). | N | DES | P0 |
| FR-22 | Batas sesi: emulasi N-HCE ≤ 60 detik dengan hitung mundur dan tombol "Coba lagi" (O-A03). Sesi N-SE yang diinvalidasi saat app ke background dipulihkan dengan benar (O-A18). | N | DES | P0 |
| FR-23 | Kanal W: Express Mode aktif default, Auto-Presentment lewat TCI, dan power reserve. TRA diaktifkan untuk zona berisiko tinggi sesuai kebijakan gedung (O-W06). | W | OBS O-S07/O-S17 → DES | P0 (R2) |
| FR-24 | Akses cepat untuk kanal N/B: widget Lock Screen, kontrol Control Center, dan App Shortcut/Siri ("Buka kartu Lobi"). Kanal W memakai tombol "Buka di Wallet". | Semua | DES (padanan Quick Access) | P1 |
| FR-25 | Presentasi berfungsi **offline**, tanpa data seluler/Wi-Fi. | Semua | OBS O-S09 | P0 |
| FR-26 | Umpan balik jelas: status sukses/gagal (`.success`/`.failure`, O-A22), haptic, dan teks awam ("Dekatkan bagian atas iPhone ke pembaca kartu"). Teks presentasi tidak memakai istilah "NFC". | Semua | DES (O-A10, E05) | P0 |
| FR-27 | Saat terkunci/layar mati/baterai habis: kanal N/B **tidak** dapat dipakai tanpa membuka app dan autentikasi (setara O-S10). Kanal W mendukung Express Mode dan power reserve. Perilaku ini dijelaskan di FAQ. | Semua | OBS O-S10 + DES (I-05, O-W06) | P0 |
| FR-28 | Berdampingan dengan Apple Pay, Apple Wallet, dan app NFC lain. App tidak memblokir mereka di luar intent aktif. | Semua | OBS O-S06 | P0 |
| FR-29 | Pemilihan kartu otomatis berdasarkan *reader group* yang diumumkan reader, tanpa membocorkan daftar gedung milik pengguna. | N, B | DES | P1 |
| FR-80 | Kanal B "Tap": dengan app atau widget aktif, iPhone didekatkan ke reader (ambang RSSI per reader, ±30 cm), lalu akses dibuka. | B | DES (O-B01) | P0 |
| FR-81 | Kanal B *hands-free* di background (opt-in, eksperimental). App dibangunkan Core Bluetooth (filter service UUID) di dekat reader berprofil "proximity", hanya bila kebijakan gedung mengizinkan. **Ditunda dari R1** (ADR-0012). | B | DES (O-B04, U11) | P2 |
| FR-82 | Kanal B: izin Bluetooth diminta dengan penjelasan konteks. Kondisi Bluetooth mati atau izin ditolak ditangani dengan panduan. | B | DES | P0 |
| FR-83 | Kanal B anti-buka-tidak-sengaja: hanya reader dengan RSSI tertinggi di atas ambang yang diproses, maksimal 1 transaksi per 3 detik per reader, dengan konfirmasi visual/haptic. | B | DES | P1 |

### 6.4 Manajemen kartu & anggota

| ID | Requirement | Kanal | Asal | Prio |
|---|---|---|---|---|
| FR-30 | Detail kartu menampilkan nama, gedung, zona, status, kanal, perangkat, masa berlaku sertifikat (N/B), dan riwayat tap lokal 30 hari (N/B). | Semua | OBS O-S11 | P0 |
| FR-31 | **Hapus kartu**: Detail → Pengaturan → Hapus, dengan konfirmasi + autentikasi. Kredensial dicabut di ACS; untuk kanal W, pass dinonaktifkan lewat Apple Access Platform. | Semua | OBS O-S11 | P0 |
| FR-32 | **Anggota** bergabung dengan security code pemilik, memakai kartu fisik yang sama atau undangan dari pemilik. Pemilik menerima notifikasi. | Semua | OBS O-S12 | P0 |
| FR-33 | Pemilik utama melihat dan menghapus anggota. Anggota tidak dapat mengelola anggota lain. | Semua | OBS O-S13 | P0 |
| FR-34 | Pemilik utama mengganti security code (autentikasi + kode lama). Anggota yang sudah ada tetap aktif. | Semua | OBS O-S13 | P0 |
| FR-35 | Tidak ada share/forward kredensial di luar mekanisme anggota. Untuk kanal W, izin *sharing* Wallet **dinonaktifkan**; anggota kanal W bergabung lewat security code di app (ADR-0013, O-W11). | Semua | OBS O-S14 + DES | P0 |
| FR-36 | Batas anggota per kartu dikonfigurasi gedung (default 4, provisional — ADR-0015). | Semua | DES | P1 |
| FR-37 | Rename kartu dan pilih warna, hanya untuk tampilan in-app. Tampilan pass Wallet mengikuti template Apple (O-W01). | N, B | DES (O-A10) | P2 |
| FR-38 | Status kartu jelas: Aktif, Menunggu persetujuan, Ditangguhkan, Perlu diperbarui, Dicabut. | Semua | DES | P0 |
| FR-39 | Kebijakan kartu fisik ditampilkan: kartu fisik tetap berlaku kecuali operator mencabutnya. | Semua | DES | P2 |

### 6.5 Perangkat, kehilangan, lifecycle

| ID | Requirement | Kanal | Asal | Prio |
|---|---|---|---|---|
| FR-40 | Kredensial **terikat perangkat**: tidak ikut iCloud Backup/restore dan tidak pindah lewat login di perangkat lain. | Semua | OBS O-S15 | P0 |
| FR-41 | **Pindah perangkat.** Kanal N/B: login di iPhone baru → "Pindahkan kartu" (OTP + App Attest) → kredensial baru diterbitkan dan yang lama dicabut. Kanal W: *Easy Provisioning* dari Wallet selama kredensial aktif (O-W09). Ini padanan Smart Switch. | Semua | OBS O-S15 → DES | P0 |
| FR-42 | **Ponsel hilang.** (a) Find My Lost Mode: pass W otomatis ditangguhkan via Apple (O-W09); kredensial N/B tidak dapat dipakai tanpa autentikasi. (b) Erase via Find My menghapus kunci. (c) Portal web "Tangguhkan semua kartu saya". (d) Admin gedung dapat suspend. | Semua | OBS O-S16 → DES | P0 |
| FR-43 | Reinstall app atau hapus data app membuat kredensial N/B tidak dapat dipakai. Server menandai UNREACHABLE; pengguna melakukan transfer atau enrolment ulang. | N, B | OBS O-S16 (analog) | P0 |
| FR-44 | Perubahan keamanan perangkat. Bila passcode dimatikan, kunci in-app terhapus dan pass Wallet ikut terhapus (O-W10); app mendeteksinya dan menawarkan pemulihan. Perubahan Face ID/Touch ID **tidak** membatalkan kredensial (ADR-0009). | Semua | DES | P0 |
| FR-45 | **Perpanjangan sertifikat otomatis** untuk kanal N/B. Masa berlaku default 7 hari (ADR-0010; dapat diatur 1–30 hari per gedung); diperpanjang saat sisa < 50% dan perangkat online. Peringatan "Perlu terhubung ke internet" muncul bila sisa < 24 jam. | N, B | DES | P0 |
| FR-46 | Satu kredensial per pengguna per kartu per iPhone. Untuk kanal W, Apple Watch mendapat kredensial terpisah secara otomatis (O-W05) dan dicatat terpisah di audit. | Semua | DES | P1 |

### 6.6 Portal admin (web)

| ID | Requirement | Prio |
|---|---|---|
| FR-50 | Daftar kredensial per gedung, dengan filter status/kanal dan pencarian. | P0 |
| FR-51 | Approve / suspend / resume / revoke, termasuk lewat Apple Access Platform untuk kanal W (O-W09). | P0 |
| FR-52 | Impor registri kartu fisik (CSV atau API ACS). Identitas kartu dan kontak pemegang langsung di-HMAC saat impor; tiap kartu dipetakan ke zona. | P0 |
| FR-53 | Undangan via email/SMS/QR: token sekali pakai, dengan masa kedaluwarsa. | P0 |
| FR-54 | Audit log tak terubah (siapa, apa, kapan), tanpa lokasi GPS pengguna. | P0 |
| FR-55 | Kebijakan gedung: maksimal anggota, wajib persetujuan, wajib kecocokan pemegang (FR-18), masa berlaku sertifikat (1–30 hari), interval sinkron reader, kanal yang diizinkan, dan TRA per zona. | P0 |
| FR-56 | Keamanan portal: SSO (OIDC/SAML) + MFA wajib (passkey/WebAuthn disarankan). RBAC: Org Owner, Site Admin, Security Officer (read-only audit), Helpdesk (suspend/resume), Integrator (armada reader). | P0 |
| FR-57 | Manajemen armada reader/gateway: status online, versi firmware, sinkron terakhir, rotasi kunci reader group. | P1 |
| FR-58 | Laporan & ekspor: kredensial aktif per kanal, adopsi, kegagalan tap (dari ACS), audit. | P1 |
| FR-59 | Antrean sengketa klaim kartu (FR-18). Keputusan tercatat, dengan opsi memindahkan peran PRIMARY dan mencabut kredensial pihak lain. | P0 |

### 6.7 Notifikasi, bantuan, lokalisasi

| ID | Requirement | Prio |
|---|---|---|
| FR-60 | FAQ in-app setara FAQ Samsung, disesuaikan per kanal: perangkat didukung, kartu didukung, maks 8, offline, layar terkunci, hapus, anggota, sharing, pindah perangkat, hilang (E01). | P0 |
| FR-61 | Bahasa Indonesia dan Inggris (P0). Tionghoa Tradisional dan Melayu P1, menjadi P0 bila pilot di HK/MY. | P0/P1 |
| FR-62 | Notifikasi push untuk anggota baru, kartu ditangguhkan/dicabut, perlu online untuk perpanjangan, dan persetujuan selesai. Payload tidak berisi data sensitif. | P0 |
| FR-63 | Bantuan & diagnostik: kontak dukungan dan ekspor laporan diagnostik **tanpa rahasia** (versi, kanal, status, kode error). | P1 |
| FR-64 | "Usulkan gedung saya": formulir minat bila gedung belum mendukung Anastrophe. | P2 |

### 6.8 Integrasi Apple Wallet (kanal W, rilis R2)

| ID | Requirement | Asal | Prio |
|---|---|---|---|
| FR-70 | Tombol **Add to Apple Wallet** (In-App Provisioning) di akhir enrolment bila kanal W tersedia. Status pass ditampilkan di app (`PKSecureElementPass.passActivationState`). | O-W05, O-W20 | P0 (R2) |
| FR-71 | Sinkronisasi lifecycle dua arah dengan Apple Access Platform: update, suspend/resume, remove, dan notifikasi dari Apple. | O-W09 | P0 (R2) |
| FR-72 | Desain pass memakai template Apple per vertikal (corporate/multi-family/student); card art gedung dikelola via ABR. | O-W01 | P1 (R2) |
| FR-73 | Web Provisioning sebagai alternatif untuk pengguna tanpa app. | O-W05 | P2 |

## 7. User story & kriteria penerimaan

Versi Gherkin lengkap ada di QA Suite §6 (AT-xx).

| ID | User story | Kriteria penerimaan (ringkas) | FR |
|---|---|---|---|
| US-01 | Sebagai penghuni, saya ingin menambah kartu akses dengan menempelkan kartu fisik agar bisa masuk gedung memakai iPhone. | Kartu terdaftar terbaca → gedung & zona tampil → buat code → kartu Aktif ≤ 90 dtk. UID mentah tidak tersimpan. | FR-10, 11, 14, 16 |
| US-02 | Sebagai penghuni, saya ingin tahu kenapa kartu saya tidak bisa ditambahkan. | Pesan spesifik per alasan (tidak terdaftar/tidak terbaca/125 kHz/gedung belum mendukung) + tawaran undangan. | FR-13 |
| US-03 | Sebagai pemegang sah, saya tidak ingin orang lain yang meminjam kartu saya menjadi pemilik utama. | Kontak tidak cocok registri → status Menunggu persetujuan; pemegang sah bisa melapor; admin memutuskan. | FR-18, 59 |
| US-04 | Sebagai anggota keluarga, saya ingin bergabung ke kartu pemilik dengan security code. | Code benar → Anggota aktif + pemilik dinotifikasi. Salah 5× → terkunci 30 menit. | FR-32, NFR-S05 |
| US-05 | Sebagai pengguna di gedung kanal N, saya ingin membuka pintu dengan menempelkan iPhone. | Pilih kartu → autentikasi → tempel → reader grant ≤ 500 ms (p95); Apple Pay tidak muncul. | FR-20, 21, 26, 28 |
| US-06 | Sebagai pengguna di Indonesia (kanal B), saya ingin membuka pintu dengan iPhone. | Buka widget/app → dekatkan → grant ≤ 1,5 dtk (p95); Bluetooth mati → panduan. | FR-80, 82 |
| US-07 | Sebagai pengguna kanal W, saya ingin membuka pintu tanpa membuka app atau Face ID. | Express aktif → tempel iPhone terkunci → grant; reader TRA → minta autentikasi. | FR-23, 70 |
| US-08 | Sebagai pengguna yang ganti iPhone, saya ingin memindahkan kartu tanpa ke kantor manajemen. | Transfer (N/B) atau Easy Provisioning (W) berhasil; kredensial lama ditolak di reader. | FR-41 |
| US-09 | Sebagai pengguna yang kehilangan iPhone, saya ingin menangguhkan semua kartu dari web. | Portal → "Tangguhkan semua" → reader online menolak ≤ 60 dtk. | FR-42, G4 |
| US-10 | Sebagai pengguna, saya ingin menghapus akun saya dari dalam app. | Hapus akun → semua kredensial dicabut → data pribadi dihapus ≤ 30 hari. | FR-06 |
| US-11 | Sebagai admin gedung, saya ingin mencabut akses penghuni yang pindah. | Revoke → status Dicabut → reader online menolak ≤ 60 dtk; tercatat di audit. | FR-51, 54 |
| US-12 | Sebagai pengguna yang jarang online, saya ingin tahu kapan kartu perlu diperbarui. | Sisa sertifikat < 24 jam → peringatan; setelah online → diperpanjang otomatis. | FR-45, 38 |

## 8. UX & konten

**Design system:** [`design-system/anastrophe/MASTER.md`](design-system/anastrophe/MASTER.md) untuk portal admin web, dan override iOS [`pages/ios-app.md`](design-system/anastrophe/pages/ios-app.md) untuk app. Keduanya dihasilkan dengan skill UI/UX Pro Max: gaya *Minimalism & Swiss*, palet *trust navy* + aksen gold dengan kontras WCAG AA terverifikasi, SF Pro + Dynamic Type, SF Symbols, target sentuh 44 pt.

**Inventaris layar:** Onboarding (SIWA, OTP, persetujuan) · Daftar Kunci · Detail Kartu · Alur Tambah Kartu (pilih gedung/scan QR → baca kartu → konfirmasi → security code → provisioning → selesai/Add to Apple Wallet) · Lembar Presentasi (N: hitung mundur; B: status kedekatan) · Anggota · Pengaturan (akun, hapus akun, notifikasi, analitik) · Bantuan/FAQ · Diagnostik.

**Aturan konten:**
- Gunakan bahasa awam, misalnya "Dekatkan bagian atas iPhone ke pembaca kartu"; jangan pakai "NFC", "HCE", "APDU" (E05).
- Tombol pass Wallet hanya memakai aset resmi *Add to Apple Wallet* sesuai pedoman Apple. UI in-app tidak boleh meniru tampilan Wallet/Apple Pay (O-A10).
- Pesan error harus bisa ditindaklanjuti. Katalog error ada di SDD §15.

**Aksesibilitas:** VoiceOver mengumumkan status presentasi; Dynamic Type sampai ukuran aksesibilitas terbesar; kontras WCAG AA; Reduce Motion dihormati.

## 9. Requirement non-fungsional

| ID | Kategori | Requirement |
|---|---|---|
| NFR-P01 | Performa | Kanal N: transaksi reader (SELECT → RESULT) ≤ **500 ms** p95 pada iPhone 11 dengan reader referensi (selaras target Aliro, O-L03). |
| NFR-P02 | Performa | Kanal N: dari ketuk kartu hingga siap ditempel (termasuk autentikasi) ≤ 2 dtk p95. |
| NFR-P03 | Performa | Cold start app ≤ 1,5 dtk p95 (iPhone 11). |
| NFR-P04 | Performa | Kanal B: dari intent pengguna (app/widget di foreground) hingga keputusan reader ≤ 1,5 dtk p95. |
| NFR-P05 | Performa | API app p95 ≤ 300 ms. Endpoint yang dipanggil Apple Access Platform p90 < 2,2 dtk (O-W15). |
| NFR-R01 | Keandalan | Tap berhasil ≥ 95% pada percobaan pertama dan ≥ 99% dalam dua percobaan, per kanal, di reader tersertifikasi. |
| NFR-R02 | Ketersediaan | Backend 99,9% (R1); **99,99% production** setelah kanal W aktif (O-W15). Kegagalan backend tidak menghalangi presentasi offline. |
| NFR-R03 | DR | RTO ≤ 30 menit; RPO ≤ 5 menit; uji DR per kuartal, dan bersama Apple untuk kanal W (O-W14). Topologi R1 (multi-region hot standby vs satu region multi-AZ) **menunggu keputusan manusia** (ADR-0014); untuk R2 multi-region wajib. |
| NFR-R04 | Pencabutan | Reader online ≤ 60 dtk; reader offline ≤ interval sinkron (default 15 menit) dan selalu dibatasi masa berlaku sertifikat (default 7 hari). |
| NFR-S01 | Keamanan | Kunci privat kredensial tidak pernah keluar dari Secure Enclave/SE; tidak dapat diekspor maupun di-backup. |
| NFR-S02 | Keamanan | Setiap transaksi memakai ECDH ephemeral + tanda tangan (anti-replay, *forward secrecy*). UID tidak pernah dipakai sebagai faktor otentikasi. Identitas kredensial tidak diungkap sebelum reader terautentikasi. |
| NFR-S03 | Keamanan | App Attest wajib untuk enrolment, provisioning, dan transfer; perangkat yang gagal attestation ditolak. |
| NFR-S04 | Keamanan | Security code disimpan di server sebagai hash Argon2id + salt; tidak pernah disimpan di perangkat. |
| NFR-S05 | Keamanan | Rate-limit security code: 5 salah → terkunci 30 menit; 10 salah/24 jam → terkunci + notifikasi pemilik. |
| NFR-S06 | Keamanan | TLS 1.3 untuk API app dengan certificate pinning. Token akses 15 menit, refresh token terikat perangkat. Server-to-server dengan Apple: JWT/mTLS, TLS ≥ 1.2 (O-W13). |
| NFR-S07 | Keamanan | Mitigasi relay: intent eksplisit + autentikasi pengguna (N/B); batas waktu respons di reader yang dikalibrasi lewat HIL (U06); TRA untuk zona berisiko (W). |
| NFR-S08 | Keamanan | Manajemen kunci: Site CA di HSM, kunci reader group di SE/TPM reader atau gateway. Rotasi: Site CA 2 tahun, reader group 1 tahun, rotasi darurat ≤ 24 jam. Sertifikat layanan diperbarui otomatis ≥ 30 hari sebelum kedaluwarsa (O-W16). |
| NFR-S09 | Keamanan | Secure SDLC: SAST, pemindaian dependensi, pentest eksternal sebelum pilot dan sebelum GA. Target OWASP MASVS L2 + R. |
| NFR-S10 | Keamanan | Portal admin: SSO + MFA, idle timeout 15 menit, semua aksi sensitif tercatat di audit. |
| NFR-PR01 | Privasi | Tidak mengumpulkan lokasi GPS. Log tap berasal dari ACS, bukan dari app. Patuh UU PDP (UU 27/2022) dan GDPR (EEA). |
| NFR-PR02 | Privasi | Identitas kartu fisik dan kontak pemegang disimpan hanya sebagai HMAC dengan kunci per gedung. |
| NFR-PR03 | Privasi | Retensi: audit 1 tahun (dapat diatur ≤ 5 tahun bila diwajibkan hukum); log aplikasi 30 hari (≥ 25 hari, O-W16); metrik 18 bulan. Data akun yang dihapus dimusnahkan ≤ 30 hari; audit dipseudonimkan. |
| NFR-PR04 | Privasi | Privacy Nutrition Label dan Privacy Manifest akurat; tanpa tracking lintas app (ATT tidak dipakai). |
| NFR-O01 | Operasional | Log terpusat (≥ 25 hari), metrik, alert, on-call; respons insiden P1 ≤ 15 menit (O-W16). |
| NFR-O02 | Operasional | Lingkungan: Dev, QA, Load, Staging, Production (O-W13). |
| NFR-CP01 | Kompatibilitas | iOS 26.0+; iPhone 11+/SE 2+; mendukung dua versi mayor iOS terakhir (N dan N-1). |
| NFR-CP02 | Kompatibilitas | Daftar reader tersertifikasi per kanal. W: ECP v2.3 + sertifikasi IOT Apple. N: AID ANP/1 native atau transparan + gateway. B: profil GATT ANP/1. |
| NFR-A01 | Aksesibilitas | VoiceOver, Dynamic Type (hingga AX5), kontras WCAG AA (token terverifikasi di design system), target sentuh ≥ 44 pt, haptic, Reduce Motion. |
| NFR-C01 | Kepatuhan | Pedoman desain Apple (O-A10); materi App Review lengkap (O-A11). |
| NFR-C02 | Kepatuhan | Kanal hanya aktif di wilayah eligible (O-A08, FR-04). |
| NFR-C03 | Kepatuhan | Semua persyaratan Apple Wallet Access Program terpenuhi sebelum kanal W diluncurkan (O-W12–O-W18). |
| NFR-C04 | Kepatuhan | Penghapusan akun dapat diinisiasi di dalam app (O-P01). |

## 10. Analitik & metrik produk

Event app (opt-in, tanpa PII): `onboarding_completed`, `eligibility_resolved{channel_set}`, `enroll_started{method}`, `enroll_card_read{result}`, `enroll_completed{channel, duration_s}`, `enroll_failed{reason}`, `presentment_started{channel}`, `presentment_result{channel, outcome, duration_ms}`, `cert_renewed`, `cert_expiring_warning`, `member_joined`, `code_lockout`, `device_transfer{result}`, `account_deleted`.

KPI dashboard: G1–G6, adopsi per kanal, distribusi alasan gagal enrolment, waktu propagasi pencabutan (G4), rasio kartu "Perlu diperbarui".

## 11. Ketergantungan & asumsi

| ID | Ketergantungan / asumsi | Rujukan |
|---|---|---|
| D1 | Entitlement NFC & SE Platform (N-SE) atau HCE (N-HCE) disetujui untuk use case *Corporate Badge / Home Keys / Student ID*. | O-A06, O-A07 |
| D2 | Perjanjian mengikat dengan operator gedung (syarat Apple untuk N dan W). | O-A07, O-W03 |
| D3 | Reader gedung mendukung ANP/1 (N/B), atau reader transparan + gateway (I-12), atau Aliro + ECP v2.3 (W). | U03, O-W07 |
| D4 | Untuk N-SE: applet lolos review lab independen dan diterima Apple. | O-A06 |
| D5 | Untuk W: Anastrophe diterima di Apple Wallet Access Program sebagai Credential Manager (dan Credential Provider untuk Aliro). | O-W03, O-W18, U07 |
| D6 | Integrasi API dengan ACS/panel mitra untuk sinkronisasi hak akses. | — |
| A1 | Pilot ganda: 1 gedung Indonesia (kanal B) + 1 gedung Singapura/Malaysia (kanal N + B) (ADR-0011). | O-A08, I-06 |
| D7 | Entitas/akun Apple Developer *established* di wilayah eligible untuk entitlement NFC & SE (ADR-0017, **terbuka**). | E03 |
| D8 | Kapabilitas hardware untuk reader referensi NFC + BLE: desain, produksi pilot, sertifikasi radio lokal (ADR-0016). | O-R01 |
| A2 | Model komersial: B2B per kredensial aktif/bulan dibayar operator; gratis untuk pengguna akhir; paket reader/gateway referensi opsional. | — |

## 12. Risiko

| ID | Risiko | Kemungkinan | Dampak | Mitigasi | Pemilik |
|---|---|---|---|---|---|
| R1 | Indonesia tidak eligible NFC in-app | Tinggi | Tinggi | Kanal B di ID; pilot N di SG/MY/HK; ajukan kanal W; pantau U02 | Product |
| R2 | Entitlement N ditolak/tertunda | Sedang | Tinggi | Ajukan bersama operator; siapkan kebijakan keamanan & privasi (E03); kanal B tetap jalan | BD/Legal |
| R3 | Tidak diterima di Apple Wallet Access Program atau tidak tersedia di wilayah target | Sedang | Sedang | R1 tidak bergantung pada W; bermitra dengan vendor yang sudah jadi Credential Provider | BD |
| R4 | Reader legacy tidak mendukung AID kustom/Aliro/ECP | Tinggi | Tinggi | Daftar reader tersertifikasi; OSDP Transparent Mode + gateway (I-12); reader referensi dual NFC+BLE | Hardware |
| R5 | Ekspektasi "tinggal tempel seperti Samsung" | Tinggi | Sedang | Enrolment via kartu fisik terasa serupa (FR-11); edukasi; kanal W untuk Express | Product/UX |
| R6 | Batas 60 dtk / UI modal / batas assertion mengganggu UX | Sedang | Rendah | Hitung mundur, retry, dan state machine yang patuh (FR-21, FR-22) | iOS |
| R7 | Relay attack | Rendah | Tinggi | NFR-S07; TRA untuk zona sensitif | Security |
| R8 | Biaya program Apple (U04, U12) | Sedang | Sedang | Masukkan ke model harga B2B | Finance |
| R9 | Keandalan BLE di background rendah (U11) | Sedang | Sedang | MVP hanya "Tap" di foreground; hands-free P2 setelah uji lapangan | iOS |
| R10 | Beban SLA 99,99% + DR untuk kanal W | Sedang | Sedang | Arsitektur multi-region sejak R1 (NFR-R03) | Backend/SRE |
| R11 | Penyalahgunaan klaim kartu (enrolment hijack) | Sedang | Tinggi | FR-18, FR-59; notifikasi pemegang | Security |
| R12 | Perubahan kebijakan Apple (wilayah, API) | Sedang | Sedang | Gating dari server (FR-04); pantau dokumen E03/E21 tiap kuartal | Product |
| R13 | Tidak ada entitas di wilayah eligible, sehingga entitlement NFC & SE tidak bisa diajukan | Tinggi | Tinggi | Putuskan ADR-0017 di M0 (legal/finance); pilot B di Indonesia tetap jalan | Legal/BD |
| R14 | Kapabilitas hardware reader referensi (jadwal, sertifikasi radio) | Sedang | Tinggi | Desain berbasis modul bersertifikat; jalur alternatif gateway OSDP transparan (ADR-0016) | Hardware |

## 13. Rilis & milestone

| Milestone | Durasi | Isi | Kriteria keluar |
|---|---|---|---|
| M0 Discovery & kemitraan | 6 mgg | Survei reader gedung (U03); **putuskan entitas hukum (ADR-0017)**; ajukan entitlement N; kirim kuesioner Apple Wallet Access Program (ADR-0008, U07); kontrak 2 operator pilot (ADR-0011); mulai desain reader referensi (ADR-0016); putuskan topologi backend (ADR-0014) | 2 operator pilot tanda tangan; ADR-0014 & ADR-0017 diputuskan; entitlement development diterima (N) |
| M1 Prototype | 6 mgg | ANP/1 lewat HCE (entitlement dev, O-A13) dan BLE; reader/gateway referensi; backend minimal | Tap N dan B berhasil di lab; test vector protokol lulus |
| M2 MVP (R1) | 12 mgg | Semua P0 kanal N + B; portal admin; sinkron reader | Kriteria keluar QA Suite §4 terpenuhi |
| M3 Pilot (R1) | 8 mgg | 1–2 gedung (SG/MY/HK: N+B; ID: B) | G1, G2 tercapai; tanpa defect S1/S2 |
| M4 GA (R1) | — | P1 R1; rilis App Store | App Review lulus |
| M5 Kanal W (R2) | Mengikuti Apple | Integrasi Apple Access Platform, Aliro, sertifikasi IOT reader, E2E dengan Apple | NFR-C03 terpenuhi; uji bersama Apple lulus |

## 14. Pemangku kepentingan (RACI ringkas)

| Aktivitas | Product | iOS | Backend/SRE | Hardware | Security | QA | Legal/Privacy | BD |
|---|---|---|---|---|---|---|---|---|
| Prioritas & scope | A/R | C | C | C | C | C | C | C |
| Entitlement & program Apple | A | C | C | C | C | I | R | R |
| Protokol ANP/1 | C | R | R | R | A | C | I | I |
| Reader/gateway | C | C | C | A/R | C | C | I | C |
| Privasi & retensi | C | C | R | I | C | I | A | I |
| Rilis | A | R | R | R | C | R | C | I |

(R = Responsible, A = Accountable, C = Consulted, I = Informed)

## 15. Keputusan & pertanyaan terbuka

Keputusan diambil lewat lapisan keputusan **JEV** (ADR-0018). Status mengikuti confidence JEV: ≥ 0,80 diterima, 0,60–0,80 provisional, < 0,60 atau escape → eskalasi ke manusia.

| # | Pertanyaan | Keputusan | Status | ADR |
|---|---|---|---|---|
| 1 | Wilayah pilot R1? | Pilot ganda: Indonesia (B) + Singapura/Malaysia (N + B) | Diterima (0,84) | ADR-0011 |
| 2 | Strategi reader pilot? | Reader referensi Anastrophe NFC + BLE; gateway OSDP transparan sebagai jalur retrofit | Provisional (0,66) | ADR-0016 |
| 3 | Kapan mengajukan Apple Wallet Access Program? | Sekarang (M0), paralel dengan R1 | Diterima (1,0) | ADR-0008 |
| 4 | Default batas anggota & masa berlaku sertifikat? | 4 anggota; 7 hari | Provisional (0,65 / 0,78) | ADR-0015, ADR-0010 |
| 5 | Mekanisme anggota di kanal W? | Security code di app; Wallet sharing nonaktif | Diterima (0,89) | ADR-0013 |
| 6 | BLE hands-free di R1? | Ditunda (P2); R1 hanya Tap | Diterima (1,0) | ADR-0012 |
| 7 | **Entitas hukum untuk entitlement NFC & SE?** | — (JEV: `investigate`) | **Eskalasi ke manusia** — butuh legal/finance | ADR-0017 |
| 8 | Topologi backend R1? | Multi-region primary + hot standby (JEV 0,48) | Diterima — keputusan pengguna setelah eskalasi | ADR-0014 |
| 9 | Strategi pemindaian BLE Tap (NFR-P04)? | Pindai saat lembar dibuka + early exit (JEV 0,51) | Diterima — keputusan pengguna setelah eskalasi | ADR-0019 |

## 16. Lampiran A — Pemetaan fitur Samsung → Anastrophe

| Fitur Samsung (bukti) | Kanal W | Kanal N | Kanal B |
|---|---|---|---|
| Tempel kartu fisik → kartu digital (O-S05) | Verifikasi kepemilikan → *Add to Apple Wallet* (FR-11, FR-70) | Verifikasi kepemilikan → kredensial in-app (FR-11, FR-16) | Sama dengan N |
| Maks 8 kartu (O-S04) | Batas 8 per perangkat + batas perangkat per pass (FR-15) | 8 (FR-15) | 8 (FR-15) |
| Kartu terenkripsi tidak didukung (O-S03) | Ditentukan registri gedung (FR-13) | Sama | Sama |
| Security code & anggota (O-S05, O-S12, O-S13) | Security code di app (FR-32–FR-34); opsi Wallet sharing (P2) | FR-32–FR-34 | FR-32–FR-34 |
| Tidak bisa share (O-S14) | Sharing nonaktif default (FR-35) | Tidak ada share (FR-35) | Tidak ada share |
| Quick Access (O-S07) | Express Mode + Auto-Presentment (FR-23) — lebih baik | Widget/kontrol/shortcut (FR-24) | Widget/kontrol (FR-24, FR-80) |
| Offline (O-S09) | Ya (FR-25) | Ya | Ya |
| Tidak bisa saat layar mati/terkunci (O-S10) | **Bisa** (Express, power reserve) | Tidak (FR-27) | Tidak; hands-free opt-in P2 (FR-81) |
| Berdampingan dengan Smart Octopus (O-S06) | Berdampingan dengan kartu Wallet lain | Berdampingan dengan Apple Pay (FR-28) | Sama |
| Terikat perangkat; Smart Switch (O-S15) | Easy Provisioning (FR-41) | Re-provision (FR-41) | Re-provision (FR-41) |
| SmartThings Find (O-S16) | Find My Lost Mode → suspend otomatis (FR-42) | Find My Erase + portal (FR-42) | Sama dengan N |
| NFC ON + eSE (O-S08) | Tidak relevan | Tidak relevan | Bluetooth harus aktif (FR-82) |

## 17. Lampiran B — Glosarium

Glosarium kanonis (bahasa domain bersama PRD/SDD/QA/kode) ada di [`GLOSSARY.md`](../GLOSSARY.md), dikelola dengan skill `domain-modeling`. Istilah kunci: **Kanal** (W/N/B), **Kartu (digital)**, **Kredensial**, **Reader group**, **Site CA**, **ANP/1**, **Pemegang utama**, **Anggota**, **Security code**, **Sengketa klaim**.
