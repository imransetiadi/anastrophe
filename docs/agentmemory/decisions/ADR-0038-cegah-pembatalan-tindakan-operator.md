---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0038
jev: escalate
confidence: 0.45
status: Diusulkan (eskalasi)
---
# ADR-0038 — Pemegang kartu tidak boleh membatalkan suspend/revoke operator (terbuka)

- **Masalah:** setelah suspend atau revoke, pemegang kartu bisa mendaftar ulang kartu fisik yang sama dan mendapat kredensial baru (review akhir siklus hidup C1).
- **JEV:** `hold_pending_approval` 0,53 / `block_reenrol_code` 0,25 / `revoke_removes_card` 0,19; confidence 0,45, jadi **menunggu keputusan pengguna**.
- **Rekomendasi:** `hold_pending_approval`.
- **Dokumen lengkap:** `docs/adr/0038-cegah-pembatalan-tindakan-operator.md`.
