# Enrolment via undangan (FR-12, FR-53) — desain

**Status:** fokus dari ADR-0033 (JEV 0,89). Pengguna memakai mode iterasi otomatis dan melewati sesi tanya-jawab; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

Kartu yang tidak terbaca (mis. 125 kHz) dan gedung tanpa registri kartu belum punya jalur enrolment. FR-13 menawarkan undangan untuk kasus itu, dan FR-12 berprioritas P0. Pengelola gedung mengirim undangan sekali pakai yang bisa didaftarkan tanpa kartu fisik.

## Tujuan

1. Tabel `invitations` (SDD §8.1): hash token, gedung, kartu terdaftar opsional, zona, masa berlaku, waktu dipakai.
2. CLI operator `anastrophe-registry invite` mencetak token dan tautan sekali pakai, lalu menyimpan hash-nya saja.
3. `POST /v1/enrollments` menerima `invitation` sebagai alternatif `card`. Pemakaian tunggal ditegakkan dalam transaksi.
4. Undangan yang tidak dikenal, kedaluwarsa, atau sudah dipakai dijawab **identik** (TC-ENR-08).
5. App: parser tautan `/i/<token>` dan argumen lab `-ANLabInvite <token>`; body enrolment membawa token.

## Non-goal

- Universal Link produksi (domain dan entitlement Associated Domains belum ada) serta App Clip (P2).
- Pengiriman undangan lewat email/SMS (penyedia eksternal) dan API admin HTTP (FR-53 lewat portal).
- Pencocokan kontak undangan dengan akun (butuh FR-03). `contact_hmac` disimpan bila ada, belum ditegakkan.

## Anti-goal

- Token mentah tersimpan di database, log, audit, atau baris idempotency.
- Respons yang membedakan undangan tak dikenal, kedaluwarsa, dan terpakai, atau membocorkan info kartu.
- Satu undangan menghasilkan dua card instance.

## Token (*keputusan builder*)

- 32 byte acak (`crypto/rand`), dikodekan base64url tanpa padding (43 karakter).
- Disimpan sebagai SHA-256(token). Token berentropi 256 bit, jadi hash tanpa kunci aman dari tebakan.
- Masa berlaku default 7 hari (SDD §5.6); CLI menerima `--ttl` 1–30 hari.
- Tautan: `https://<domain>/i/<token>`. Domain belum ditentukan, jadi CLI menerima `--link-base`.

## Model data (migrasi `0009_invitations.sql`)

- `invitations(id uuid pk, site_id → sites, physical_card_id → physical_cards null, contact_hmac bytea(32) null, token_hash bytea(32) unique, zones_bitmap bigint default 0, expires_at, used_at null, created_at)`.
- `card_instances.invitation_id → invitations` (null bila lewat kartu).
- *Keputusan builder:* `zones_bitmap` ditambahkan ke undangan agar gedung tanpa registri tetap *fail-closed* dan zonanya eksplisit. Bila undangan diikat ke kartu terdaftar, zona dan `physical_card_id` diambil dari kartu.

## Enrolment

Permintaan: `{device_id, invitation}`. `site_id` tidak diperlukan karena diambil dari undangan. `card` dan `invitation` saling eksklusif.

1. Validasi bentuk token (43 karakter base64url); gagal → 400 `REQ-INVALID`.
2. Dalam transaksi: kunci perangkat; cari undangan lewat hash `FOR UPDATE`.
   - Tidak ada, kedaluwarsa, atau sudah dipakai → 404 `ENR-INVITATION-INVALID`, dengan body dan status yang sama.
3. Batas 8 kartu tetap berlaku. Perangkat ini sudah punya card instance aktif untuk kartu yang sama → 409 `ENR-DUPLICATE`.
4. Card instance dibuat `PROVISIONING`. Undangan adalah niat eksplisit pengelola, jadi aturan perangkat tambahan ADR-0032 tidak berlaku (SDD §8.2: undangan → PROVISIONING). `invitation_id` diisi, dan `physical_card_id` bila undangan diikat ke kartu.
5. `used_at` diisi di transaksi yang sama. Audit `enrollment.started` `{status, method: "invitation"}` berisi id internal saja.
   - *Keputusan builder (selaras ADR-0034):* perangkat yang sama dengan token yang sama melanjutkan instance-nya yang belum selesai (200). Bila instance undangan menjadi `ABANDONED`, `used_at` dikosongkan lagi sehingga undangan bisa dipakai ulang sampai kedaluwarsa. Perangkat lain dengan token terpakai tetap `ENR-INVITATION-INVALID`.
6. Idempotency: hash memakai hash token, bukan token mentah.

Zona sertifikat: kartu terdaftar bila tertaut, lalu `invitations.zones_bitmap` bila lewat undangan, lalu kebijakan gedung untuk data lama.

## CLI

`anastrophe-registry invite --site <uuid> [--card-tech <tech> --card-id <hex>] [--zones Lobi;Parkir] [--contact <email|telepon>] [--ttl 7] [--link-base https://…/i/] --operator <nama>`

- Mencetak token dan tautan **sekali**. Token tidak bisa diambil lagi.
- Kartu dan kontak opsional langsung di-HMAC per gedung; kartu harus sudah ada di registri.
- Audit `invitation.created` `{expires_at, bound_to_card}`.

## App

- `InvitationLink.token(from: URL)` menerima `https://<host>/i/<token>` dengan token 43 karakter base64url.
- Argumen lab `-ANLabInvite <token>` dipakai sebagai pengganti kartu lab.
- `ENR-INVITATION-INVALID` dipetakan ke teks ID/EN: "Undangan tidak berlaku atau sudah dipakai."

## Review Focus

1. Undangan yang sama dipakai dua perangkat bersamaan: tepat satu berhasil.
2. Tak dikenal, kedaluwarsa, dan terpakai dijawab identik.
3. Token mentah tidak muncul di database, log, audit, idempotency, atau keluaran CLI selain cetakan pertama.
4. Zona undangan tanpa kartu *fail-closed* (0 bila tidak diisi).
5. Undangan untuk kartu yang sudah dipegang perangkat lain tetap `PROVISIONING`, sedangkan perangkat yang sama mendapat `ENR-DUPLICATE`.

## Diserahkan ke builder

Nama berkas, fungsi, dan format keluaran CLI.
