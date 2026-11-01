# ADR-0030: Detail kartu menampilkan lima tap terbaru dan tautan ke riwayat 30 hari

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-30, FR-31, O-S11, NFR-A01, TC-MGT-01

## Konteks

Detail kartu menampilkan `history.prefix(20)` di bawah judul "Riwayat tap (30 hari)" tanpa cara melihat sisanya (temuan review akhir I2). Dengan 4 tap per hari kerja, daftar berhenti di sekitar hari ke-9. Entri yang lebih lama tersimpan tetapi tidak bisa dibuka. Detail juga memuat satu aksi utama dan bagian Pengaturan → Hapus kartu (FR-31, O-S11), yang akan terdorong jauh ke bawah bila semua entri ditampilkan.

## Keputusan

- Detail menampilkan **lima** tap terbaru.
- Bila ada lebih dari lima, baris "Lihat semua (n)" membuka layar riwayat yang memuat semua entri 30 hari, terbaru di atas, dengan baris yang sama.
- Judul layar riwayat memakai judul bagian riwayat yang sudah ada.

## Konsekuensi

- Setiap tap 30 hari terakhir bisa dibuka (FR-30, TC-MGT-01).
- Bagian Pengaturan → Hapus tetap dekat, termasuk pada ukuran teks AX5.
- Tambahan UI: satu layar daftar dan satu string ("Lihat semua (n)") dalam ID dan EN.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** How should the card detail screen present the local 30-day tap history (FR-30)?
- **Prioritas yang diberikan:** semua tap 30 hari bisa dilihat; detail tetap ringkas dengan Hapus mudah dicapai; layak di AX5; UI dan string tambahan minimal.
- **Hasil:** `inline_recent_plus_all` · confidence **0.95** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round14.input.json`](jev-log/2026-11-01-round14.input.json), [`jev-log/2026-11-01-round14.output.json`](jev-log/2026-11-01-round14.output.json)

| Kandidat | Probabilitas |
|---|---|
| `inline_recent_plus_all` | 0.96 |
| `history_screen_only` | 0.02 |
| `show_all_inline` | 0.01 |
| `cap_20_relabel` | 0 |
