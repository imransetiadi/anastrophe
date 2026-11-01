# ADR-0025: Audit pseudonim sejak ditulis

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-54, NFR-PR03, SDD §8.4.6 dan inventaris data, ADR-0024, CLAUDE.md aturan 6

## Konteks

SDD meminta baris audit dipseudonimkan saat akun dihapus (HMAC user id) dan disimpan 1 tahun (≤ 5 tahun bila diwajibkan). Log audit ADR-0024 append-only: trigger menolak UPDATE/DELETE, dan verifikasi menghitung ulang dari seq 1.

Pseudonimisasi lewat UPDATE terblokir trigger, dan bila trigger dimatikan, verifikasi rusak. Memangkas baris terlama juga membuat verifikasi gagal di seq 1. Belum ada baris produksi, jadi format masih bisa ditetapkan sekarang.

## Keputusan

**Audit hanya menulis identitas pseudonim sejak awal.**

- Aktor dan subjek berupa ID pseudonim: UUID perangkat dan card instance serta `cred_id` hex saat ini. Identitas pengguna atau admin kelak memakai pseudonim HMAC per gedung yang dihitung saat menulis, dengan kunci di luar tabel audit.
- Hapus akun memusnahkan pemetaan pengguna → pseudonim, bukan menulis ulang baris audit.
- Retensi memangkas segmen awal secara utuh. Verifikasi dilanjutkan dari checkpoint `(seq, hash)` yang dicatat sebelum pemangkasan.

## Konsekuensi

- Baris audit tetap tidak berubah dan hash tetap valid setelah hapus akun.
- Tidak ada jalur UPDATE pada `audit_events` dalam operasi normal.
- Mekanisme checkpoint dan pemangkasan retensi dibangun bersama fitur retensi (belum diimplementasikan). Event saat ini tidak memuat data pribadi.
- Pseudonim HMAC dan kuncinya mengikuti praktik HMAC per gedung yang sudah dipakai untuk identitas kartu (CLAUDE.md aturan 6).

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** How should Anastrophe's append-only, per-site hash-chained audit log (ADR-0024) satisfy the SDD rules that audit rows are pseudonymized on account deletion (HMAC user id, NFR-PR03) and retained 1 year (≤ 5 years), given that rows cannot be updated and verification currently starts at seq 1?
- **Prioritas yang diberikan:** penuhi aturan privasi SDD/NFR-PR03; baris audit tetap tidak berubah dan dapat diverifikasi; sederhana dan konsisten dengan praktik HMAC per gedung; putuskan sebelum ada baris produksi.
- **Hasil:** `pseudonymous_at_write` · confidence **0.96** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round9.input.json`](jev-log/2026-11-01-round9.input.json), [`jev-log/2026-11-01-round9.output.json`](jev-log/2026-11-01-round9.output.json)

| Kandidat | Probabilitas |
|---|---|
| `pseudonymous_at_write` | 0.97 |
| `crypto_shredding` | 0.01 |
| `hash_identity_digests` | 0 |
