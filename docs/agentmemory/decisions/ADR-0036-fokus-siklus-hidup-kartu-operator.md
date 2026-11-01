---
type: decision
project: anastrophe
date: 2026-11-01
adr: ADR-0036
jev: operator_lifecycle_status
confidence: 0.98
status: Diterima
---
# ADR-0036 — Fokus berikutnya: siklus hidup kartu oleh operator

- **Masalah:** operator belum bisa menangguhkan, memulihkan, atau mencabut kartu (FR-51), dan app tidak pernah menerima status itu dari server (FR-38).
- **Keputusan:** CLI suspend/resume/revoke dengan audit dan denylist, ditambah sinkron status kartu ke app.
- **Dokumen lengkap:** `docs/adr/0036-fokus-siklus-hidup-kartu-operator.md`.
