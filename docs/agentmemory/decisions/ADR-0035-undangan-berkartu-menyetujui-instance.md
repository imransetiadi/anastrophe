---
type: decision
project: anastrophe
date: 2026-11-01
adr: ADR-0035
jev: promote_existing
confidence: 0.94
status: Diterima
---
# ADR-0035 — Undangan berkartu menyetujui instance yang belum selesai

- **Masalah:** perangkat yang sudah memegang instance `PENDING_APPROVAL`/`PROVISIONING` untuk kartu A buntu dengan `ENR-DUPLICATE` saat memakai undangan untuk kartu A (review akhir undangan I1).
- **Keputusan:** undangan menjadi persetujuan operator: instance itu menjadi `PROVISIONING`, terhubung ke undangan, dengan audit `enrollment.approved` (aktor perangkat, metode undangan). Respons 200; tidak ada instance baru.
- **Dokumen lengkap:** `docs/adr/0035-undangan-berkartu-menyetujui-instance.md`.
- **Sesi:** [Enrolment via undangan](../sessions/2026-11-01-undangan.md)
