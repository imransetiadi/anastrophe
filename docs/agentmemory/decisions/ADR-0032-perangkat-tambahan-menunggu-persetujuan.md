---
type: decision
project: anastrophe
date: 2026-11-01
adr: ADR-0032
jev: pending_for_additional
confidence: 0.71
status: Diterima (provisional)
---
# ADR-0032 — Sebelum ada akun, perangkat tambahan menunggu persetujuan

- **Masalah:** kartu fisik hanya bukti kepemilikan lemah, dan pencocokan kontak maupun security code belum mungkin tanpa akun.
- **Keputusan:** perangkat pertama mendapat `PROVISIONING`; perangkat lain untuk kartu yang sama mendapat `PENDING_APPROVAL` yang disetujui atau ditolak lewat CLI operator. Ditinjau ulang saat fondasi akun dibangun.
- **Dokumen lengkap:** `docs/adr/0032-perangkat-tambahan-menunggu-persetujuan.md` · log JEV round 16.
- **Sesi:** [Minor riwayat tap, fokus registri, push ke GitHub](../sessions/2026-11-01-minor-riwayat-tap-dan-registri.md)
