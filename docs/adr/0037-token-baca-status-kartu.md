# ADR-0037: App membaca status kartu dengan token baca status

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-25, FR-38, FR-51, ADR-0009, ADR-0026, ADR-0036, SDD §5.3, §8.4.2

## Konteks

App perlu tahu bila operator menangguhkan, memulihkan, atau mencabut kartunya (ADR-0036), sementara push (FR-62) belum tersedia. Ada tiga batasan:

- Kunci kredensial wajib `.userPresence` (aturan 5, ADR-0009). Di iPhone, setiap tanda tangan memunculkan Face ID atau passcode, jadi pemeriksaan bertanda tangan saat app dibuka akan terus meminta autentikasi.
- `:challenge` tidak terautentikasi dan sudah membedakan kartu dicabut (410). Menambahkan status ke sana membuat siapa pun yang tahu `cred_id` bisa membedakan kartu ditangguhkan. `cred_id` terlihat oleh setiap reader.
- Perpanjangan baru terjadi setelah tap atau menjelang kedaluwarsa (ADR-0023), jadi bisa terlambat berhari-hari.

## Keputusan

Setiap card instance punya **token baca status** 32 byte acak, dipakai sebagai bearer untuk `GET /v1/cards/{id}/status`.

- Server hanya menyimpan SHA-256 token. App menyimpan token di Keychain dengan `afterFirstUnlockThisDeviceOnly`, sehingga token bisa dibaca tanpa kehadiran pengguna dan tidak ikut backup (SDD §5.3).
- App memeriksa status saat masuk foreground, dibatasi frekuensinya dan hanya saat online. Status lokal diperbarui: `SUSPENDED` → Ditangguhkan, `REVOKED` → Dicabut, `ACTIVE` memulihkan kartu yang ditangguhkan. Presentasi tidak menunggu pemeriksaan ini dan tetap berjalan offline dengan status terakhir (FR-25).
- Card id tak dikenal, token salah, dan tanpa token dijawab identik.
- *Penyempurnaan builder:* token dibuat oleh app. Hash-nya dikirim saat provisioning kredensial, dan boleh diganti saat perpanjangan yang sudah bertanda tangan. Respons provisioning dan perpanjangan disimpan utuh di tabel idempotency, jadi token yang diterbitkan server akan tersimpan mentah di database. Dengan hash dari app, token mentah tidak pernah melewati server kecuali saat pemeriksaan status, dan tidak pernah disimpan.

## Konsekuensi

- Status kartu di app mengikuti server tanpa prompt autentikasi dan tanpa menunggu tap.
- Pihak yang hanya tahu `cred_id` atau `device_id` tidak mendapat informasi baru.
- Kartu yang diprovisikan sebelum fitur ini mendapat token pada perpanjangan berikutnya.
- Token yang dicuri hanya bisa membaca status kartu itu.

## Pembaruan setelah review akhir (2026-11-02)

- **Provisioning tidak mengganti hash** (review I1). `POST /v1/enrollments/{id}/credentials` hanya dilindungi id card instance, yang dikembalikan `:challenge` kepada siapa pun yang tahu `cred_id`. Karena itu provisioning hanya memasang hash bila instance belum punya. Penggantian hanya lewat `:renew`.
- **App memulihkan diri.** Bila server menjawab `CARD-NOT-FOUND` untuk token yang ada, app menghapus token lokal, sehingga perpanjangan berikutnya memasang token baru. Provisioning memakai ulang token yang sudah ada untuk instance itu.
- **`:renew` tidak membocorkan penangguhan** (review M2). Status dan kill switch diperiksa setelah nonce dan tanda tangan valid, sehingga tanpa kunci kredensial kartu ditangguhkan dan aktif dijawab sama.
- **Koreksi kata** (review M9). Tanda tangan perpanjangan mencakup `cred_id` dan nonce, tetapi tidak `status_token_hash`. Permintaan itu hanya bisa dibuat pemegang kunci, sedangkan integritas hash di dalamnya bergantung pada TLS.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** How should the app learn the server-side status of its cards without push?
- **Prioritas yang diberikan:** keamanan dan privasi; tanpa prompt di luar tindakan pengguna; tepat waktu saat online; API minimal dan pola yang ada.
- **Hasil:** `status_read_token` · confidence **0.96** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round21.input.json`](jev-log/2026-11-01-round21.input.json), [`jev-log/2026-11-01-round21.output.json`](jev-log/2026-11-01-round21.output.json)

| Kandidat | Probabilitas |
|---|---|
| `status_read_token` | 0.97 |
| `signed_status_on_user_action` | 0 |
| `challenge_reports_status` | 0 |
| `renewal_time_only` | 0 |
| `none` | 0.03 |
