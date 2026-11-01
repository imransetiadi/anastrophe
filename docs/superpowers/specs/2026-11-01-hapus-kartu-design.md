# Hapus kartu (FR-31) — desain

**Status:** keputusan otorisasi lewat JEV (ADR-0026, `pop_revoke`, 0,98). Pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

Pengguna dapat menghapus kartu dari iPhone (FR-31, TC-MGT-02). Kredensial dicabut di server, sehingga reader menolak setelah sinkron dan slot dari batas 8 kartu terbebas.

## Tujuan

1. Backend: `DELETE /v1/cards/{id}` dengan `Idempotency-Key` wajib. Body `{"credential_id","nonce","signature"}` (base64), dengan tanda tangan atas `"ANP1-REVOKE"` ‖ `cred_id` ‖ `nonce` ‖ teks `card_instance_id` huruf kecil.
   - Dalam satu transaksi: card instance ada (404 `CARD-NOT-FOUND`) dan ACTIVE (409 `CARD-NOT-REMOVABLE`); kredensial milik kartu itu (400 `CRED-PROOF-INVALID`); nonce valid (400 `CRED-CHALLENGE-INVALID`); tanda tangan valid (400 `CRED-PROOF-INVALID`).
   - Lalu card instance dan semua kredensial ACTIVE-nya menjadi REVOKED (`revoke_reason = 'user_deleted'`), nonce terpakai, dan setiap kredensial mendapat audit `credential.revoked` dengan data `{"channel","reason"}`. Respons 204.
2. App: Detail → Pengaturan → "Hapus kartu" → konfirmasi → Face ID/passcode → `CardRemover` (challenge → tanda tangan → DELETE) → hapus kunci, record, dan kartu lokal.
   - Server tidak terjangkau: kartu tetap ada dan pengguna mendapat pesan.
   - Server menjawab 404 atau 409 (sudah dicabut atau tidak dikenal): hapus lokal tetap berjalan.
   - Kartu tanpa backend penerbit (lab `lab_ca.py`): hapus lokal saja.
3. `CredentialRecord.serverCardID` (opsional) disimpan saat provisioning.

## Keputusan builder

- `:challenge` tidak lagi memeriksa kill switch kanal, karena nonce juga dipakai untuk penghapusan dan pengguna harus tetap bisa menghapus kartu di kanal yang dimatikan. `:renew` tetap menolak kanal yang dimatikan.
- Konfirmasi memakai `confirmationDialog` dengan peran destruktif (pedoman iOS); autentikasi memakai `UserAuthenticator` yang sama dengan presentasi.

## Non-goal

Kanal W (Apple Access Platform), hapus anggota (FR-33), dan sinkron denylist ke reader (Site Sync).
