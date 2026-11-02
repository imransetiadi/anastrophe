# ADR-0035: Undangan berkartu menyetujui instance yang belum selesai milik perangkat yang sama

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-12, FR-19, FR-54, ADR-0032, ADR-0033, ADR-0034, temuan review akhir undangan I1

## Konteks

Undangan yang diikat ke kartu terdaftar menolak perangkat yang sudah memegang card instance aktif untuk kartu itu dengan 409 `ENR-DUPLICATE`. Status yang dihitung termasuk `PENDING_APPROVAL` dan `PROVISIONING`, padahal kartunya belum berfungsi di perangkat itu. Review akhir mengonfirmasi jalan buntu ini terhadap PostgreSQL:

1. Perangkat B mendaftarkan kartu A lewat jalur kartu dan mendapat `PENDING_APPROVAL` karena perangkat lain sudah memegangnya (ADR-0032).
2. Operator membuat undangan untuk kartu A dan mengirimnya ke B.
3. B memakai undangan itu dan mendapat `ENR-DUPLICATE`, dengan teks "Kartu ini sudah ada di iPhone ini.". Hasilnya sama berhari-hari kemudian karena `PENDING_APPROVAL` tidak kedaluwarsa (ADR-0034). Bila instance B masih `PROVISIONING`, B buntu sampai 15 menit.

ADR-0034 menetapkan `ENR-DUPLICATE` hanya untuk instance `ACTIVE` atau `SUSPENDED`, dengan prioritas pertama "tanpa jalan buntu".

## Keputusan

Bila perangkat memakai undangan yang sah dan diikat ke kartu A, sementara perangkat itu sudah memegang instance `PENDING_APPROVAL` atau `PROVISIONING` untuk kartu A, undangan diperlakukan sebagai persetujuan operator atas instance tersebut.

- Dalam transaksi yang sama, instance menjadi `PROVISIONING`, `invitation_id` diisi, `status_changed_at` diperbarui, dan `used_at` undangan diisi.
- Audit `enrollment.approved` dicatat dengan aktor `device:<id>` dan data `{method: "invitation", invitation: <id internal>, from: <status sebelumnya>}`.
- Respons 200 dengan `{enrollment_id, status: "PROVISIONING"}` milik instance itu. Tidak ada instance baru, sehingga jumlah kartu aktif perangkat tidak bertambah.
- Bila instance itu sudah milik undangan lain, instance dikembalikan apa adanya (melanjutkan, ADR-0034) dan undangan baru tidak terpakai.
- `ENR-DUPLICATE` tetap untuk instance `ACTIVE` atau `SUSPENDED`.

## Konsekuensi

- Undangan dari operator selalu membawa perangkat sampai ke kredensial, tanpa langkah `approve` terpisah.
- Rantai audit menunjukkan undangan mana yang mengubah status instance (FR-54).
- Perangkat tanpa undangan tetap mengikuti ADR-0032: perangkat tambahan menunggu persetujuan operator.
- Langkah 3 spesifikasi undangan ("card instance aktif → `ENR-DUPLICATE`") diganti oleh keputusan ini.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** What should POST /v1/enrollments do when a device redeems a card-bound invitation while it already holds an unfinished instance for that card?
- **Prioritas yang diberikan:** tanpa jalan buntu; niat operator dan jejak audit; sekali pakai, batas 8 kartu, dan ADR-0032 tetap utuh; kode dan API tambahan minimal.
- **Hasil:** `promote_existing` · confidence **0.94** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round19.input.json`](jev-log/2026-11-01-round19.input.json), [`jev-log/2026-11-01-round19.output.json`](jev-log/2026-11-01-round19.output.json)

| Kandidat | Probabilitas |
|---|---|
| `promote_existing` | 0.95 |
| `supersede_existing` | 0.02 |
| `resume_existing` | 0 |
| `distinct_conflict` | 0 |
| `none` | 0.03 |
