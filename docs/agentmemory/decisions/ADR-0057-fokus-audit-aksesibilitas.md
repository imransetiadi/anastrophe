---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0057
jev: accept
confidence: 0.70
status: Provisional
---
# ADR-0057 — Fokus berikutnya: audit aksesibilitas app (NFR-A01, TC-UX-01–04/09)

- **Pilihan:** audit aksesibilitas yang sistematis:
  - test kontras token di host (TC-UX-03);
  - target UI test XCUITest yang menjalankan `performAccessibilityAudit` atas 16 keadaan layar demo, di mode terang, gelap, dan AX5 (ID/EN), ditambah cek target sentuh ≥ 44 pt (TC-UX-01, -02, -04);
  - penilaian checklist design system §9 (TC-UX-09).
- **Status:** Provisional (JEV 0,70), ditinjau di M2. Pekerjaannya baru sebagian; lihat sesi.
- **Keputusan turunan:** [ADR-0058](ADR-0058-cakupan-token-warna-tint-app.md) (cakupan token) dan [ADR-0059](ADR-0059-pengecualian-kontras-per-elemen.md) (pengecualian kontras).
- **Dokumen lengkap:** `docs/adr/0057-fokus-audit-aksesibilitas.md`. Sesi: [audit aksesibilitas](../sessions/2026-11-02-audit-aksesibilitas.md).
