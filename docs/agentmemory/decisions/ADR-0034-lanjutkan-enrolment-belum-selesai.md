---
type: decision
project: anastrophe
date: 2026-11-01
adr: ADR-0034
jev: resume_plus_expiry
confidence: 0.81
status: Diterima
---
# ADR-0034 — Enrolment yang belum selesai dilanjutkan

- **Masalah:** perangkat yang gagal di langkah kredensial, atau yang baru disetujui operator, buntu dengan `ENR-DUPLICATE` terhadap instance-nya sendiri.
- **Keputusan:** instance `PROVISIONING`/`PENDING_APPROVAL` milik perangkat yang sama dilanjutkan (200, `enrollment_id` sama). `PROVISIONING` tanpa kredensial menjadi `ABANDONED` setelah 15 menit.
- **Dokumen lengkap:** `docs/adr/0034-lanjutkan-enrolment-belum-selesai.md`.
- **Sesi:** [Registri kartu fisik](../sessions/2026-11-01-registri-kartu.md)
