---
type: decision
project: anastrophe
date: 2026-11-01
adr: ADR-0031
jev: registry_enrolment_server
confidence: 0.88
status: Diterima
---
# ADR-0031 — Iterasi berikutnya: registri kartu fisik dan pencocokan enrolment

- **Masalah:** fitur besar yang tersisa bergantung pada akun, hardware, atau penyedia eksternal yang belum tersedia.
- **Keputusan:** bangun registri kartu fisik (HMAC per gedung), impor lewat CLI operator, dan pencocokan di `POST /v1/enrollments` dengan alasan FR-13.
- **Dokumen lengkap:** `docs/adr/0031-fokus-registri-enrolment-server.md` · log JEV round 15.
- **Sesi:** [Minor riwayat tap, fokus registri, push ke GitHub](../sessions/2026-11-01-minor-riwayat-tap-dan-registri.md)
