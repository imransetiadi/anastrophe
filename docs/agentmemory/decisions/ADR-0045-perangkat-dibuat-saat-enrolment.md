---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0045
jev: provisional
confidence: 0.77
status: Provisional (tinjau di M2)
---
# ADR-0045 — Perangkat dibuat di dalam transaksi enrolment

- **Pilihan:** app membuat `device_id` (UUID v4, Keychain ThisDeviceOnly, dibuat ulang setelah instal ulang); server `INSERT … ON CONFLICT DO NOTHING` sebelum `lockDevice` di transaksi enrolment, sehingga enrolment yang ditolak tidak meninggalkan baris.
- **Ditolak:** endpoint registrasi publik (baris tanpa batas) dan registrasi oleh operator.
- **Tinjau ulang** di M2 bersama App Attest (NFR-S03); ADR-0041 tidak berubah.
- **Dokumen lengkap:** `docs/adr/0045-perangkat-dibuat-saat-enrolment.md`.
