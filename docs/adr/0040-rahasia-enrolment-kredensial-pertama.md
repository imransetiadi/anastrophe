# ADR-0040: Rahasia enrolment untuk kredensial pertama; tambah kanal ke kartu aktif ditolak

- **Status:** Diterima
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-05, FR-16, ADR-0018, ADR-0027, ADR-0034, ADR-0035, ADR-0037, ADR-0039, SDD §8.4.1, §8.5

## Konteks

Provisioning kredensial hanya dilindungi id card instance, dan `:challenge` membocorkan id itu kepada siapa pun yang tahu `cred_id` (ADR-0039). Celah yang dieksploitasi reviewer adalah **menambah kanal** pada instance ACTIVE milik orang lain.

Padahal satu-satunya pemanggil provisioning di app adalah alur enrolment yang memprovisikan tepat satu kredensial sesudah `POST /v1/enrollments`. Tidak ada alur app yang menambah kanal ke kartu aktif, dan FR-05 memilih satu kanal terbaik per kartu.

## Keputusan

- **Rahasia enrolment.** App membuat 32 byte acak per enrolment dan mengirim SHA-256-nya di `POST /v1/enrollments`. Server menyimpan hash itu pada card instance saat dibuat. Hash diganti bila perangkat yang sama mendapat instance itu kembali lewat panggilan enrolment, yaitu saat melanjutkan (ADR-0034) atau saat dipromosikan undangan (ADR-0035).
- **Hanya kredensial pertama.** `POST /v1/enrollments/{id}/credentials` wajib membawa rahasia itu sebagai `Authorization: Bearer` dan hanya berlaku untuk instance `PROVISIONING`. Rahasia yang hilang atau salah dijawab sama dengan id tak dikenal (404 `ENR-NOT-FOUND`). Pemeriksaan rahasia terjadi sebelum status instance diungkap.
- **Tambah kanal ditolak.** Kanal baru untuk instance ACTIVE ditolak sampai produk membutuhkan alur tambah kanal bertanda tangan.
- **App membuang rahasia.** Rahasia hanya ada di memori selama alur enrolment dan tidak disimpan, karena enrolment ulang setelah crash memasang rahasia baru.

## Konsekuensi

- `cred_id`, id instance, id perangkat, maupun data reader tidak lagi cukup untuk menerbitkan kredensial.
- Tidak ada rahasia baru yang tersimpan di perangkat atau server, kecuali hash sementara milik instance yang sedang diprovisikan.
- Fitur tambah kanal di masa depan butuh ADR dan alur bertanda tangan sendiri.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Ronde 24:** `enrolment_secret_all` 0,51 lawan `secret_first_then_signature` 0,44 · confidence **0.43**, sehingga dieskalasi. Log: [`jev-log/2026-11-02-round24.input.json`](jev-log/2026-11-02-round24.input.json), [`jev-log/2026-11-02-round24.output.json`](jev-log/2026-11-02-round24.output.json)
- **Ronde 25** diajukan ulang sekali dengan bukti material baru: app tidak pernah menambah kanal ke instance ACTIVE, dan FR-05 memilih satu kanal per kartu. Kandidat `secret_first_block_add_channel` ditambahkan.
  - **Hasil:** `secret_first_block_add_channel` · confidence **0.83** · escaped: false · tanpa requirement *contradicted*
  - **Log:** [`jev-log/2026-11-02-round25.input.json`](jev-log/2026-11-02-round25.input.json), [`jev-log/2026-11-02-round25.output.json`](jev-log/2026-11-02-round25.output.json)

| Kandidat (ronde 25) | Probabilitas |
|---|---|
| `secret_first_block_add_channel` | 0.86 |
| `enrolment_secret_all` | 0.08 |
| `secret_first_then_signature` | 0.05 |
