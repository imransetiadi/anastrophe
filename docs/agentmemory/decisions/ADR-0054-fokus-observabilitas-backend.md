---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0054
jev: accept
confidence: 0.99
status: Diterima
---
# ADR-0054 — Fokus berikutnya: observabilitas backend (NFR-O01 sebagian)

- **Pilihan:** log akses terstruktur dengan request id tanpa data pribadi, korelasi log galat, dan metrik teks Prometheus di listener internal. Semuanya memakai stdlib saja.
- **Di luar cakupan:** pengiriman log terpusat, alert, on-call, dan tracing (infrastruktur).
- **Dokumen lengkap:** `docs/adr/0054-fokus-observabilitas-backend.md`. Sesi: [observabilitas backend](../sessions/2026-11-02-observabilitas-backend.md).
