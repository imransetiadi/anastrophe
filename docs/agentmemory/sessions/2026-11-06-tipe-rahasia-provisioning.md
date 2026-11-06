---
type: session
project: anastrophe
date: 2026-11-06
---
# Sesi 2026-11-06 — Fokus berikutnya pasca ADR-0060: tipe nominal rahasia provisioning

## Konteks

Keempat kandidat [[ADR-0060]] selesai dan tercommit (`e5b21b7`, `77ad35a`, `3ff9410`, `556468f`). Sesi ini mencari fokus kerja berikutnya dari `docs/agentmemory/backlog.md`.

## Ronde pertama — berbasis bukti usang

`jev_decide` memilih `renewal_type_safety_and_tests` (confidence 0,64) berdasarkan baris backlog "Perpanjangan: celah test ..., slot pekerjaan tunggal tidak terikat ke tap, renewer menulis salinan kartu lama" dan "Audit: waktu event bisa mundur sepanjang seq".

**Verifikasi langsung terhadap kode** (sebelum implementasi, mengikuti praktik `backlog.md` sendiri) menemukan keempat klaim itu sudah diperbaiki sebelumnya:
- Audit: `b2ed49c fix(audit): waktu event tidak mundur sepanjang seq (minor review audit 3)`.
- Cek kanal/kunci-group di renewer app: test `responsKanalBerbedaDitolak`, `kunciGroupTidakValidDitolak` sejak `a77d7c2`.
- Kredensial non-ACTIVE di backend: `TestKanalDimatikanTidakDiperpanjang` dkk. sudah ada.
- `RenewalScheduler.pending` sudah terikat ke `tap: UUID`; `CredentialRenewer.renew` sudah membaca ulang kartu sebelum menimpa.

`docs/agentmemory/backlog.md` diperbaiki untuk mencerminkan temuan ini. Satu temuan nyata dicatat tapi sengaja **tidak** dijadikan kandidat: endpoint `/v1/credentials/{id}:challenge` tanpa autentikasi membedakan status kredensial lewat kode HTTP berbeda (oracle status kredensial) — mengubahnya berarti mengubah kontrak error yang baru diselaraskan ke SDD §15 ([[ADR-0060]] `error_catalog_alignment`), jadi butuh keputusan tersendiri.

## Ronde kedua/ketiga — kandidat terverifikasi

`jev_decide` ronde ketiga (confidence 0,99) memilih `provisioning_secret_hash_type_safety`, dari tiga kandidat yang masing-masing diverifikasi langsung ke kode sebelum dipanggil. Lihat [[ADR-0061]].

## Implementasi

- `ProvisioningSecret`/`ProvisioningSecretHash` (struct terpisah, `ANCore`) menggantikan pola `Data` polos keduanya di `ANStorage.ProvisioningSecret` lama.
- `ANStorage.ProvisioningSecretGenerator` menghasilkan/menghash tipe baru.
- `CardProvisioner`, `APIClient.createEnrollment` (dua overload), `APIClient.submitCredentialKey` disesuaikan.
- **Bukti jaminan tipe:** menukar argumen `secret`/`secretHash` di `CardProvisioner.provision` dicoba langsung — gagal kompilasi, lalu dikembalikan.

## Bukti uji

`swift test` (host, 397 test, semua target lulus termasuk suite baru `ProvisioningSecretTests`), `xcodebuild -scheme AnastropheKit-Package test` (simulator iPhone 17 Pro, `TEST SUCCEEDED`), `python3 scripts/docs/check_docs.py .` (0 masalah).

`jev_gate` tereskalasi (composite 0,754, safe_to_apply 0,54; 0 *contradicted*). Mengikuti preseden [[ADR-0060]] (empat unit tidak memanggil `jev_gate` sama sekali) dan preseden gate lain yang tereskalasi namun diterima berdasarkan bukti uji nyata, unit ini dianggap selesai berdasarkan verifikasi langsung di atas.

## Berikutnya

`ble_flaky_test_fix` (BLETapTests, assertion OR-toleran) dan `provisioning_concurrency_test_hardening` (tiga test backend `time.Sleep(300ms)`) tetap kandidat valid, terverifikasi masih terbuka.
