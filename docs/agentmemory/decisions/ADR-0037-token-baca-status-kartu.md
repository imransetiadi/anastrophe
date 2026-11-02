---
type: decision
project: anastrophe
date: 2026-11-01
adr: ADR-0037
jev: status_read_token
confidence: 0.96
status: Diterima
---
# ADR-0037 — Token baca status kartu

- **Masalah:** app perlu tahu status kartu dari server tanpa push. Tanda tangan kunci kredensial memunculkan Face ID, dan `:challenge` tidak terautentikasi.
- **Keputusan:** token baca status 32 byte per card instance, dibuat app, hanya hash-nya di server, dipakai sebagai bearer untuk `GET /v1/cards/{id}/status` saat app masuk foreground.
- **Dokumen lengkap:** `docs/adr/0037-token-baca-status-kartu.md`.
