# ADR-0049: Fokus berikutnya: kebijakan gedung (FR-55 sebagian)

- **Status:** Provisional (JEV 0,63), ditinjau di milestone M2
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-55, FR-04, FR-05, ADR-0010, ADR-0018, ADR-0023, ADR-0043, ADR-0048

## Konteks

Layar Bantuan selesai di `10c69ef`. FR-55 (P0) meminta kebijakan per gedung, tetapi:

- **Masa berlaku sertifikat:** `sites.policy` sudah memuat zona dan `cert_validity_days` (ADR-0010), tetapi belum ada alat operator untuk mengaturnya.
- **Kanal:** kanal yang diizinkan masih global lewat `/v1/config`. Akibatnya gedung yang hanya punya pembaca "Tempel ke pembaca" bisa menerima kredensial Bluetooth yang tidak berguna, atau sebaliknya.

## Hasil JEV

- **Hasil:** `kebijakan_gedung` · confidence **0.63** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round34.input.json`](jev-log/2026-11-02-round34.input.json), [`jev-log/2026-11-02-round34.output.json`](jev-log/2026-11-02-round34.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `kebijakan_gedung` | 0.68 | ketiganya *supported* |
| `filter_cli_fr50` | 0.28 | ketiganya *supported* |
| `minor_klien` | 0.01 | tidak memajukan P0 |
| `akses_cepat` | 0 | P1; dampak P0 tidak diketahui |

## Keputusan

Unit berikutnya mencakup bagian FR-55 yang bisa dibangun sekarang:

- CLI kebijakan untuk masa berlaku sertifikat (1–30 hari) dan kanal yang diizinkan per gedung, dengan audit.
- Penegakan kanal gedung saat provisioning.
- App mengetahui kanal gedung dari lookup kode gedung dan respons enrolment, agar memilih kanal yang diizinkan.

Persetujuan opsional per gedung (FR-17) tidak disentuh, karena mengubah perilaku keamanan bawaan (ADR-0032).

Desainnya ada di `docs/superpowers/specs/2026-11-02-kebijakan-gedung-design.md`.

## Konsekuensi

- **Provisional:** ditinjau di M2. Filter kanal dan pencarian CLI (FR-50) menjadi kandidat berikutnya.
- Kanal yang dilarang setelah kredensial terbit tidak mencabut kredensial lama. Perpanjangan tidak ikut diubah: kill switch per kanal tetap hanya di `:renew` global (ADR-0023). Perluasan ke perpanjangan butuh keputusan sendiri.
