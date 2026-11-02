# ADR-0048: Fokus berikutnya: layar Bantuan dan FAQ in-app

- **Status:** Diterima (JEV 0,99)
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-60, FR-02, FR-27, FR-63, TC-UX-08, TC-PRIV-06, ADR-0018, ADR-0043

## Konteks

Alur Tambah Kartu produksi (ADR-0043) selesai di `3f32f20`, jadi penghuni kini bisa menambah dan memakai kartu. Namun app belum punya layar Bantuan maupun FAQ, padahal:

- FR-60 (P0) meminta FAQ in-app per kanal.
- FR-02 (P0) meminta daftar perangkat yang didukung di halaman Bantuan.
- FR-27 (P0) meminta perilaku saat layar terkunci dijelaskan di FAQ.
- FR-63 (P1) meminta ekspor laporan diagnostik tanpa rahasia.

Keempatnya murni app dan bisa diverifikasi di simulator.

## Hasil JEV

- **Hasil:** `bantuan_faq` · confidence **0.99** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round33.input.json`](jev-log/2026-11-02-round33.input.json), [`jev-log/2026-11-02-round33.output.json`](jev-log/2026-11-02-round33.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `bantuan_faq` | 0.99 | ketiganya *supported* |
| `kebijakan_gedung` | 0.01 | dampak P0 tidak diketahui |
| `minor_tambah_kartu` | 0 | tidak menutup requirement P0 baru |
| `akses_cepat` | 0 | P1; butuh target extension baru |

## Keputusan

Unit berikutnya adalah layar Bantuan, dibuka dari tab Kunci:

- FAQ untuk sepuluh topik FR-60, disesuaikan dengan kanal yang tersedia di iPhone ini;
- daftar perangkat yang didukung (FR-02);
- penjelasan saat layar terkunci (FR-27);
- laporan diagnostik tanpa rahasia (FR-63).

Desainnya ada di `docs/superpowers/specs/2026-11-02-bantuan-faq-design.md`.

## Konsekuensi

- Topik FAQ untuk fitur yang belum ada (anggota, pindah perangkat) dijawab sesuai perilaku sekarang, tanpa menjanjikan fitur.
- Kontak dukungan R1 adalah pengelola gedung, karena belum ada kanal dukungan Anastrophe yang ditetapkan.
