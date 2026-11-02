# ADR-0052: Fokus berikutnya: verifier App Attest di backend (NFR-S03, langkah pertama)

- **Status:** Provisional (JEV 0,60), ditinjau di milestone M2
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** NFR-S03, TC-ENR-17, TC-SEC-05, TC-SEC-15, ADR-0021, ADR-0045, ADR-0046, E35–E41, O-AA01–O-AA08

## Konteks

App Attest wajib untuk enrolment, provisioning, dan transfer (NFR-S03), dan menjadi gerbang pra-pilot bersama kontrol enumerasi kartu (ADR-0046). Belum ada kode App Attest di app maupun server.

- **Yang belum bisa sekarang:** attestation nyata butuh build bertanda tangan dengan capability App Attest (`DEVELOPMENT_TEAM` belum ada) dan iPhone fisik.
- **Yang bisa sekarang:** verifikasi di server bisa dibangun dan diuji, karena Apple menerbitkan contoh attestation resmi (E36).

Kandidat lain:
- pembersihan sisa Keychain sesudah instal ulang (FR-43, P0 sebagian);
- laporan FR-58 (P1);
- App Shortcuts FR-24 (P1);
- polling di test konkurensi.

## Hasil JEV

- **Hasil:** `app_attest_verifier` · confidence **0.60** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round37.input.json`](jev-log/2026-11-02-round37.input.json), [`jev-log/2026-11-02-round37.output.json`](jev-log/2026-11-02-round37.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `app_attest_verifier` | 0.65 | ketiganya *supported* |
| `instal_ulang_fr43` | 0.32 | ketiganya *supported* |
| `laporan_fr58` | 0.01 | P0/gerbang pra-pilot: *unknown* |
| `akses_cepat_fr24` | 0 | P0/gerbang pra-pilot: *unknown* |
| `polling_test_konkurensi` | 0 | P0/gerbang pra-pilot: *unknown* |

## Keputusan

- **Paket backend `internal/appattest`:** memverifikasi objek attestation dan assertion App Attest menurut langkah Apple (O-AA01, O-AA02). Paket ini belum disambungkan ke endpoint, database, atau app.
- **Bukti uji:**
  - contoh attestation resmi Apple (O-AA04), di-commit sebagai data uji;
  - vektor sintetis untuk setiap jalur gagal;
  - konvensi digest assertion (hash ganda) sudah dibuktikan dengan assertion iOS 27 nyata (O-AA06). Data pihak ketiga itu hanya dipakai di scratchpad dan tidak masuk repo.
- **Kebijakan menyusul:** endpoint mana yang mewajibkan App Attest, kategori peluncuran app yang diterima, format `clientData`, dan bypass untuk dev diputuskan di unit penyambungan berikutnya.

Desain dan rencananya ada di `docs/superpowers/specs/2026-11-02-verifier-app-attest-design.md` dan `docs/superpowers/plans/2026-11-02-verifier-app-attest.md`.

## Konsekuensi

- Gerbang pra-pilot NFR-S03 belum tertutup. Unit ini baru menyediakan mekanismenya.
- Validasi akhir butuh uji H dengan build bertanda tangan dan App ID Anastrophe (U14).
- `instal_ulang_fr43` tetap kandidat kuat untuk fokus berikutnya.
