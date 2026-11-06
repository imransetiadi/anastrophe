# ADR-0061: Fokus berikutnya: tipe nominal untuk rahasia provisioning vs hash-nya (ADR-0040)

- **Status:** Diterima
- **Tanggal:** 2026-11-06
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0), ronde ketiga sesi ini
- **Rujukan:** ADR-0018, ADR-0040, ADR-0060, CLAUDE.md aturan 9 (secret tidak pernah masuk repo — relevan karena perubahan ini menyentuh kode yang menangani rahasia, bukan memindahkannya ke repo)

## Konteks

Setelah keempat kandidat ADR-0060 selesai (commit `e5b21b7`, `77ad35a`, `3ff9410`, `556468f`), sesi ini mencari fokus berikutnya dari `docs/agentmemory/backlog.md`.

**Ronde pertama** (`jev-log/2026-11-06-fokus-berikutnya-r2.output.json`) memilih `renewal_type_safety_and_tests` (confidence 0,64, Provisional) berdasarkan baris backlog "Perpanjangan: celah test (cek kanal dan kunci group di renewer, kredensial non-ACTIVE di backend); slot pekerjaan tunggal tidak terikat ke tap; renewer menulis salinan kartu lama" dan baris "Audit: waktu event bisa mundur sepanjang `seq`".

**Verifikasi terhadap kode** (sebelum implementasi, mengikuti praktik `backlog.md` sendiri — "Ledger ... sebagian catatan sudah usang") menemukan keempat klaim itu **sudah diperbaiki sebelumnya dan tidak lagi berlaku**:
- Audit: `b2ed49c fix(audit): waktu event tidak mundur sepanjang seq (minor review audit 3)` (2026-11-01).
- Cek kanal/kunci-group di renewer app: test `responsKanalBerbedaDitolak`, `kunciGroupTidakValidDitolak` sudah ada sejak `a77d7c2` (2026-11-01).
- Kredensial non-ACTIVE di backend: `TestKanalDimatikanTidakDiperpanjang`, `TestKredensialDitangguhkanTidakDiperpanjang`, `TestKredensialDicabutTidakDiperpanjang` sudah ada.
- Slot pekerjaan `RenewalScheduler.pending` sudah terikat ke `tap: UUID`; `afterPresentation` menolak tap lain.
- `CredentialRenewer.renew` sudah membaca ulang kartu sebelum menimpa record (bukan menulis salinan lama).

`docs/agentmemory/backlog.md` diperbaiki untuk mencerminkan temuan ini (lihat commit unit ini). Satu temuan nyata ikut tercatat tapi **sengaja tidak dijadikan kandidat**: endpoint `/v1/credentials/{id}:challenge` tanpa autentikasi membedakan status kredensial lewat kode HTTP berbeda (404/410/409/201) — oracle status kredensial serupa pola ADR-0046/0047. Mengubah ini berarti mengubah kontrak error yang baru diselaraskan ke SDD §15 (ADR-0060 `error_catalog_alignment`), jadi butuh keputusan tersendiri, bukan diam-diam diubah dalam unit ini.

**Ronde ketiga** memakai tiga kandidat yang diverifikasi langsung terhadap kode:
1. `ble_flaky_test_fix` — `BLETapTests.autentikasiBatalMembatalkanPemindaian` masih memakai assertion OR-toleran (`scanCount == 0 || scanWasCancelled`), dikonfirmasi langsung di kode.
2. `provisioning_secret_hash_type_safety` — `ProvisioningSecret.generate() -> Data` dan `.hash(secret: Data) -> Data` (ANStorage) keduanya `Data` polos; di `CardProvisioner.provision`, variabel `secret` dan `secretHash` bertipe sama dipakai di dua pemanggilan API berbeda ~25 baris terpisah, tanpa penjagaan kompiler.
3. `provisioning_concurrency_test_hardening` — tiga test backend (`hardening_test.go` ×2, `status_test.go`) masih memakai `time.Sleep(300 * time.Millisecond)` untuk menguji race, bukan sinkronisasi eksplisit.

## Hasil JEV

- **Hasil:** `provisioning_secret_hash_type_safety` · confidence **0.99** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-06-fokus-berikutnya-r2.output.json`](jev-log/2026-11-06-fokus-berikutnya-r2.output.json) (ronde 1, berbasis bukti usang), [`jev-log/2026-11-06-fokus-berikutnya-r3.output.json`](jev-log/2026-11-06-fokus-berikutnya-r3.output.json) (ronde 3, diterima)

| Kandidat (ronde 3) | Probabilitas | Catatan requirement |
|---|---|---|
| `provisioning_secret_hash_type_safety` | 0.99 | keduanya *supported* |
| `ble_flaky_test_fix` | 0.01 | req. 2 (tidak ubah kontrak error) *unknown* — tidak relevan untuk perbaikan test, tapi JEV tidak bisa memastikan *supported* |
| `provisioning_concurrency_test_hardening` | 0 | keduanya *supported*, kalah probabilitas |

Confidence 0,99 ≥ 0,80 (ADR-0018) → **Diterima** tanpa eskalasi.

## Keputusan

Bungkus rahasia enrolment mentah dan hash-nya (ADR-0040) sebagai dua tipe nominal berbeda di `ANStorage` (`ProvisioningSecret` dan `ProvisioningSecretHash`, atau nama setara), bukan `Data` polos, sehingga tertukar di `CardProvisioner.provision` atau pemanggil lain menjadi galat kompilasi, bukan bug runtime senyap. Sesuaikan signature `APIClient.createEnrollment(provisioningKeyHash:)` dan `submitCredentialKey(provisioningSecret:)` mengikuti tipe baru. Perilaku runtime (byte yang dikirim ke jaringan) tidak berubah — ini murni pengerasan tipe, dikerjakan TDD dengan test regresi yang membuktikan alur provisioning tetap berfungsi identik.

`ble_flaky_test_fix` dan `provisioning_concurrency_test_hardening` tetap kandidat valid untuk fokus berikutnya setelah unit ini.

Unit berdiri sendiri dan kecil (satu pola di satu alur), dikerjakan langsung TDD tanpa dokumen spesifikasi/rencana terpisah — mengikuti preseden keempat unit ADR-0060 (`app_attest_hardening`, dll.) yang juga langsung ke TDD + commit.

## Penutupan unit

Diimplementasikan di `ANCore` (`ProvisioningSecret`, `ProvisioningSecretHash`, tipe baru), `ANStorage` (`ProvisioningSecretGenerator`, pengganti enum `ProvisioningSecret` lama), `ANFeatures` (`CardProvisioner`), dan `ANNetworking` (`APIClient`), dengan test yang disesuaikan.

Bukti verifikasi langsung:
- `swift build` dan `swift test` (host) lulus tanpa regresi, termasuk suite baru `ProvisioningSecretTests` (ADR-0061).
- `xcodebuild -scheme AnastropheKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` → `TEST SUCCEEDED`.
- `python3 scripts/docs/check_docs.py .` → 0 masalah.
- **Pembuktian jaminan tipe:** menukar argumen `secret`/`secretHash` di `CardProvisioner.provision` (mengirim `secret` ke parameter `provisioningKeyHash`) dicoba langsung dan **gagal kompilasi** (`cannot convert value of type 'ProvisioningSecret' to expected argument type 'ProvisioningSecretHash'`), lalu dikembalikan ke semula. Ini membuktikan tujuan unit tercapai: pola bug yang jadi alasan ADR ini sekarang benar-benar tertangkap kompiler.

`jev_gate` dipanggil dan **tereskalasi** (composite 0,754, safe_to_apply 0,54; 0 klaim *contradicted*, 3 *unsupported* karena sebagian evidence ditulis ringkas, bukan kutipan literal penuh per klaim) — log mentah di [`jev-log/2026-11-06-tipe-rahasia-provisioning-gate.json`](jev-log/2026-11-06-tipe-rahasia-provisioning-gate.json). Mengikuti preseden ADR-0060 (empat unit sebelumnya tidak memanggil `jev_gate` sama sekali, cukup TDD RED→GREEN langsung) dan preseden tujuh gate penutupan lain di README yang tereskalasi namun diterima berdasarkan bukti uji nyata, unit ini dianggap selesai berdasarkan verifikasi langsung di atas, bukan skor `jev_gate`.

## Konsekuensi

- Tidak ada perubahan kontrak jaringan atau katalog error SDD §15 — aman dari tumpang tindih dengan ADR-0060.
- Modul yang disentuh: `ANStorage` (definisi tipe), `ANFeatures` (`CardProvisioner`), `ANNetworking` (`APIClient` signature). `StatusToken` (token baca status, ADR-0037) dibiarkan dulu memakai `Data` polos karena pola pemanggilannya tidak menunjukkan risiko tertukar yang sama (dipakai langsung, tidak melewati dua variabel lokal sejenis); bisa dipertimbangkan terpisah bila ditemukan pola serupa.
- `ble_flaky_test_fix` dan `provisioning_concurrency_test_hardening` menyusul sebagai unit terpisah.
