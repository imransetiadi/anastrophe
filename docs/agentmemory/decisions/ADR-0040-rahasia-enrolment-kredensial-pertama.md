---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0040
jev: secret_first_block_add_channel
confidence: 0.83
status: Diterima
---
# ADR-0040 — Rahasia enrolment untuk kredensial pertama

- **Masalah:** provisioning hanya dilindungi id instance yang bocor lewat `:challenge`; reviewer menambah kanal ke kartu aktif orang lain.
- **Keputusan:** app mengirim hash rahasia 32 byte saat enrolment; provisioning kredensial pertama wajib membawa rahasianya; tambah kanal ke instance ACTIVE ditolak.
- **JEV:** ronde 24 tereskalasi (0,43); ronde 25 dengan bukti baru (app tidak pernah menambah kanal) → 0,83.
- **Dokumen lengkap:** `docs/adr/0040-rahasia-enrolment-kredensial-pertama.md`.
