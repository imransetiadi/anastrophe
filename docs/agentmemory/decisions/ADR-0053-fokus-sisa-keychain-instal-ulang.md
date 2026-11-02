---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0053
jev: escalate
confidence: 0.39
status: Tereskalasi — diterapkan (risiko rendah)
---
# ADR-0053 — Fokus berikutnya: bersihkan sisa Keychain saat instal ulang (FR-43 sebagian)

- **Diterapkan:** pembersihan semua item Keychain service app pada peluncuran pertama tanpa penanda dan tanpa kartu lokal. Alasannya: unit ini pilihan JEV, berisiko rendah, tanpa semantik keamanan baru, dan didasarkan pada persetujuan umum pengguna.
- **Menunggu pengguna:** penyambungan App Attest (seri 0,47), yang menyangkut pengikatan kunci attested ke `device_id` (ADR-0041/0046).
- **Dokumen lengkap:** `docs/adr/0053-fokus-sisa-keychain-instal-ulang.md`. Sesi: [sisa Keychain instal ulang](../sessions/2026-11-02-sisa-instal-ulang.md).
