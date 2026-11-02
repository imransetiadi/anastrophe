---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0059
jev: accept
confidence: 0.93
status: Diterima
---
# ADR-0059 — Isu kontras audit: pengecualian per elemen dengan bukti

- **Pilihan:** tidak ada aturan kategori untuk isu kontras "nearly passed". Pengecualian hanya per elemen, dan hanya bila elemen bertoken, pasangan tokennya lolos test host di permukaan nyata, dan pengukuran piksel mengonfirmasi warnanya. Alasannya merujuk W3C *Understanding SC 1.4.3*.
- **Bukti kalibrasi (iOS 26.5, 3x):** audit menerapkan ambang WCAG 2.x persis; pasangan token 4,62–4,92 tidak pernah ditandai. Rentang 3,0–4,49 berisi semua kegagalan warna sistem.
- **Bila isu berulang di perangkat 2x:** naikkan nilai token lewat ADR baru, bukan lewat pengecualian.
- **Dokumen lengkap:** `docs/adr/0059-pengecualian-kontras-per-elemen.md`. Sesi: [audit aksesibilitas](../sessions/2026-11-02-audit-aksesibilitas.md).
