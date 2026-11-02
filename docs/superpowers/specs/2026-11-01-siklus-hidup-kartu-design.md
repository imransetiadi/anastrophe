# Siklus hidup kartu oleh operator dan status kartu di app (FR-51, FR-38) — desain

**Status:** fokus dari ADR-0036 (JEV 0,98); mekanisme status dari ADR-0037 (JEV 0,96). Pengguna memakai mode iterasi otomatis dan melewati sesi tanya-jawab; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

Operator baru bisa menyetujui atau menolak perangkat tambahan. Kartu yang hilang, disalahgunakan, atau milik penghuni yang pindah belum bisa ditangguhkan atau dicabut (FR-51, P0). App punya status Ditangguhkan dan Dicabut, tetapi tidak pernah menerimanya dari server (FR-38, P0). Iterasi ini menutup keduanya tanpa portal admin dan tanpa push.

## Tujuan

1. CLI `anastrophe-registry`: `list`, `suspend`, `resume`, dan `revoke` card instance, dengan audit.
2. Kredensial mengikuti status instance. Kredensial yang dicabut dicatat di `denylist_entries` untuk sinkron reader nanti (SDD §8.4.3).
3. Token baca status (ADR-0037): app membuat token, server menyimpan hash-nya, dan `GET /v1/cards/{id}/status` menjawab status instance.
4. App memperbarui status kartu saat masuk foreground. Kartu Ditangguhkan atau Dicabut tidak bisa dipresentasikan.

## Non-goal

- Sinkron denylist ke reader (menunggu ADR-0022), push (FR-62), portal admin dan RBAC (FR-50 penuh, FR-56), lost mode oleh pengguna (FR-42), dan Apple Access Platform (kanal W).
- Penegakan penangguhan di reader offline. Kredensial `SUSPENDED` tidak bisa diperpanjang sehingga kedaluwarsa dalam ≤ 7 hari (ADR-0010); denylist hanya untuk kredensial yang dicabut.

## Anti-goal

- Token baca status mentah tersimpan di database, log, audit, atau baris idempotency.
- Endpoint status yang membedakan card id tak dikenal, token salah, dan tanpa token.
- Prompt Face ID atau passcode untuk memeriksa status.
- Presentasi yang menunggu jaringan (FR-25).

## Model data (migrasi `0010`)

- `card_instances.status_token_hash bytea null` (SHA-256 token, 32 byte).
- `denylist_entries(site_id uuid → sites, cred_id bytea, revoked_at timestamptz, expires_at timestamptz, primary key (site_id, cred_id))`. `expires_at` = `not_after` sertifikat kredensial, sehingga denylist tidak tumbuh tanpa batas (SDD §8.1).

## Transisi status oleh operator

| Perintah | Dari | Ke | Kredensial | Audit |
|---|---|---|---|---|
| `suspend` | `ACTIVE` | `SUSPENDED` | `ACTIVE` → `SUSPENDED` | `card.suspended` |
| `resume` | `SUSPENDED` | `ACTIVE` | `SUSPENDED` → `ACTIVE` | `card.resumed` |
| `revoke` | `ACTIVE`, `SUSPENDED`, `PROVISIONING` | `REVOKED` | `ACTIVE`/`SUSPENDED` → `REVOKED` dengan `revoked_at` dan `revoke_reason`, lalu masuk denylist | `card.revoked` `{reason, credentials}` |

- Status lain ditolak tanpa perubahan dan tanpa audit. `PENDING_APPROVAL` memakai `reject`.
- Baris instance dikunci `FOR UPDATE`, dan semuanya terjadi dalam satu transaksi. Aktor audit `operator:<pegangan>`.
- Alasan pencabutan berupa kode pendek `[a-z_]{1,32}`, default `operator`. Teks bebas tidak diterima karena audit bersifat append-only dan tidak boleh memuat data pribadi.
- *Keputusan builder:* hapus kartu oleh pengguna (ADR-0026) memakai helper pencabutan yang sama, sehingga kredensialnya juga masuk denylist.
- Instance `REVOKED` tidak lagi dihitung aktif, jadi slot batas 8 kartu terbebas. Perpanjangan sudah menolak instance dan kredensial yang tidak `ACTIVE` (SDD §8.4.2).

## CLI

- `anastrophe-registry list --site <uuid> [--status <STATUS>]`: satu baris per card instance berisi id, status, kanal kredensial aktif, waktu dibuat, dan asal (`kartu`, `undangan`, atau `-`). Tidak ada identitas kartu, kontak, maupun id perangkat utuh. *Keputusan builder:* operator butuh id instance untuk `approve`, `suspend`, `resume`, dan `revoke` (bagian kecil FR-50).
- `anastrophe-registry suspend|resume --card-instance <uuid> --operator <pegangan>`
- `anastrophe-registry revoke --card-instance <uuid> [--reason <kode>] --operator <pegangan>`

## Token baca status (ADR-0037)

- App membuat 32 byte acak per card instance dan menyimpannya di Keychain dengan `afterFirstUnlockThisDeviceOnly`, dengan kunci per id card instance server.
- Provisioning `POST /v1/enrollments/{id}/credentials` menerima field opsional `status_token_hash` (base64 dari 32 byte) dan memasangnya hanya bila instance belum punya hash (review akhir I1: id instance bukan rahasia). Field ini opsional agar klien lama tetap berfungsi, dan app memakai ulang token yang sudah ada untuk instance itu.
- Perpanjangan `POST /v1/credentials/{cred}:renew` menerima field opsional yang sama. Permintaan ini sudah bertanda tangan kunci kredensial. App mengirimnya bila kartu belum punya token, misalnya kartu yang diprovisikan sebelum fitur ini.
- Hash idempotency kedua endpoint mencakup `status_token_hash`, sehingga pengulangan dengan hash berbeda tidak memakai respons lama.
- `GET /v1/cards/{id}/status` dengan header `Authorization: Bearer <token base64url>`:
  - 200 `{"status": "<status instance>"}` bila SHA-256 token cocok, dengan perbandingan waktu-konstan.
  - Id bukan UUID atau tidak dikenal, header hilang atau rusak, token salah, atau instance tanpa token → 404 `CARD-NOT-FOUND` dengan body yang sama.
  - Tidak ada audit karena hanya membaca, dan token tidak pernah di-log.

## App

- `CardStatusRefresher` memeriksa setiap kartu yang punya token, `serverCardID`, dan `renewalURL`, lalu memperbarui status lokal:
  - `SUSPENDED` → Ditangguhkan;
  - `REVOKED` atau `DELETED` → Dicabut;
  - `ACTIVE` → Aktif, hanya bila status lokal Ditangguhkan. Status lokal lain seperti "Perlu dipindahkan" tidak ditimpa.
  - Galat jaringan atau 404 → status lokal tetap. Pada 404 `CARD-NOT-FOUND`, token lokal dihapus agar perpanjangan berikutnya memasang token baru (review akhir I1).
- Pemeriksaan berjalan saat app masuk foreground dan saat layar Kunci pertama dimuat, paling sering sekali per 60 detik (*keputusan builder*). Presentasi tidak menunggunya.
- Token dibuat saat provisioning dan, bila belum ada, saat perpanjangan. Hapus kartu juga menghapus tokennya.
- Token dibaca tanpa `LAContext`, jadi tidak ada prompt autentikasi.

## Review Focus

1. Endpoint status: id tak dikenal, token salah, dan tanpa token dijawab identik.
2. Token mentah tidak muncul di database, log, audit, atau baris idempotency.
3. Transisi ilegal (resume dari `ACTIVE`, suspend dari `PENDING_APPROVAL`, apa pun dari `REVOKED`) ditolak tanpa perubahan dan tanpa audit.
4. Revoke: kredensial dan denylist konsisten, slot batas 8 kartu terbebas, dan perpanjangan ditolak setelah suspend atau revoke.
5. App: status server tidak menimpa "Perlu dipindahkan", offline mempertahankan status terakhir, dan presentasi diblokir untuk kartu Ditangguhkan atau Dicabut.

## Diserahkan ke builder

Nama berkas dan fungsi, format keluaran `list`, serta nama kunci Keychain.
