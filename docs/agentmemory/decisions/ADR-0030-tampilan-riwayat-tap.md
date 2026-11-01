---
type: decision
project: anastrophe
date: 2026-11-01
adr: ADR-0030
jev: inline_recent_plus_all
confidence: 0.95
status: Diterima
---
# ADR-0030 — Detail kartu: lima tap terbaru dan riwayat 30 hari

- **Masalah:** detail hanya menampilkan 20 baris di bawah judul "30 hari"; entri yang lebih lama tersimpan tetapi tidak bisa dibuka (temuan review I2).
- **Keputusan:** lima tap terbaru tampil di detail; bila lebih dari lima, baris "Lihat semua" (dengan jumlah entri) membuka seluruh riwayat 30 hari. Pengaturan → Hapus kartu tetap dekat.
- **Dokumen lengkap:** `docs/adr/0030-tampilan-riwayat-tap.md` · log JEV round 14.
- **Sesi:** [Perbaikan review riwayat tap](../sessions/2026-11-01-perbaikan-riwayat-tap.md)
