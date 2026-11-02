---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0050
jev: accept
confidence: 1.0
status: Diterima
---
# ADR-0050 — Fokus berikutnya: filter kanal dan pencarian daftar kartu (FR-50)

- **Pilihan:** `anastrophe-registry list --channel ble|nfcHCE --id <awalan>` (digabung AND dengan `--status`), tanpa identitas kartu atau kontak.
- **Batas:** pencarian hanya awalan id card instance; pencarian nama atau nomor kartu menunggu portal dan akun (aturan 6).
- **Dokumen lengkap:** `docs/adr/0050-fokus-filter-daftar-kartu.md`. Sesi: [filter daftar kartu](../sessions/2026-11-02-filter-daftar-kartu.md).
