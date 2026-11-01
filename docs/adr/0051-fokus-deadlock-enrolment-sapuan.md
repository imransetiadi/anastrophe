# ADR-0051: Fokus berikutnya: deadlock enrolment–sapuan per jam

- **Status:** Diterima (JEV 0,96)
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** NFR-R02, ADR-0024, ADR-0034, ADR-0042, backlog (review perbaikan minor)

## Konteks

Review perbaikan minor (ADR-0042) mencatat deadlock PostgreSQL 40P01 yang sudah ada sebelumnya, antara dua transaksi:

- **Enrolment:** `abandonStale` di dalam enrolment menulis audit `enrollment.abandoned`, yang mengambil kunci advisory rantai audit gedung. Sesudah itu enrolment masih bisa menunggu kunci baris instance, yaitu `UPDATE` resume atau `SELECT … FOR UPDATE` instance yang ditahan.
- **Sapuan per jam:** sapuan memegang baris instance yang ditandainya `ABANDONED`, lalu meminta kunci rantai audit gedung.

Akibatnya enrolment sesekali gagal 500. Pilihan lain untuk fokus kali ini terblokir:

- FR-07 menunggu dokumen legal;
- FR-44 butuh keputusan semantik;
- FR-58 masih P1.

## Hasil JEV

- **Hasil:** `deadlock_sapuan` · confidence **0.96** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round36.input.json`](jev-log/2026-11-02-round36.input.json), [`jev-log/2026-11-02-round36.output.json`](jev-log/2026-11-02-round36.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `deadlock_sapuan` | 0.97 | ketiganya *supported* |
| `persetujuan_fr07` | 0.03 | ketiganya *supported* |
| `pemulihan_fr44` | 0 | butuh input dan keputusan keamanan |
| `laporan_fr58` | 0 | P1 |

## Keputusan

- **Audit ditunda:** selama enrolment kartu dan undangan, audit ditahan dan baru ditulis di akhir transaksi, setelah semua kunci baris diambil.
- **Urutan rantai:** audit ditulis berurutan per rantai gedung. Urutan di dalam satu rantai dipertahankan, sehingga `seq` tetap logis.
- **Sapuan per jam:** audit sapuan memakai urutan rantai yang sama.
- **Bukti:** test urutan kunci deterministik. Satu koneksi menahan baris instance, dan koneksi lain memastikan enrolment yang sedang menunggu tidak memegang kunci rantai audit.

Desain dan rencananya ada di `docs/superpowers/specs/2026-11-02-deadlock-enrolment-sapuan-design.md` dan `docs/superpowers/plans/2026-11-02-deadlock-enrolment-sapuan.md`.

## Konsekuensi

- Isi dan hash audit tidak berubah; hanya waktu penulisan dalam transaksi yang bergeser.
- Bila enrolment gagal, transaksi di-rollback, jadi audit yang ditunda ikut hilang bersama perubahannya, sama seperti sebelumnya.
