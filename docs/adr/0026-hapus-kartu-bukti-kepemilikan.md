# ADR-0026: Hapus kartu dengan bukti kepemilikan kunci

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-31, FR-15, TC-MGT-02, SDD §8.2, §8.3, §8.5 (`DELETE /cards/{id}`), ADR-0023, ADR-0009

## Konteks

FR-31 meminta hapus kartu dengan konfirmasi dan autentikasi, serta pencabutan kredensial di sisi server. Backend belum punya autentikasi sesi pengguna.

Kartu yang hanya dihapus lokal tetap memakai satu dari 8 slot perangkat di server (FR-15), dan kredensialnya tetap ACTIVE sampai kedaluwarsa. Perpanjangan (ADR-0023) sudah memakai tanda tangan kunci kredensial atas nonce server.

## Keputusan

`DELETE /v1/cards/{card_instance_id}` membawa bukti kepemilikan untuk salah satu kredensial kartu: `cred_id`, nonce dari `POST /v1/credentials/{cred}:challenge`, dan tanda tangan kunci kredensial atas `"ANP1-REVOKE"` ‖ `cred_id` ‖ `nonce` ‖ `card_instance_id`.

Server memverifikasi bukti, mencabut card instance beserta semua kredensialnya (slot terbebas), dan mencatat `credential.revoked` di audit. App menandatangani setelah konfirmasi pengguna dan Face ID/passcode, dan menyimpan ID kartu server saat provisioning.

## Konsekuensi

- Pihak ketiga tidak dapat menghapus kartu orang lain tanpa kunci privat kredensialnya.
- Tidak ada mekanisme baru: nonce dan tanda tangan sama dengan perpanjangan, dibedakan oleh prefix domain.
- Kartu yang belum pernah diprovisikan (tanpa kredensial) belum bisa dihapus lewat jalur ini.
- Penghapusan butuh koneksi internet; bila server tidak terjangkau, kartu tetap ada dan pengguna dapat mencoba lagi.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** How should the Anastrophe tracer backend authorize card deletion (FR-31, SDD DELETE /cards/{id}) before user session authentication exists?
- **Prioritas yang diberikan:** pencabutan di server + slot terbebas; pihak ketiga tidak bisa menghapus; pakai ulang pola ADR-0023; sederhana tanpa autentikasi sesi.
- **Hasil:** `pop_revoke` · confidence **0.98** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round10.input.json`](jev-log/2026-11-01-round10.input.json), [`jev-log/2026-11-01-round10.output.json`](jev-log/2026-11-01-round10.output.json)

| Kandidat | Probabilitas |
|---|---|
| `pop_revoke` | 0.98 |
| `bearer_card_id` | 0 |
| `local_only_until_auth` | 0 |
