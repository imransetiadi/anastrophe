---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0041
jev: escalate
confidence: 0.44
status: Diusulkan (eskalasi)
---
# ADR-0041 — Pengambilalihan enrolment yang belum selesai (terbuka)

- **Masalah:** pihak yang tahu `device_id` dan identitas kartu (atau token undangan) bisa mengganti hash rahasia enrolment instance yang belum selesai lalu memprovisikannya (review akhir provisioning aman I1).
- **JEV:** `first_writer_wins` 0,53 / `document_residual_risk` 0,22 / `replace_with_old_secret` 0,22; confidence 0,44, jadi **menunggu keputusan pengguna**.
- **Rekomendasi:** `first_writer_wins`.
- **Dokumen lengkap:** `docs/adr/0041-pengambilalihan-enrolment-belum-selesai.md`.
