---
type: decision
project: anastrophe
date: 2026-11-01
adr: ADR-0033
jev: invitation_enrolment
confidence: 0.89
status: Diterima
---
# ADR-0033 — Iterasi berikutnya: enrolment via undangan

- **Masalah:** kartu yang tidak terbaca dan gedung tanpa registri belum punya jalur enrolment (FR-12, FR-13).
- **Keputusan:** undangan sekali pakai dari CLI operator (hanya hash token yang disimpan), diterima `POST /v1/enrollments` sebagai alternatif identitas kartu.
- **Dokumen lengkap:** `docs/adr/0033-fokus-enrolment-undangan.md` · spesifikasi `docs/superpowers/specs/2026-11-01-undangan-design.md`.
- **Sesi:** [Registri kartu fisik](../sessions/2026-11-01-registri-kartu.md)
