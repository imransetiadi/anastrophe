---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0051
jev: accept
confidence: 0.96
status: Diterima
---
# ADR-0051 — Fokus berikutnya: deadlock enrolment–sapuan per jam

- **Pilihan:** audit enrolment dan sapuan ditahan lalu ditulis sesudah semua kunci baris, berurutan stabil per rantai. Isi, hash, dan `seq` audit tidak berubah.
- **Tambahan saat implementasi:**
  - lanjutan `PENDING_APPROVAL` dikunci di dalam enrolment;
  - event tetap ditulis saat enrolment gagal;
  - `AppendAudit` mengunci baris gedung `FOR KEY SHARE` sebelum kunci rantai (temuan review akhir).
- **Sisa:** tabrakan `hashtext` antar-rantai (sangat jarang; dideteksi PostgreSQL).
- **Dokumen lengkap:** `docs/adr/0051-fokus-deadlock-enrolment-sapuan.md`. Sesi: [deadlock enrolment–sapuan](../sessions/2026-11-02-deadlock-enrolment-sapuan.md).
