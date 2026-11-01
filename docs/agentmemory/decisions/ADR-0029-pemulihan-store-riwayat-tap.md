---
type: decision
project: anastrophe
date: 2026-11-01
adr: ADR-0029
jev: reset_on_corruption_only
confidence: 0.87
status: Diterima
---
# ADR-0029 — Store riwayat tap dibuat ulang hanya bila rusak atau tak termigrasi

- **Masalah:** store riwayat yang gagal dibuka membuat seluruh app jatuh ke mode "penyimpanan tidak tersedia" tanpa kartu (temuan review I1).
- **Keputusan:** pembukaan riwayat tidak pernah gagal. Store dibuat ulang sekali hanya bila berkasnya rusak atau skemanya tidak cocok dengan model; galat lain memakai riwayat sementara di memori tanpa menghapus berkas.
- **Dasar teknis:** [SwiftDataError menyembunyikan galat Core Data](../lessons/swiftdata-galat-tersembunyi.md).
- **Dokumen lengkap:** `docs/adr/0029-pemulihan-store-riwayat-tap.md` · log JEV round 13.
- **Sesi:** [Perbaikan review riwayat tap](../sessions/2026-11-01-perbaikan-riwayat-tap.md)
