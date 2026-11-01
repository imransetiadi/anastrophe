# ADR-0027: Kartu yang ditangguhkan bisa dihapus pemiliknya

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-31, FR-15, FR-42, FR-51, SDD §8.2, ADR-0026

## Konteks

ADR-0026 hanya mengizinkan penghapusan kartu ACTIVE. Kartu SUSPENDED (pengguna, admin, atau Lost Mode) lalu terhapus lokal saja di app, sementara server tetap menghitungnya ke batas 8 kartu. *Resume* kelak akan mengaktifkan kredensial yang kuncinya sudah dihapus (temuan review akhir I1).

## Keputusan

- `:challenge` diizinkan untuk kredensial ACTIVE atau SUSPENDED; perpanjangan tetap mensyaratkan ACTIVE.
- `DELETE /v1/cards/{id}` menerima kartu ACTIVE atau SUSPENDED dengan bukti dari kredensial ACTIVE atau SUSPENDED kartu itu, lalu mencabutnya (SUSPENDED → REVOKED ada di mesin status SDD).
- Server menjawab 410 `CARD-GONE` hanya bila kartu atau kredensial sudah REVOKED/DELETED atau kartu tidak dikenal. App menghapus lokal tanpa konfirmasi server hanya pada `CARD-GONE` (dan `CRED-NOT-FOUND` dari `:challenge`), setelah mencoba setiap kredensial kartu.

## Konsekuensi

- Kartu yang ditangguhkan bisa dihapus, dan slotnya terbebas.
- Pencabutan lebih ketat daripada penangguhan, jadi pemegang kunci tidak mendapat akses tambahan.
- Kode lain (mis. `INTERNAL`, `CRED-PROOF-INVALID`) tidak lagi membuat app menghapus lokal.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Should a card owner be able to delete a SUSPENDED card (FR-31), and when may the app delete a card locally without server confirmation?
- **Prioritas yang diberikan:** pencabutan di server + slot terbebas; tidak ada kredensial yang bisa di-resume tanpa kunci; hapus lokal tanpa konfirmasi hanya bila server bilang kartu sudah tiada.
- **Hasil:** `revoke_suspended` · confidence **0.94** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round11.input.json`](jev-log/2026-11-01-round11.input.json), [`jev-log/2026-11-01-round11.output.json`](jev-log/2026-11-01-round11.output.json)

| Kandidat | Probabilitas |
|---|---|
| `revoke_suspended` | 0.95 |
| `block_suspended` | 0.02 |
| `local_only_suspended` | 0 |
