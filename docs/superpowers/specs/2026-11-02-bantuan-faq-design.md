# Layar Bantuan dan FAQ in-app (FR-60, FR-02, FR-27, FR-63) — desain

**Status:** fokus dari ADR-0048 (JEV 0,99). Pengguna memakai mode iterasi otomatis dan melewati sesi tanya-jawab; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

Penghuni kini bisa menambah dan memakai kartu, tetapi app belum menjelaskan hal-hal yang paling sering ditanyakan: iPhone mana yang didukung, mengapa kartu tidak bisa dipakai saat iPhone terkunci, apa yang terjadi bila ponsel hilang, dan sebagainya. Samsung punya FAQ resmi untuk fitur padanannya (E01). Iterasi ini menambah layar Bantuan yang menjawabnya sesuai perilaku app saat ini, ditambah laporan diagnostik yang bisa dibagikan tanpa membocorkan rahasia.

## Tujuan

1. **Pintu masuk:** tombol "Bantuan" (ikon `questionmark.circle` dengan label VoiceOver) di toolbar tab Kunci, untuk semua build.
2. **FAQ (FR-60):** sepuluh topik, yaitu perangkat didukung, kartu didukung, batas 8 kartu, offline, layar terkunci, hapus kartu, anggota, berbagi, pindah perangkat, dan ponsel hilang. Jawaban ditulis dalam ID dan EN, sesuai perilaku R1.
3. **Per kanal:** bagian "Cara akses di iPhone ini" menampilkan status "Tempel ke pembaca" dan "Bluetooth" dari kelayakan perangkat, memakai teks alasan yang sudah ada (mis. "Bluetooth mati…").
4. **Perangkat didukung (FR-02):** iPhone 11 dan yang lebih baru serta iPhone SE generasi 2 dan 3, dengan iOS 26 atau lebih baru (ADR-0006, O-D01, O-D02). "Tempel ke pembaca" hanya tersedia di wilayah tertentu dan bila gedung mendukungnya (O-A08); Bluetooth tidak bergantung wilayah.
5. **Layar terkunci (FR-27):** kartu di app tidak bisa dipakai saat iPhone terkunci, layar mati, atau baterai habis. Pengguna perlu membuka app, memilih kartu, lalu Face ID/Touch ID/kode sandi (I-05, O-S10).
6. **Diagnostik (FR-63, P1):** tombol "Bagikan laporan diagnostik" (lembar bagikan sistem) dengan teks yang dibuat di perangkat tanpa jaringan.
   - Isinya: versi app dan build, versi iOS, bahasa, status kanal, layanan terkonfigurasi atau tidak, jumlah kartu, serta per kartu status, kanal, dan tanggal berlaku.
   - Tanpa nama kartu (*keputusan builder*: nama gedung bukan rahasia, tetapi tidak dibutuhkan untuk diagnosis).
7. **Dukungan:** "Untuk kartu dan akses gedung, hubungi pengelola gedung Anda." Kanal dukungan Anastrophe belum ditetapkan.

## Non-goal

- Kanal dukungan Anastrophe (email/obrolan), formulir "Usulkan gedung saya" (FR-64), App Clip, dan konten FAQ dari server.
- Anggota, pindah perangkat, dan Lost Mode/portal "tangguhkan semua". FAQ menjawab perilaku sekarang tanpa menjanjikan fitur.
- Kanal W (Apple Wallet, R2) di bagian per kanal.

## Anti-goal

- Laporan diagnostik yang memuat `cred_id`, id kartu server, `device_id` (ADR-0041), token baca status, rahasia enrolment, identitas kartu fisik, kontak, kunci, sertifikat, atau URL lengkap layanan.
- Teks Bantuan yang memakai istilah teknis "NFC", "HCE", atau "APDU" (sejalan dengan aturan teks presentasi).
- Jawaban yang menjanjikan fitur yang belum ada, atau bertentangan dengan perilaku app (mis. menyebut kartu bisa dipakai saat terkunci).
- Layar Bantuan yang menghubungi jaringan.

## Desain

- **`HelpContent` (ANFeatures):** daftar topik FAQ berurutan, dengan kunci katalog `help.faq.<topik>.question`/`.answer`. Daftar perangkat didukung ditaruh sebagai teks katalog `help.devices.*`.
- **`DiagnosticsReport` (ANFeatures):** fungsi murni dari `DiagnosticsInput` ke teks.
  - Input: versi app dan build, versi OS, bahasa, kelayakan per kanal, layanan terkonfigurasi, dan ringkasan kartu (status, kanal, `notAfter`).
  - Ringkasan kartu sengaja tidak membawa id atau kunci, jadi rahasia tidak mungkin ikut walau pemanggil salah.
- **`HelpView` (sheet dari tab Kunci):** `List` dengan bagian "Cara akses di iPhone ini", "Pertanyaan umum" (`DisclosureGroup` per topik), "iPhone yang didukung", "Diagnostik" (`ShareLink`), dan "Dukungan". Mengikuti `pages/ios-app.md`: Dynamic Type, VoiceOver, SF Symbols, mode gelap/terang.
- **Ketersediaan kanal:** dibaca dari `services.availability()` saat layar dibuka. Teks memakai pemetaan alasan yang sudah dipakai detail kartu bila memungkinkan.
- **DEBUG:** `-ANDemoScreen help` membuka Bantuan untuk verifikasi visual.

## Uji

- FAQ mencakup kesepuluh topik FR-60, setiap topik punya teks ID dan EN, dan semua kunci `help.*` bebas jargon (TC-UX-08).
- Laporan diagnostik memuat bidang yang diizinkan dan tidak memuat hex `cred_id`, id kartu server, `device_id`, token, atau identitas kartu walau store berisi semuanya (TC-PRIV-06).
- Pemetaan status kanal mencakup tersedia, Bluetooth mati, Bluetooth belum diizinkan, dan tidak eligible.
- Screenshot simulator ID dan EN lewat `-ANDemoScreen help`.

## Review Focus

1. Laporan diagnostik tanpa rahasia di semua jalur: banyak kartu, kartu tanpa kanal, store gagal dibuka.
2. Jawaban FAQ akurat terhadap perilaku saat ini: batas 8, perpanjangan saat online, layar terkunci, hapus kartu, persetujuan perangkat tambahan.
3. Status kanal per iPhone mengikuti kelayakan (Bluetooth mati/ditolak, wilayah tidak eligible, build tanpa emulasi).
4. Aksesibilitas: teks panjang di `DisclosureGroup` terbaca di AX5, dan tombol ikon berlabel.
5. Tidak ada istilah teknis di teks Bantuan dalam kedua bahasa.

## Diserahkan ke builder

Nama berkas dan fungsi, tata letak, susunan kata final jawaban FAQ (sesuai isi di atas), dan format teks laporan.
