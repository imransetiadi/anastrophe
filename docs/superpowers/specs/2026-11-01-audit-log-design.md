# Audit log berantai hash (FR-54) — desain

**Status:** keputusan cakupan rantai lewat JEV (ADR-0024, `per_site_chain`, 0,95). Pengguna melewati sesi tanya-jawab; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

Operator gedung perlu jejak tak terubah atas siapa melakukan apa dan kapan terhadap kredensial (FR-54). Jejak ini juga menjadi mitigasi ancaman "penyalahgunaan admin" (SDD §11). Backend saat ini belum mencatat apa pun.

## Tujuan

1. Tabel `audit_events` append-only dengan rantai hash per gedung, ditambah rantai `platform` untuk event tanpa gedung.
2. Event dicatat **dalam transaksi yang sama** dengan perubahan bisnisnya: bila audit gagal, perubahan dibatalkan.
3. Fungsi verifikasi yang menunjuk baris pertama yang rusak.
4. Event iterasi ini: `enrollment.started`, `credential.provisioned`, `credential.renewed`.

## Non-goal (rencana berikutnya)

- `GET /admin/sites/{id}/audit` dan RBAC portal: butuh autentikasi admin.
- Event suspend/resume/revoke: endpoint admin belum ada.
- Penandatanganan atau anchoring hash ke pihak ketiga, serta retensi/arsip.

## Anti-goal

- Menyimpan identitas kartu fisik mentah, kontak, atau lokasi GPS (CLAUDE.md aturan 6, FR-54).
- Baris audit yang bisa diubah atau dihapus lewat jalur aplikasi.
- Satu kunci tulis global untuk semua gedung (ADR-0024).

## Model data (migrasi `0005_audit_events.sql`)

`audit_events(id bigserial pk, chain text, site_id uuid null → sites, seq bigint, at timestamptz, actor text, action text, subject text, data jsonb, prev_hash bytea(32), hash bytea(32))`

- `UNIQUE (chain, seq)`.
- `chain` = `site:<uuid>` atau `platform`. *Keputusan builder:* teks tunggal memudahkan keunikan, karena NULL di `site_id` tidak ikut constraint unik.
- Trigger `BEFORE UPDATE OR DELETE` menolak perubahan apa pun (append-only).

## Hash

- `hash = SHA-256("ANP1-AUDIT" ‖ prev_hash ‖ u64be(seq) ‖ field(chain) ‖ field(at RFC 3339 nano UTC) ‖ field(actor) ‖ field(action) ‖ field(subject) ‖ field(data kanonik))`.
- `field(x)` = panjang u32be ‖ byte UTF-8. Data kanonik = JSON dengan kunci terurut.
- Baris pertama setiap rantai memakai `prev_hash` = 32 byte nol, dengan `seq` mulai dari 1.
- *Keputusan builder:* encoding biner berawalan panjang menghindari ambiguitas pemisah. Waktu dipotong ke mikrodetik agar sama dengan presisi `timestamptz`.

## Penambahan

`(*Tx).AppendAudit(ctx, Event{SiteID, Actor, Action, Subject, Data, At})` berjalan dalam transaksi pemanggil:

1. `pg_advisory_xact_lock(hashtext('audit:' || chain))`.
2. Baca `seq`/`hash` terakhir rantai itu.
3. Hitung hash baru, lalu sisipkan.

Dua transaksi pada gedung yang sama berjalan berurutan; gedung berbeda berjalan paralel.

## Isi event

| Event | `subject` | `actor` | `data` |
|---|---|---|---|
| `enrollment.started` | `card_instance:<id>` | `device:<id>` | `{}` |
| `credential.provisioned` | `credential:<cred_id hex>` | `device:<id>` | `{"channel","not_after"}` |
| `credential.renewed` | `credential:<cred_id hex>` | `device:<id>` | `{"channel","not_after"}` |

## Verifikasi

`(*Store).VerifyAuditChain(ctx, chain) (rows int, err error)` menghitung ulang semua hash. Hasilnya `ErrAuditTampered`, berisi `seq` pertama yang tidak cocok, bila ada baris yang diubah, dihapus (lompatan `seq`), atau disisipkan.

## Diserahkan ke builder

Nama berkas dan fungsi internal, serta letak helper hash.
