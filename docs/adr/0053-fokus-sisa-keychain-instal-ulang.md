# ADR-0053: Fokus berikutnya: bersihkan sisa Keychain saat instal ulang (FR-43 sebagian)

- **Status:** Tereskalasi (JEV 0,39).
  - **Diterapkan:** `instal_ulang_fr43`, pilihan JEV. Unit ini berisiko rendah, bisa dibatalkan, dan tidak membawa semantik keamanan baru, karena FR-43 sudah ditetapkan di PRD. Dasarnya persetujuan umum pengguna, dengan pola yang sama seperti ADR-0042.
  - **Menunggu pengguna:** penyambungan App Attest (seri di 0,47).
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-43, FR-40, ADR-0009, ADR-0045, ADR-0052, ADR-0041, ADR-0046, TC-ENR-23

## Konteks

Sesudah app dihapus lalu dipasang lagi, kartu ikut hilang karena metadata SwiftData ada di Application Support, dan device id dibuat ulang (ADR-0045). Namun item Keychain service app dari instalasi lama tetap tersisa: blob kunci Secure Enclave (`cred.key.*`), record kredensial (`cred.record.*`), token baca status, dan counter (backlog "Sisa instal ulang").

Item-item itu yatim, karena tidak ada kartu yang merujuknya. Keberadaannya bertentangan dengan maksud FR-43, yaitu bahwa instal ulang membuat kredensial N/B tidak dapat dipakai.

Kandidat seri adalah penyambungan App Attest: endpoint challenge dan penyimpanan kunci attested per perangkat, dalam mode belum diwajibkan. Mengikat kunci attested ke `device_id` yang belum terautentikasi menyentuh ADR-0041. Kandidat ini juga menyentuh pembatas per perangkat attested (ADR-0046), kebijakan endpoint yang wajib, kategori produksi, dan bypass dev. Semua itu semantik keamanan yang menjadi hak pengguna.

## Hasil JEV

- **Hasil:** `instal_ulang_fr43` · confidence **0.39** (eskalasi) · escaped: false · tanpa requirement *contradicted* untuk dua kandidat teratas
- **Log mentah:** [`jev-log/2026-11-02-round38.input.json`](jev-log/2026-11-02-round38.input.json), [`jev-log/2026-11-02-round38.output.json`](jev-log/2026-11-02-round38.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `instal_ulang_fr43` | 0.47 | ketiganya *supported* |
| `app_attest_penyambungan` | 0.47 | ketiganya *supported* |
| `laporan_fr58` | 0.01 | P0/gerbang: *unknown* |
| `akses_cepat_fr24` | 0.01 | P0/gerbang: *contradicted* (P1) |
| `polling_test_konkurensi` | 0.01 | P0/gerbang: *unknown* |

## Keputusan

- **Diterapkan:** pada peluncuran pertama sesudah instal ulang, semua item Keychain service app dihapus. Peluncuran itu dikenali dari penanda instalasi yang tidak ada dan store kartu lokal yang kosong.
  - Penghapusan dilakukan sebelum layanan dipakai.
  - Bila kartu masih ada, tidak ada yang dihapus. Kasus ini terjadi saat pembaruan dari build tanpa penanda.
  - Store kartu yang gagal dibaca dianggap berisi kartu, sehingga tidak ada yang dihapus.
- **Tidak diterapkan otomatis:** penyambungan App Attest. Masuk daftar keputusan pengguna bersama ADR-0041 dan ADR-0046.
- **Tetap terbuka:** status UNREACHABLE di server (FR-43). Status ini butuh definisi "melapor" dan TTL.

Desain dan rencananya ada di `docs/superpowers/specs/2026-11-02-sisa-instal-ulang-design.md` dan `docs/superpowers/plans/2026-11-02-sisa-instal-ulang.md`.

## Konsekuensi

- Instal ulang tidak lagi meninggalkan materi kredensial di Keychain.
- Pembaruan dari build tanpa penanda tidak kehilangan kartu, karena kartu yang masih ada mencegah penghapusan.
- Keputusan pengguna bertambah satu: penyambungan App Attest.
