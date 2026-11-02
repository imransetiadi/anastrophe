---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0052
jev: accept
confidence: 0.60
status: Provisional
---
# ADR-0052 — Fokus berikutnya: verifier App Attest di backend (NFR-S03, langkah pertama)

- **Pilihan:** paket `internal/appattest` memverifikasi attestation dan assertion App Attest menurut langkah Apple, belum disambungkan ke endpoint.
- **Runner-up:** pembersihan sisa Keychain sesudah instal ulang (FR-43), dengan probabilitas 0,32.
- **Menyusul:** challenge, penyimpanan kunci dan counter, kebijakan kategori, bypass dev, dan uji H dengan App ID Anastrophe (U14).
- **Dokumen lengkap:** `docs/adr/0052-fokus-verifier-app-attest.md`. Sesi: [verifier App Attest](../sessions/2026-11-02-verifier-app-attest.md).
