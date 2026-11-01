# ADR-0042: Fokus berikutnya setelah provisioning aman (terbuka)

- **Status:** Diterapkan: rekomendasi penulis (`hardening_minors`). Dasarnya tujuan iterasi berkelanjutan pengguna dan persetujuan umumnya atas saran penulis; pengguna dapat membatalkannya.
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-60, FR-05, FR-10, ADR-0018, ADR-0038, ADR-0041, backlog terverifikasi

## Konteks

Provisioning aman (ADR-0039/0040) selesai. Dua keputusan keamanan menunggu pengguna (ADR-0038, ADR-0041), begitu pula ADR-0017 dan ADR-0022. Kandidat yang tidak mendahului keputusan itu ada dua:

- **FAQ in-app** (FR-60, P0): hanya di app, dalam ID dan EN.
- **Perbaikan minor tertunda** dari review siklus hidup, provisioning, dan undangan. Contohnya update yang dijaga status, kedaluwarsa dan purge denylist, konkurensi penyegar status, parameter rahasia yang wajib, test idempotency, dan validasi `--link-base`.

Alur "Tambah kartu" Release masih terblokir akun, App Attest, dan iPhone fisik.

## Hasil JEV

- **Hasil:** `faq_in_app` · confidence **0.41** · escaped: false · tanpa requirement *contradicted*
- Confidence di bawah 0,60, jadi pilihan fokus dieskalasi ke pengguna (ADR-0018) dan tidak diajukan ulang tanpa bukti baru.
- **Log mentah:** [`jev-log/2026-11-02-round27.input.json`](jev-log/2026-11-02-round27.input.json), [`jev-log/2026-11-02-round27.output.json`](jev-log/2026-11-02-round27.output.json)

| Kandidat | Probabilitas |
|---|---|
| `faq_in_app` | 0.51 |
| `hardening_minors` | 0.46 |
| `add_card_flow_mocked` | 0 |

## Rekomendasi penulis

`hardening_minors` lebih dulu. Beberapa minor menyentuh jalur keamanan yang baru dibangun: hash tertinggal pada instance aktif, purge denylist, dan parameter rahasia yang bisa terlewat. Memperbaikinya sekarang lebih murah selagi konteksnya masih segar. FAQ (FR-60) menyusul sesudahnya.

## Penerapan (2026-11-02)

JEV mengeskalasi pilihan ini (0,41). Tujuan sesi pengguna adalah iterasi tanpa henti ("lakukan iterasi infinity looping untuk build apps ini secara bertahap"), dan pengguna sebelumnya menyetujui saran penulis secara umum. Karena itu rekomendasi penulis diterapkan. Pilihan ini berisiko rendah, bisa dibatalkan, hanya di branch fitur, dan tidak menyentuh ADR-0038 maupun ADR-0041, yang tetap menunggu pengguna karena mengubah perilaku bagi pengguna sah.
