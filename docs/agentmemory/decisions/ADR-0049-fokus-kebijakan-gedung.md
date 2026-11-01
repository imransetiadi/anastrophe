---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0049
jev: provisional
confidence: 0.63
status: Provisional (tinjau di M2)
---
# ADR-0049 — Fokus berikutnya: kebijakan gedung (FR-55 sebagian)

- **Pilihan:** CLI `policy` untuk masa berlaku sertifikat (1–30 hari) dan kanal per gedung, penegakan kanal saat provisioning (sesudah rahasia enrolment), dan app memilih kanal yang diizinkan gedung dari lookup kode gedung dan respons enrolment.
- **Tidak disentuh:** persetujuan opsional per gedung (FR-17, mengubah perilaku keamanan bawaan ADR-0032) dan perpanjangan (kill switch tetap global di `:renew`, ADR-0023).
- **Kandidat berikutnya:** filter kanal dan pencarian CLI (FR-50).
- **Dokumen lengkap:** `docs/adr/0049-fokus-kebijakan-gedung.md`. Sesi: [kebijakan gedung](../sessions/2026-11-02-kebijakan-gedung.md).
