# ADR-0028: Kartu tanpa kunci dihapus lokal tanpa bukti

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-31, FR-41, ADR-0009, ADR-0026

## Konteks

Kunci kredensial memakai `WhenPasscodeSetThisDeviceOnly` (ADR-0009), sedangkan record memakai `AfterFirstUnlockThisDeviceOnly`. Mematikan passcode menghapus kunci tetapi menyisakan record dan kartu (status "Perlu dipindahkan"). Tanpa kunci, bukti kepemilikan ADR-0026 mustahil dibuat, sehingga kartu tidak pernah bisa dihapus (temuan review akhir I2).

## Keputusan

Bila tidak ada kunci untuk kredensial kartu, langkah server dilewati dan record serta kartu dihapus lokal.

- Autentikasi tetap diminta bila perangkat bisa mengautentikasi.
- Bila passcode tidak disetel (autentikasi mustahil), penghapusan tetap diizinkan, karena kartu tanpa kunci tidak bisa dipakai.
- Pengguna diberi tahu bahwa server gedung menyimpan kartu itu sampai kedaluwarsa atau dicabut lewat pemindahan/admin.

## Konsekuensi

- Pengguna selalu bisa membersihkan kartu yang tidak bisa dipakai.
- Tidak ada akses yang diberikan atau dipertahankan, karena kunci sudah tidak ada.
- Slot server tetap terpakai sampai kartu dicabut lewat pemindahan perangkat (FR-41) atau admin.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** How should the app handle deleting a card whose credential private key is missing, when a proof of possession is impossible?
- **Prioritas yang diberikan:** pengguna selalu bisa menghapus kartu yang tak terpakai; tanpa akses tambahan; autentikasi bila memungkinkan; jujur soal server.
- **Hasil:** `local_delete_no_proof` · confidence **1.0** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round12.input.json`](jev-log/2026-11-01-round12.input.json), [`jev-log/2026-11-01-round12.output.json`](jev-log/2026-11-01-round12.output.json)

| Kandidat | Probabilitas |
|---|---|
| `local_delete_no_proof` | 1.0 |
| `block_until_transfer` | 0 |
| `local_delete_require_auth` | 0 |
