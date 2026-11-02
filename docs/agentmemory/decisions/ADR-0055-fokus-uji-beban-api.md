---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0055
jev: accept
confidence: 0.95
status: Diterima
---
# ADR-0055 — Fokus berikutnya: uji beban API dan baseline lab (TC-PERF-05)

- **Pilihan:** generator beban Go (stdlib) dengan skenario config, lookup kode gedung, enrolment + provisioning, dan perpanjangan. Alat ini hanya memakai kartu sintetis, hanya menembak loopback kecuali diizinkan eksplisit, dan membaca porsi ≤ 0,3 dtk dari histogram `/metrics` server.
- **Sesudah review akhir:** redirect tidak diikuti, enrol mengikuti jalur app (`Idempotency-Key`, `status_token_hash`), token laju yang terlewat dan run yang berhenti lebih awal terlihat di laporan dan exit code.
- **Di luar cakupan:** uji 1.000 rps campuran dan uji rendam, yang menunggu lingkungan Load (NFR-O02).
- **Dokumen lengkap:** `docs/adr/0055-fokus-uji-beban-api.md`. Sesi: [uji beban API](../sessions/2026-11-02-uji-beban-api.md).
