# ADR-0046: Oracle tebak kartu pada enrolment menjadi gerbang pra-pilot (terbuka)

- **Status:** Tereskalasi (JEV 0,49). Diterapkan sebagian: hanya inti yang sama dari dua kandidat teratas (pencatatan ancaman dan gerbang pra-pilot), tanpa perubahan perilaku. Pilihan kontrolnya menunggu pengguna.
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** NFR-S03, NFR-S09, FR-11, ADR-0031, ADR-0032, ADR-0041, ADR-0044, ADR-0045

## Konteks

Review akhir alur Tambah Kartu (temuan #1) menunjukkan bahwa `POST /v1/enrollments` kini menjadi oracle tebakan identitas kartu tanpa autentikasi:

- **`site_id` publik:** kode gedung di poster membuka `site_id` (ADR-0044).
- **`device_id` bebas:** `device_id` acak apa pun diterima (ADR-0045). Sebelumnya perangkat tak dikenal ditolak `ENR-NOT-FOUND` sebelum pencocokan kartu.
- **Ruang tebakan kecil:** identitas ISO 14443A 4 byte hanya 2^32 nilai. Dengan R kartu terdaftar, satu tebakan benar butuh ±2^32/R percobaan, misalnya ±2,1 juta untuk R = 2.000.
- **Dampak tebakan benar:** untuk kartu yang belum pernah didaftarkan, tebakan benar dijawab `PROVISIONING` (perangkat pertama, ADR-0032), jadi penyerang bisa memprovisikan kredensial dengan zona kartu itu.
- **Tanpa jejak:** percobaan yang ditolak tidak meninggalkan baris, audit, atau log, dan belum ada pembatas laju.

Backend belum di-deploy dan pilot belum mulai. App Attest (NFR-S03) belum diterapkan.

## Hasil JEV

- **Hasil:** `deteksi_per_gedung` · confidence **0.49** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round31.input.json`](jev-log/2026-11-02-round31.input.json), [`jev-log/2026-11-02-round31.output.json`](jev-log/2026-11-02-round31.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `deteksi_per_gedung` | 0.56 | ketiganya *supported* |
| `catat_gerbang_pra_pilot` | 0.33 | DoS lintas penghuni: *unknown* |
| `batas_per_ip` | 0 | butuh konfigurasi proxy yang belum ada |
| `batas_per_gedung` | 0 | membuka DoS lintas penghuni |

## Keputusan

Confidence di bawah 0,60, jadi pilihan kontrol diserahkan ke pengguna (ADR-0018). Inti yang sama dari dua kandidat teratas, yang tidak mengubah perilaku, diterapkan sekarang:

- Ancaman dicatat di SDD §10.1 dan QA (TC-SEC-15, pending).
- **Gerbang wajib sebelum pilot:** App Attest (NFR-S03) ditambah pembatas atau deteksi kegagalan enrolment kartu (`ENR-NOT-REGISTERED`). Desainnya menunggu keputusan pengguna, misalnya deteksi per gedung tanpa identitas, pembatas per perangkat yang di-attest, atau keduanya.

**Rekomendasi penulis:** deteksi per gedung, yaitu hitungan `ENR-NOT-REGISTERED` per gedung dalam jendela geser dengan log peringatan tanpa identitas, dipasang bersama App Attest. Deteksi ini tidak memblokir siapa pun, dan pembatas dipasang per perangkat yang sudah di-attest, bukan per gedung, agar tidak membuka DoS lintas penghuni.

## Konsekuensi

- Sampai gerbang ini ditutup, backend tidak boleh dibuka ke internet untuk pilot.
- Pertanyaan ini tidak diajukan ulang ke JEV tanpa bukti baru, misalnya desain App Attest atau topologi deploy.
