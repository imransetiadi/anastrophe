# ADR-0032: Sebelum ada akun, perangkat pertama diprovisikan dan perangkat tambahan menunggu persetujuan

- **Status:** Diterima (provisional — tinjau ulang saat fondasi akun dibangun)
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** ADR-0004, ADR-0005, ADR-0031, SDD §8.4.1, FR-03, FR-11, FR-15

## Konteks

Registri kartu fisik (ADR-0031) dibangun lebih dulu daripada akun (FR-03). Tanpa akun, pencocokan kontak pemegang (ADR-0004) dan security code pemilik (ADR-0005) belum mungkin. Kartu fisik hanyalah bukti kepemilikan lemah. Orang yang sempat meminjam atau menemukan kartu terdaftar bisa mendaftarkan iPhone-nya dan menyimpan kredensial yang terus diperpanjang.

## Keputusan

Untuk kartu fisik yang cocok dengan registri:

- Bila belum ada card instance aktif untuk kartu itu, perangkat mendapat card instance `PROVISIONING`.
- Bila perangkat lain sudah memegang card instance aktif, perangkat ini mendapat card instance `PENDING_APPROVAL`. Operator menyetujui atau menolaknya lewat perintah CLI.
- Perangkat yang sama boleh mendaftar lagi setelah kartunya dihapus.

Aturan ini sementara. Saat akun dan keanggotaan ada, `PENDING_APPROVAL` untuk perangkat tambahan digantikan alur MEMBER_CANDIDATE dengan security code pemilik (SDD §8.4.1).

## Konsekuensi

- Akses dengan kartu pinjaman tidak lagi otomatis untuk perangkat kedua; tetap ada pemeriksaan manusia.
- Enrolment pertama dan uji lab end-to-end tetap berjalan tanpa akun atau portal admin.
- Pemegang pertama tetap dipercaya tanpa pencocokan kontak sampai akun ada. Risiko ini sama dengan tracer saat ini dan ditinjau ulang bersama fondasi akun.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Until accounts, holder contact matching and memberships exist, what should POST /v1/enrollments do when a device presents a registered card that another device already holds?
- **Prioritas yang diberikan:** tidak lebih longgar daripada model target SDD; enrolment pertama dan lab tetap jalan tanpa akun; mudah berkembang ke hasil SDD §8.4.1; kode sementara minimal.
- **Hasil:** `pending_for_additional` · confidence **0.71** (provisional) · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round16.input.json`](jev-log/2026-11-01-round16.input.json), [`jev-log/2026-11-01-round16.output.json`](jev-log/2026-11-01-round16.output.json)

| Kandidat | Probabilitas |
|---|---|
| `pending_for_additional` | 0.75 |
| `first_device_only` | 0.11 |
| `pending_approval_all` | 0.1 |
| `none` | 0.03 |
| `ask_user` | 0.01 |
| `allow_any_holder` | 0 |
