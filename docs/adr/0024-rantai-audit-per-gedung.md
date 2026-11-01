# ADR-0024: Rantai hash audit per gedung

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-54, FR-56, SDD §8.1 (`audit_events`), §8.3, §8.5 (`GET /admin/sites/{id}/audit`), ADR-0014

## Konteks

FR-54 meminta log audit yang tidak dapat diubah. SDD §8.1 memakai satu tabel `audit_events` dengan `prev_hash`/`hash`, tetapi tidak menetapkan cakupan rantai.

Audit dibaca dan diekspor per gedung (`GET /admin/sites/{id}/audit`), dan peran Security Officer bersifat per gedung (FR-56). Operator gedung adalah tenant yang terpisah.

## Keputusan

**Satu rantai hash per gedung.**

- `audit_events` mendapat kolom `site_id`, dan `prev_hash` menunjuk baris terakhir dari gedung yang sama.
- Penambahan baris hanya diserialkan di dalam satu gedung (advisory lock per gedung).
- Event yang tidak terkait gedung (mis. `account.deleted`) masuk rantai platform tersendiri.

## Konsekuensi

- Ekspor audit sebuah gedung dapat diverifikasi utuh tanpa melihat baris tenant lain.
- Tidak ada kunci tulis yang dipakai bersama oleh semua gedung.
- Menghapus atau mengubah baris mana pun tetap terdeteksi di rantainya.
- Verifikasi lintas gedung memerlukan pemeriksaan tiap rantai.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** For Anastrophe's tamper-evident audit log (FR-54, SDD §8.1 table audit_events with prev_hash/hash), should the hash chain be one global chain for the whole deployment or one chain per site?
- **Prioritas yang diberikan:** bukti integritas yang bisa diverifikasi per gedung tanpa data tenant lain; cocok dengan model data dan API audit per gedung; sederhana; tanpa bottleneck tulis global.
- **Hasil:** `per_site_chain` · confidence **0.95** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round8.input.json`](jev-log/2026-11-01-round8.input.json), [`jev-log/2026-11-01-round8.output.json`](jev-log/2026-11-01-round8.output.json)

| Kandidat | Probabilitas |
|---|---|
| `per_site_chain` | 0.96 |
| `global_chain` | 0 |
