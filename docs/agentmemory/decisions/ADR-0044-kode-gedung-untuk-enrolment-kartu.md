---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0044
jev: accept
confidence: 0.96
status: Diterima
---
# ADR-0044 — Kode gedung untuk enrolment kartu fisik

- **Pilihan:** `sites.join_code` (8 simbol Crockford base32, `XXXX-XXXX`) + `GET /v1/sites/lookup` (404 `SITE-NOT-FOUND` identik) + CLI `site-code`. Penghuni mengonfirmasi nama gedung sebelum menempel kartu.
- **Ditolak:** kode tanpa lookup (nama tidak terkonfirmasi), tautan gedung (teks panjang), dan daftar gedung publik (membuka daftar pelanggan).
- **Catatan:** kode bukan rahasia; rotasi membuat kode lama tidak berlaku. Pembatasan laju diserahkan ke infrastruktur.
- **Dokumen lengkap:** `docs/adr/0044-kode-gedung-untuk-enrolment-kartu.md`.
