---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0039
jev: secure_provisioning
confidence: 0.92
status: Diterima
---
# ADR-0039 — Fokus berikutnya: provisioning kredensial yang aman

- **Masalah:** provisioning kredensial hanya dilindungi id card instance, yang dibocorkan `:challenge` kepada pemegang `cred_id`.
- **Keputusan:** provisioning harus membuktikan asalnya dari perangkat yang memulai enrolment; mekanisme dipilih di spesifikasi.
- **Dokumen lengkap:** `docs/adr/0039-fokus-provisioning-aman.md`.
