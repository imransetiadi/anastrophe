---
type: decision
project: anastrophe
date: 2026-11-06
adr: ADR-0061
jev: accept
confidence: 0.99
status: Diterima
---
# ADR-0061 — Fokus berikutnya: tipe nominal rahasia provisioning vs hash-nya

- **Pilihan:** `provisioning_secret_hash_type_safety` — bungkus rahasia enrolment mentah ([[ADR-0040]]) dan hash-nya sebagai dua tipe nominal berbeda di `ANCore` (`ProvisioningSecret`, `ProvisioningSecretHash`), bukan `Data` polos, sehingga tertukar di `CardProvisioner.provision` atau pemanggil lain jadi galat kompilasi.
- **Status:** Diterima (JEV 0,99, ronde ketiga — ronde pertama berbasis bukti backlog usang, lihat sesi).
- **Verifikasi jaminan:** menukar argumen `secret`/`secretHash` di kode dicoba langsung dan gagal kompilasi, membuktikan tujuan tercapai.
- **`jev_gate` penutupan:** tereskalasi (composite 0,754), diterima berdasarkan bukti uji langsung (`swift test`, `xcodebuild test`, `check_docs.py`), mengikuti preseden [[ADR-0060]].
- **Dokumen lengkap:** `docs/adr/0061-fokus-berikutnya-tipe-rahasia-provisioning.md`. Sesi: [tipe rahasia provisioning](../sessions/2026-11-06-tipe-rahasia-provisioning.md).
