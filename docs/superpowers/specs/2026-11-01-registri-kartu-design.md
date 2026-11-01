# Registri kartu fisik dan pencocokan enrolment (FR-11 sisi server, FR-13, FR-52) — desain

**Status:** fokus dari ADR-0031 (JEV 0,88). Aturan perangkat tambahan dari ADR-0032 (JEV 0,71, provisional). Pengguna memakai mode iterasi otomatis dan melewati sesi tanya-jawab; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

Enrolment R1 harus berangkat dari kartu fisik yang terdaftar di registri gedung (FR-11). Saat ini backend membuat card instance untuk perangkat dan gedung apa pun tanpa memeriksa kartu. Registri menutup celah itu dan memberi alasan spesifik bila kartu tidak didukung (FR-13).

## Tujuan

1. Tabel `physical_cards` (SDD §8.1): HMAC identitas kartu dan kontak pemegang per gedung, zona per kartu, dan status.
2. Kunci HMAC per gedung di balik antarmuka. Produksi memakai KMS; lokal memakai kunci dev.
3. CLI operator `anastrophe-registry`: `import` dari CSV, serta `approve`/`reject` untuk card instance `PENDING_APPROVAL` (ADR-0032).
4. `POST /v1/enrollments` menerima identitas kartu, mencocokkan HMAC, lalu menjawab dengan alasan FR-13 atau status `PROVISIONING`/`PENDING_APPROVAL`.
5. Sertifikat memakai zona kartu terdaftar, *fail-closed* bila bitmap 0.
6. App: permintaan enrolment membawa identitas kartu; alur lab mengirim identitas lab; pesan alasan FR-13 dalam ID dan EN.

## Non-goal

- Akun, pencocokan kontak, peran PRIMARY/MEMBER, dan security code (iterasi akun).
- Pembaca `NFCTagReaderSession` live, yang butuh iPhone dan entitlement. Hanya protokol dan mock.
- Undangan (FR-12), API admin HTTP, dan impor dari API ACS.

## Anti-goal

- Identitas kartu atau kontak mentah tersimpan atau tercatat di mana pun: database, log, galat, audit, atau keluaran CLI (CLAUDE.md aturan 6).
- UID dipakai sebagai faktor autentikasi (NFR-S02), atau kartu di-clone (aturan 1).
- Kunci HMAC di database atau repo (aturan 9).

## Identitas kartu kanonik (*keputusan builder*)

| `tech` | Kode | Isi `id` | Panjang |
|---|---|---|---|
| `iso14443a` | 1 | UID | 4, 7, atau 10 B |
| `iso15693` | 2 | UID | 8 B |
| `felica` | 3 | IDm | 8 B |
| `iso7816` | 4 | ID aplikasi dari profil baca gedung (`SELECT` AID) | 1–32 B |

- JSON: `"card": {"tech": "iso14443a", "id": "<hex>"}`. Panjang yang tidak sesuai dijawab 400 `REQ-INVALID`.
- Masukan MAC: `"ANP1-CARD-v1"` ‖ u8(kode) ‖ u8(panjang) ‖ id. Kode teknologi ikut di-MAC, jadi byte yang sama pada teknologi berbeda menghasilkan HMAC berbeda.

## Kontak pemegang (*keputusan builder*)

- Email: trim lalu huruf kecil. Telepon: hanya digit dengan awalan `+`, 8–15 digit (E.164).
- Masukan MAC: `"ANP1-CONTACT-v1"` ‖ kontak ternormalisasi. Disimpan sebagai `holder_contact_hmac` (opsional) untuk iterasi akun.

## Kunci per gedung

- Antarmuka `RegistryMAC.MAC(ctx, siteID, msg) ([]byte, error)` menghasilkan HMAC-SHA256 32 B.
- Produksi: operasi MAC di KMS sehingga kunci tidak keluar (SDD §11). Adapter menyusul.
- Lokal (*keputusan builder*): HKDF-SHA256 dari `ANASTROPHE_DEV_REGISTRY_KEY` (32 B hex), dengan info `"ANP1-REGISTRY-v1"` ‖ UUID gedung. `anastrophe-api` dan CLI menolak berjalan tanpa sumber kunci, sama seperti tanpa URL database.

## Model data (migrasi `0007_physical_cards.sql`)

- `physical_cards(id uuid pk, site_id → sites, card_id_hmac bytea(32), holder_contact_hmac bytea(32) null, zones_bitmap bigint default 0, status ACTIVE|REMOVED, created_at, updated_at, unique(site_id, card_id_hmac))`.
- `card_instances.physical_card_id → physical_cards` (null untuk data tracer lama). Status card instance bertambah `REJECTED`.
- *Keputusan builder:* `acs_card_number` belum disimpan sampai integrasi ACS. Kolom itu perlu ditinjau terhadap aturan 6.

## Enrolment

Permintaan: `{device_id, site_id, card: {tech, id}}`.

1. Validasi bentuk; gagal → 400 `REQ-INVALID`.
2. Perangkat atau gedung tidak dikenal → 404 `ENR-NOT-FOUND` (sudah ada). Gedung tanpa satu pun kartu aktif di registri → 404 `ENR-SITE-UNSUPPORTED` (*keputusan builder*).
3. Tidak ada kartu `ACTIVE` dengan HMAC itu → 404 `ENR-NOT-REGISTERED`. Kartu `REMOVED` dijawab sama persis.
4. Cocok → dalam satu transaksi, baris kartu dikunci (`FOR UPDATE`) dan batas 8 kartu tetap berlaku.
   - Perangkat ini sudah punya card instance aktif untuk kartu itu → 409 `ENR-DUPLICATE` (*keputusan builder*).
   - Perangkat lain punya card instance aktif → `PENDING_APPROVAL` (ADR-0032).
   - Selain itu → `PROVISIONING`.
   - "Aktif" berarti `PENDING_APPROVAL`, `PROVISIONING`, `ACTIVE`, atau `SUSPENDED`.
5. Respons 201: `{enrollment_id, status}`. Audit `enrollment.started` berisi `{status}`, tanpa identitas kartu.

Provisioning (`/credentials`) hanya untuk `PROVISIONING`; `PENDING_APPROVAL` dijawab 409 `ENR-PENDING-APPROVAL`. Zona sertifikat diambil dari `physical_cards.zones_bitmap` bila card instance tertaut, dan dari kebijakan gedung untuk data tracer lama.

## CLI operator `anastrophe-registry`

- `import --site <uuid> --file <csv>`, dengan kolom `tech,card_id,holder_contact,zones`.
  - `zones` berisi nama zona dipisah `;`, dipetakan ke bit lewat `sites.policy.zones`. Nama yang tidak dikenal membuat baris ditolak.
  - Upsert per (gedung, HMAC).
  - Laporan memuat jumlah ditambah, diperbarui, dan ditolak; penolakan disebut dengan nomor baris dan alasan, tanpa nilai mentah.
  - Audit `registry.imported` `{added, updated, rejected}` di rantai gedung.
- `approve|reject --card-instance <uuid> --operator <nama>`: `PENDING_APPROVAL` → `PROVISIONING` atau `REJECTED`, dengan audit `enrollment.approved|rejected`.

## App

- Permintaan enrolment membawa `CardIdentity(tech, id)`. Protokol `CardIdentityReading` punya mock untuk test; pembaca live menyusul (uji H).
- Alur lab memakai argumen `-ANLabCard <tech>:<hex>`, dan `anastrophe-devseed` mendaftarkan kartu yang sama.
- `ENR-NOT-REGISTERED`, `ENR-SITE-UNSUPPORTED`, `ENR-DUPLICATE`, dan status `PENDING_APPROVAL` dipetakan ke teks ID/EN (SDD §15).

## Review Focus

1. Identitas atau kontak mentah bocor ke database, log, galat, audit, atau keluaran CLI.
2. Dua perangkat mendaftarkan kartu yang sama bersamaan: tepat satu `PROVISIONING`, satu `PENDING_APPROVAL`.
3. Kartu `REMOVED` dijawab sama dengan kartu tak dikenal.
4. Kartu dengan bitmap zona 0 menghasilkan sertifikat yang tidak membuka zona apa pun.
5. Impor ulang CSV yang sama tidak menggandakan kartu.
6. Panjang identitas salah ditolak, dan byte yang sama pada teknologi berbeda tidak bertabrakan.

## Diserahkan ke builder

Nama berkas dan fungsi, struktur paket (mis. `internal/registry`), format laporan CLI.
