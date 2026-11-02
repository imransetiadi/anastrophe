---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0056
jev: accept
confidence: 0.93
status: Diterima
---
# ADR-0056 — Fokus berikutnya: pemindaian secret dan dependensi (TC-SEC-11)

- **Pilihan:** satu perintah (`scripts/security/scan.py`) untuk:
  - secret di riwayat git, perubahan yang di-stage, dan produk build (gitleaks dengan allowlist sempit beralasan);
  - kerentanan dependensi (govulncheck, paket Swift remote, OSV untuk alat Python).
- **Sesudah review akhir:**
  - git yang gagal, clone dangkal, dan `.gitleaksignore` memberi exit 2;
  - `gitleaks:allow` diabaikan;
  - produk build dipindai langsung dan lewat string cetak.
- **Konsekuensi:** backend kini menuntut Go ≥ 1.25 dengan toolchain go1.27.3.
- **Di luar cakupan:** CI, hook pre-commit otomatis, audit `.ipa` (TC-SEC-07), MASVS (TC-SEC-06), dan pentest (TC-SEC-12).
- **Dokumen lengkap:** `docs/adr/0056-fokus-pemindaian-secret-dependensi.md`. Sesi: [pemindaian secret dan dependensi](../sessions/2026-11-02-pemindaian-secret-dependensi.md).
