# Alur Tambah Kartu produksi (FR-05, FR-10–FR-13) — desain

**Status:** fokus dari ADR-0043 (JEV 0,98), kode gedung dari ADR-0044 (JEV 0,96), dan perangkat yang dibuat saat enrolment dari ADR-0045 (JEV 0,77, Provisional). Pengguna memakai mode iterasi otomatis dan melewati sesi tanya-jawab; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

Build Release belum punya cara menambah kartu: tombol Tambah hanya ada di DEBUG dan membuka layar Lab. Backend sudah siap (registri, undangan, provisioning aman), tetapi penghuni pilot belum bisa memakainya. Iterasi ini membangun alur Tambah Kartu produksi untuk kanal N-HCE dan B, dengan dua jalur:

- **kartu fisik:** kode gedung, lalu tempel kartu;
- **tautan undangan.**

## Tujuan

1. **Menu (FR-10):** "Tambah Kartu Akses" ada di tab Kunci pada build Release, di toolbar dan di layar kosong. Menu nonaktif saat sudah ada 8 kartu (FR-15).
2. **Jalur kartu fisik (FR-11):** kode gedung → konfirmasi nama gedung → tempel kartu → enrolment → provisioning → kartu aktif.
3. **Jalur undangan (FR-12):** pengguna menempel tautan `https://<host>/i/<token>`, atau sistem membuka tautan itu lewat `onOpenURL`. Lalu enrolment dan provisioning.
4. **Kanal otomatis (FR-05):** irisan kanal yang diizinkan `/v1/config` dan kanal in-app R1 (N-HCE, B) yang bisa diprovisikan di perangkat. Urutan: N-HCE, lalu B.
5. **Alasan penolakan (FR-13, SDD §15):** pesannya spesifik. Untuk kartu tak terdaftar, kartu tak terbaca, dan perangkat yang tidak bisa membaca kartu, app menawarkan jalur undangan.
6. **Backend:** `sites.join_code`, `GET /v1/sites/lookup`, dan CLI `site-code` (ADR-0044); baris perangkat dibuat di transaksi enrolment (ADR-0045).

## Non-goal

- **App Attest (NFR-S03):** unit tersendiri karena butuh iPhone dan `DEVELOPMENT_TEAM`. Rilis pilot belum boleh berjalan tanpanya, dan ini dicatat sebagai terbuka di traceability.
- **Keanggotaan dan akun:** security code dan anggota (FR-14, FR-32–FR-36), akun/OTP (FR-03), perlindungan klaim (FR-18).
- **Kanal dan jalur lain:** kanal W dan N-SE, App Clip, pemindai QR di dalam app, serta entitlement Associated Domains dan berkas AASA (domain belum ada, SDD §5.6).
- **Jenis identitas lain:** FeliCa, yang butuh daftar system code per gedung di Info.plist, dan identitas `iso7816` berbasis AID.
- **Alur persetujuan:** kartu placeholder "Menunggu persetujuan" di daftar (tampilan FR-17), notifikasi persetujuan (FR-62), dan perpanjangan umur instance yang disetujui melewati 15 menit. Perpanjangan itu melebarkan jendela risiko ADR-0041, jadi masuk backlog.
- **Lainnya:** "Usulkan gedung saya" (FR-64) dan pembersihan item Keychain sisa instalasi lama.

## Anti-goal

- Identitas kartu fisik tersimpan atau tercatat di mana pun: state yang bertahan, log, pesan galat, UserDefaults, SwiftData, atau database server (aturan 6).
- Membaca apa pun dari kartu selain identifier. Tidak ada pembacaan sektor atau NDEF, autentikasi, penulisan, maupun emulasi (ADR-0001, aturan 1).
- Skema URL kustom untuk undangan, karena token sekali pakai bisa disadap app lain yang mendaftarkan skema yang sama.
- Enrolment yang memakan slot server padahal tidak ada kanal yang bisa diprovisikan.
- Endpoint lookup yang membedakan kode tak dikenal dan kode rusak.
- Baris perangkat tertinggal setelah enrolment ditolak.
- Kata "NFC" di teks alur ini (mengikuti pedoman teks presentasi, aturan 7).

## Backend

### Migrasi `0013`

`sites.join_code text NULL UNIQUE CHECK (join_code ~ '^[0-9A-HJKMNP-TV-Z]{8}$')`, yaitu alfabet Crockford base32 tanpa `I`, `L`, `O`, `U`.

### Kode gedung (ADR-0044)

- **CLI:** `anastrophe-registry site-code --site <uuid> --operator <pegangan>`.
  - Membuat kode baru dengan `crypto/rand` dan menggantikan kode lama, sehingga kode lama langsung tidak berlaku.
  - Mencetak `kode: XXXX-XXXX` ke stdout, plus peringatan rotasi ke stderr bila sebelumnya sudah ada kode.
  - Bentrok unik dicoba ulang.
  - Menulis audit `site.join_code_rotated` di rantai gedung, tanpa nilai kode (*keputusan builder*: kode bukan data pribadi, tetapi audit tidak membutuhkannya).
- **Endpoint:** `GET /v1/sites/lookup?code=<kode>`.
  - Kode dinormalisasi lebih dulu: huruf besar; `-` dan spasi dibuang; `O` dibaca `0`; `I` dan `L` dibaca `1`.
  - Hasil tepat 8 simbol dan dikenal → 200 `{"site_id": "<uuid>", "name": "<nama gedung>"}`.
  - Kode kosong, panjang salah, simbol di luar alfabet, atau tak dikenal → 404 `SITE-NOT-FOUND` dengan body identik.
  - Respons membawa `Cache-Control: no-store`. Tidak ada audit karena hanya membaca.
- **devseed:** membuat kode untuk gedung lab dan mencetak `join_code: XXXX-XXXX` untuk e2e.

### Perangkat (ADR-0045)

- `enrollCard` dan `enrollInvitation`: setelah validasi UUID, jalankan `INSERT INTO devices (id) VALUES ($1) ON CONFLICT (id) DO NOTHING` sebelum `lockDevice`, di transaksi yang sama.
- `StartEnrollment` (jalur tracer lama) tidak berubah.
- Enrolment yang ditolak me-rollback transaksi. Jalur Idempotency-Key juga tidak meng-commit respons 4xx.

### Katalog error (SDD §15)

| Kode | Kondisi | Pesan (ID) | Aksi |
|---|---|---|---|
| `SITE-NOT-FOUND` (404) | Kode gedung tak dikenal, kosong, atau tidak berbentuk sah; semuanya identik | "Kode gedung tidak dikenal. Periksa kode dari pengelola gedung." | Periksa ulang kode |

`ENR-UNREADABLE` sudah ada di katalog dan kini dipakai sisi app.

## App

### Konfigurasi dan identitas perangkat

- **Base URL API:** dibaca dari Info.plist `ANAPIBaseURL`, yang diisi build setting `AN_API_BASE_URL` di xcconfig dan kosong secara bawaan karena domain produksi belum ada.
  - Di DEBUG, argumen `-ANAPIBaseURL <url>` menimpanya untuk lab dan e2e.
  - Tanpa base URL, alur Tambah Kartu menampilkan "Layanan belum tersedia" dan tidak menghubungi jaringan (*keputusan builder*).
- **`DeviceIdentityStore` (ANStorage):**
  - `device_id` berupa UUID v4 di Keychain `afterFirstUnlockThisDeviceOnly`, dibuat saat pertama dibutuhkan.
  - `device_id` dibuat ulang bila penanda instalasi di Application Support (dikecualikan dari backup) tidak ada (ADR-0045, FR-43).
  - Nilainya tidak pernah ditampilkan atau di-log.

### Inti provisioning

- **`CardProvisioner` (ANFeatures, produksi):** isi `LabProvisioning.provisionViaBackend` dipindah ke sini, dan Lab memanggilnya.
  - Hasilnya `EnrollmentOutcome`: `.added(Card)` atau `.pendingApproval`.
  - Galat lain tetap dilempar.
- **Urutan sebelum enrolment:** batas 8 lokal (FR-15) → `/v1/config` → pemilihan kanal → kunci → rahasia enrolment (ADR-0040) → enrolment.
  - Bila tidak ada kanal yang bisa diprovisikan, dilempar `channelUnavailable` tanpa menghubungi `/v1/enrollments`.
- **Pemilihan kanal:** `ChannelSelector.preferred(allowedBySite: config ∩ {nfcHCE, ble}, availability:)`.
  - Untuk B, `bluetoothOff` dan `bluetoothUnauthorized` dianggap bisa diprovisikan (*keputusan builder*): provisioning tidak butuh radio, dan presentasi yang memberi panduan (FR-82).
- **`PENDING_APPROVAL`:** kunci lokal dan rahasia dibuang, dan tidak ada kartu lokal. UI menjelaskan langkah lanjutnya: tambah lagi setelah pengelola menyetujui, atau pakai tautan undangan dari pengelola (ADR-0035).

### Pembaca kartu

- **`NFCTagCardOwnershipReader` (ANNFCEnroll, iOS):**
  - Memeriksa `NFCReaderSession.readingAvailable` lebih dulu.
  - `NFCTagReaderSession` mem-polling ISO 14443 dan ISO 15693.
  - Pesan sistemnya "Tempelkan kartu ke bagian atas iPhone" (ID/EN, tanpa "NFC").
  - Hanya `identifier` yang dibaca. Satu kartu per sesi; bila lebih dari satu, pengguna diminta mengulang.
- **Pemetaan (fungsi murni yang ditest):**
  - MIFARE dan ISO 7816 tipe A → `iso14443a` (UID 4/7/10 byte).
  - ISO 15693 → `iso15693` (8 byte).
  - Panjang tidak sah atau jenis lain → tak terbaca.
- **Galat:**
  - `readingAvailable` false → `cardReaderUnavailable`.
  - Batas waktu sistem atau jenis kartu yang tidak didukung → `cardUnreadable`.
  - Dibatalkan pengguna → `CancellationError`, tanpa pesan.
- **DEBUG di simulator:** argumen `-ANLabCardReader <tech>:<hex>` mengganti pembaca dengan pembaca palsu yang mengembalikan identitas itu, untuk e2e.

### Model dan UI

- **`AddCardModel` (@Observable @MainActor):**
  - Langkah: `chooseMethod` → (`siteCode` → `confirmSite`) atau `invitation` → `working` → `done`/`pending`/`failed`.
  - Identitas kartu hanya hidup di dalam satu pemanggilan sebagai variabel lokal, tidak di state model.
  - Tombol aksi nonaktif selama permintaan berjalan dan menampilkan ProgressView, untuk mencegah ketuk ganda.
- **Pesan:** satu teks per galat (katalog SDD §15). Tawaran undangan muncul untuk `notRegistered`, `cardUnreadable`, dan `cardReaderUnavailable`.
- **`AddCardView` (sheet):** mengikuti `docs/design-system/anastrophe/pages/ios-app.md`.
  - Satu tindakan utama per layar.
  - Field kode punya label terlihat di atasnya, keyboard `asciiCapable`, dan huruf besar otomatis; galat tampil di dekat field.
  - SF Symbols, Dynamic Type, ID dan EN.
- **Tab Kunci:** tombol "Tambah Kartu Akses" (ikon `plus` dengan label VoiceOver) ada di toolbar dan layar kosong untuk semua build. Lab tetap DEBUG di toolbar terpisah.
- **`onOpenURL`:** URL `https` dengan path `/i/<token>` membuka sheet Tambah Kartu langsung di jalur undangan dengan token terisi; URL lain diabaikan. Di DEBUG, `-ANLabOpenURL <url>` memanggil jalur yang sama untuk e2e.

## Uji

- **Go:**
  - kode gedung: buat, rotasi, normalisasi, lookup, dan 404 identik;
  - baris perangkat dibuat saat enrolment kartu dan undangan berhasil;
  - tidak ada baris perangkat setelah penolakan, dengan dan tanpa Idempotency-Key;
  - CLI `site-code` dan keluaran devseed.
- **Swift:**
  - normalisasi kode;
  - `APIClient.lookupSite`;
  - `DeviceIdentityStore`;
  - hasil `CardProvisioner` dan pemilihan kanal;
  - transisi `AddCardModel`;
  - routing URL undangan;
  - pemetaan tag.
- **E2e di simulator:** devseed + API lokal, kode gedung lab, dan pembaca palsu.
  - Screenshot kartu aktif.
  - psql: baris perangkat baru dibuat oleh enrolment.
  - psql: enrolment kartu tak terdaftar tidak membuat baris.
  - Jalur undangan lewat `-ANLabOpenURL`.
- **Tipe H (iPhone + kartu):** pembacaan kartu live. Belum bisa dijalankan dan dicatat di QA.

## Review Focus

1. Identitas kartu tidak bertahan di state, log, atau pesan galat app; server tetap hanya menyimpan HMAC.
2. Enrolment yang ditolak (kartu tak terdaftar, gedung tak dikenal, undangan tidak sah, batas 8) tidak meninggalkan baris `devices`, juga lewat jalur Idempotency-Key.
3. Lookup menjawab identik untuk kode tak dikenal, rusak, kosong, atau bersimbol di luar alfabet; normalisasi app sama dengan server.
4. Ketuk ganda "Lanjutkan" atau "Tambah" hanya menghasilkan satu enrolment.
5. Instalasi baru membuat `device_id` baru; peluncuran berikutnya memakai yang sama.

## Diserahkan ke builder

Nama berkas dan fungsi, tata letak layar, nama kunci Keychain dan berkas penanda, serta format keluaran CLI selain baris `kode:`.
