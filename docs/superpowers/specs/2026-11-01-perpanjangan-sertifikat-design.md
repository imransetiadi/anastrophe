# Perpanjangan sertifikat (FR-45) — desain

**Status:** disetujui lewat JEV (ADR-0023, `renew_on_user_auth`, 0,98). Pengguna melewati sesi tanya-jawab ("approve semua saran kamu"); pilihan yang ditandai *keputusan builder* adalah keputusan penulis desain ini.

## Maksud

Sertifikat kredensial berlaku singkat, default 7 hari (ADR-0010). Tanpa perpanjangan, setiap kartu berhenti bekerja seminggu setelah dipasang. Perpanjangan harus terjadi tanpa prompt tambahan (O-W10), tanpa melonggarkan kunci (ADR-0009), dan tetap dengan bukti kepemilikan kunci kredensial (SDD §8.4.2).

## Tujuan

1. Backend menerbitkan nonce sekali pakai dan memperpanjang sertifikat untuk kunci yang sama setelah memverifikasi tanda tangan kunci kredensial atas nonce itu.
2. App memperpanjang hanya setelah pengguna mengautentikasi untuk tap, memakai ulang `LAContext` yang sama (O-A25):
   - sisa masa berlaku < 50% → perpanjangan berjalan segera setelah tap selesai, tanpa menahan tap;
   - sudah kedaluwarsa → perpanjangan berjalan lebih dulu (dibatasi waktu), lalu tap dilanjutkan.
3. Alur lab: kartu dari backend dev dapat diperpanjang end-to-end di simulator.

## Non-goal (rencana berikutnya)

- App Attest assertion (§8.4.2): butuh tim pengembang Apple dan perangkat fisik.
- Autentikasi sesi pengguna (Sign in with Apple/OTP), sama seperti backend R1 lainnya.
- `BGAppRefreshTask` dan silent push `cert_renewal_due`: menurut ADR-0023 keduanya hanya memeriksa status, dan pemeriksaan status butuh `GET /cards` yang belum ada.
- Rotasi kunci kredensial; event audit `credential.renewed`.

## Anti-goal

- Prompt Face ID/passcode kedua; kunci tanpa `.userPresence`.
- Perpanjangan untuk kredensial atau card instance yang SUSPENDED/REVOKED.
- Record lokal yang tertimpa sertifikat untuk `cred_id`/kanal lain, atau setengah diperbarui saat gagal.
- Tap yang menggantung karena jaringan lambat saat perpanjangan wajib.

## Kontrak API

`{cred}` = `cred_id` 16 B dalam hex huruf kecil (32 karakter). *Keputusan builder:* hex aman di path tanpa escaping; ServeMux Go tidak mendukung wildcard dengan akhiran `:aksi`, jadi rute menerima `POST /v1/credentials/{aksi}` lalu memisahkan `<hex>:<aksi>`.

1. `POST /v1/credentials/{cred}:challenge`
   - 201 `{"nonce": base64(32 B acak), "expires_at": RFC 3339}`, berlaku 120 dtk.
   - 404 `CRED-NOT-FOUND` bila `cred_id` tidak dikenal; 409 `CRED-NOT-RENEWABLE` bila kredensial atau card instance tidak ACTIVE.
2. `POST /v1/credentials/{cred}:renew`
   - Header `Idempotency-Key` wajib (SDD §8.5). Body `{"nonce": base64, "signature": base64(r‖s 64 B)}`.
   - Pesan yang ditandatangani: `"ANP1-RENEW"` ‖ `cred_id` (16 B) ‖ `nonce` (32 B). Prefix memisahkan domain dari transcript ANP/1.
   - Urutan cek dalam satu transaksi (`SELECT … FOR UPDATE` pada baris kredensial): kredensial ada (404) → ACTIVE dan card instance ACTIVE (409 `CRED-NOT-RENEWABLE`) → nonce milik kredensial ini, belum dipakai, belum kedaluwarsa (400 `CRED-CHALLENGE-INVALID`) → tanda tangan valid untuk `pubkey` tersimpan (400 `CRED-PROOF-INVALID`).
   - Nonce ditandai terpakai hanya bila perpanjangan sukses (transaksi gagal = rollback).
   - Sertifikat baru: `cred_id`, `pubkey`, dan kanal sama; zona dan masa berlaku diambil dari kebijakan gedung saat ini; `not_before` = sekarang.
   - 200 dengan JSON yang sama seperti provisioning (`ProvisionedCredential`).
3. Respons provisioning dan perpanjangan menambah `not_before` (RFC 3339). Penambahan ini kompatibel ke belakang.

## App

- `ProvisionedCredential.notBefore: Date?`. `CredentialRecord` menambah `notBefore: Date?` dan `renewalURL: URL?`, yaitu base URL backend penerbit. Record lama tanpa kedua field tetap terbaca. *Keputusan builder:* URL disimpan per kredensial karena app belum punya konfigurasi backend global, dan kredensial terikat ke region asalnya (ADR-0014). `renewalURL` nil (kartu `lab_ca.py`) berarti tidak diperpanjang.
- `RenewalPolicy.need(notBefore:notAfter:now:) -> .none | .soon | .expired`:
  - `.expired` bila `now ≥ notAfter`;
  - `.soon` bila `now ≥ notBefore + (notAfter − notBefore)/2`, atau bila `notBefore` tidak ada, `now ≥ notAfter − 3,5 hari`.
- `CredentialRenewer.renew(card:channel:context:)` menjalankan challenge → tanda tangan (`keys.signer(for:context:)`) → renew. Respons divalidasi: `cred_id` dan kanal harus sama. Record disimpan dulu, lalu kartu diperbarui (`notAfter`, `zones`). Bila gagal di langkah mana pun, record lama tetap utuh.
- Coordinator BLE dan HCE mendapat hook `prepare(AuthorizedContext) async`. Hook dipanggil setelah autentikasi sukses dan sebelum `makeProvider`.
  - `LivePresentationLauncher` memakai hook ini untuk `.expired`: perpanjangan ditunggu maksimal 5 dtk; bila gagal, tap tetap lanjut dan gagal tertutup (`.denied(.expired)`).
  - Untuk `.soon`, konteks disimpan lalu perpanjangan dijalankan setelah aliran event tap selesai. *Keputusan builder:* cara ini menghindari dua operasi tanda tangan bersamaan pada satu `LAContext`; konteks dilepas setelah perpanjangan.
- Lab (DEBUG): `provisionViaBackend` menyimpan `renewalURL` dan `notBefore`. Detail kartu mendapat aksi "Perpanjang sekarang (lab)" untuk verifikasi di simulator, yang tidak punya autentikasi biometrik.

## Dokumen yang ikut berubah

- SDD §5.5 (ADR-0023), §8.4.2 (challenge + format pesan), §8.5 (dua endpoint), §15 (kode `CRED-*` baru).
- QA TC-DEV-09: "diperpanjang pada tap berikutnya tanpa prompt tambahan"; §11.1 hasil; README.

## Diserahkan ke builder

Nama tipe/berkas internal, bentuk tabel nonce, dan cara membungkus aliran event untuk pemicu setelah tap.
