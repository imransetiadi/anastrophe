# ADR-0034: Enrolment yang belum selesai dilanjutkan; PROVISIONING tanpa kredensial kedaluwarsa

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-15, FR-19, ADR-0032, SDD §8.5, temuan review akhir registri I1

## Konteks

Setiap card instance aktif milik perangkat yang sama untuk kartu yang sama dijawab 409 `ENR-DUPLICATE`, termasuk yang belum selesai. Akibatnya ada dua jalan buntu (temuan review I1):

1. Perangkat yang gagal di langkah kredensial tidak bisa mencoba lagi, padahal belum punya kartu.
2. Perangkat tambahan yang sudah disetujui operator (ADR-0032) juga ditolak saat mencoba lagi, sehingga tidak pernah mendapat kredensial.

Instance yang tertinggal juga memakan slot batas 8 kartu dan mendorong perangkat lain ke `PENDING_APPROVAL`.

## Keputusan

- **Lanjutkan:** bila perangkat yang sama sudah memegang instance `PROVISIONING` atau `PENDING_APPROVAL` untuk kartu itu, server mengembalikan `{enrollment_id, status}` instance tersebut dengan 200. Tidak ada instance baru dan tidak ada audit baru. `ENR-DUPLICATE` hanya untuk instance `ACTIVE` atau `SUSPENDED`.
- **Kedaluwarsa:** instance `PROVISIONING` yang belum punya kredensial menjadi `ABANDONED` 15 menit setelah masuk `PROVISIONING` (dibuat atau disetujui), dengan audit `enrollment.abandoned`. Status ini tidak dihitung aktif.
  - Pemeriksaan dilakukan di transaksi enrolment untuk kartu dan perangkat yang terlibat, ditambah sapuan berkala di API.
  - Melanjutkan enrolment memperbarui waktu itu.
- `PENDING_APPROVAL` tidak kedaluwarsa otomatis dan menunggu keputusan operator.

## Konsekuensi

- Kegagalan di langkah kredensial dan persetujuan operator tidak lagi berujung buntu.
- Slot batas 8 kartu dan status pemegang kartu pulih sendiri dari enrolment yang ditinggalkan.
- Perangkat lain tetap `PENDING_APPROVAL` selama instance pemegang pertama aktif (ADR-0032 tidak melemah).

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** What should the server do when a device enrols a card for which it already holds an unfinished instance?
- **Prioritas yang diberikan:** tanpa jalan buntu; tanpa sisa yang memblokir kartu atau slot; tidak melemahkan ADR-0032; API dan kode tambahan minimal.
- **Hasil:** `resume_plus_expiry` · confidence **0.81** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round18.input.json`](jev-log/2026-11-01-round18.input.json), [`jev-log/2026-11-01-round18.output.json`](jev-log/2026-11-01-round18.output.json)

| Kandidat | Probabilitas |
|---|---|
| `resume_plus_expiry` | 0.84 |
| `resume_unfinished` | 0.16 |
| `cancel_endpoint` | 0 |
| `expiry_only` | 0 |
