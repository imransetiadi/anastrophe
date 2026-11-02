# Provisioning kredensial hanya untuk perangkat yang memulai enrolment — desain

**Status:** fokus dari ADR-0039 (JEV 0,92); mekanisme dari ADR-0040 (JEV 0,83). Pengguna memakai mode iterasi otomatis; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

`POST /v1/enrollments/{id}/credentials` hanya dilindungi id card instance, padahal `:challenge` mengembalikan id itu kepada siapa pun yang tahu `cred_id`. Reviewer berhasil menerbitkan kredensial untuk kanal baru pada kartu aktif orang lain. Desain ini menutup celah tersebut tanpa App Attest.

## Tujuan

1. App membuat rahasia enrolment 32 byte per enrolment dan mengirim SHA-256-nya sebagai `provisioning_key_hash` di `POST /v1/enrollments` (kartu maupun undangan).
2. Server menyimpan hash itu pada card instance (`PROVISIONING` atau `PENDING_APPROVAL`, baru maupun dilanjutkan/dipromosikan) dalam transaksi enrolment yang sama.
3. Provisioning wajib membawa `Authorization: Bearer <rahasia base64url>`. Rahasia hilang, rusak, atau salah dijawab sama dengan id tak dikenal (404 `ENR-NOT-FOUND`). Rahasia diperiksa sebelum status instance diungkap.
4. Provisioning hanya untuk instance `PROVISIONING`: tambah kanal ke instance ACTIVE ditolak (404 `ENR-NOT-FOUND` karena hash sudah terhapus; 409 `ENR-NOT-PROVISIONABLE` sebagai pertahanan berlapis bila hash masih ada).
5. Hash dihapus setelah kredensial pertama tersimpan.

## Non-goal

- App Attest dan autentikasi perangkat (butuh tim Apple), serta alur tambah kanal bertanda tangan (butuh ADR baru bila produk memerlukannya).
- Autentikasi pemanggil enrolment: pihak yang tahu id perangkat dan identitas kartu masih bisa mengganti hash instance yang belum selesai (risiko sisa, ADR-0041).
- Menghapus `card_instance_id` dari jawaban `:challenge`. Id itu masih dipakai sebagai cadangan hapus kartu (ADR-0027) dan tidak lagi cukup untuk provisioning.

## Anti-goal

- Rahasia mentah tersimpan di server, log, audit, atau baris idempotency.
- Jawaban provisioning yang membedakan rahasia salah dari id tak dikenal.
- Rahasia disimpan di perangkat setelah alur enrolment selesai.

## Model data (migrasi `0011`)

`card_instances.provisioning_key_hash bytea null` (32 byte).

## Rincian

- `provisioning_key_hash` di body enrolment bersifat opsional pada format, tetapi instance tanpa hash tidak bisa diprovisikan. Nilai yang bukan 32 byte → 400 `REQ-INVALID`. Hash idempotency enrolment mencakupnya bila ada.
- *Keputusan builder:* jalur enrolment tanpa Idempotency-Key kini juga memakai transaksi bersama (`Store.InTx`), sehingga pemasangan hash selalu atomik dengan enrolment.
- Provisioning: hash idempotency mencakup SHA-256 rahasia. Urutan pemeriksaan: validasi body (400), instance dan rahasia (404 identik), `PENDING_APPROVAL` (409), bukan `PROVISIONING` (409), lalu penerbitan.
- App: rahasia hanya ada di memori selama alur enrolment. Enrolment ulang setelah crash memasang rahasia baru karena server mengganti hash saat instance dilanjutkan.

## Review Focus

1. Rahasia salah, hilang, atau rusak dijawab identik dengan id tak dikenal, termasuk untuk instance `PENDING_APPROVAL` dan ACTIVE.
2. Tambah kanal ke instance ACTIVE ditolak walau rahasia benar.
3. Melanjutkan (ADR-0034) dan promosi undangan (ADR-0035) tetap bisa diprovisikan dengan rahasia terbaru.
4. Rahasia mentah tidak tersimpan di database, log, maupun baris idempotency.
5. Hash terhapus setelah kredensial pertama.
