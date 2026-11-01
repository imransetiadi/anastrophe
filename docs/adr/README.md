# Architecture Decision Records

Keputusan arsitektur & produk Anastrophe. Format mengikuti skill `domain-modeling` (`docs/adr/NNNN-slug.md`). Keputusan bertanda JEV diambil lewat lapisan keputusan JEV (ADR-0018).

| ADR | Judul | Status | Pilihan JEV | Confidence |
|---|---|---|---|---|
| [ADR-0001](0001-tidak-clone-kartu-fisik.md) | Tidak meng-clone kartu fisik; terbitkan kredensial baru | Diterima (berbasis bukti; tidak memerlukan JEV) | — | — |
| [ADR-0002](0002-kanal-r1-nfc-inapp-dan-ble.md) | Kanal kredensial R1: NFC in-app + BLE; Apple Wallet di R2 | Diterima | `nfc_inapp_plus_ble` | 0.89 |
| [ADR-0003](0003-protokol-anp1.md) | Protokol kanal in-app: ANP/1 (proprietary, prinsip setara Aliro) | Diterima | `anp1_proprietary` | 0.93 |
| [ADR-0004](0004-klaim-pemegang-utama.md) | Kartu fisik = bukti kepemilikan lemah; PRIMARY wajib cocok registri | Diterima | `holder_match_else_approval` | 1 |
| [ADR-0005](0005-security-code-server-side.md) | Security code 6 digit diverifikasi server dengan rate-limit | Diterima (berbasis bukti; tidak memerlukan JEV) | — | — |
| [ADR-0006](0006-minimum-ios-26.md) | Minimum iOS 26.0 (iPhone 11+/SE 2+) | Diterima | `ios_26_0` | 0.87 |
| [ADR-0007](0007-kredensial-terikat-perangkat.md) | Kredensial terikat perangkat; pindah perangkat = re-provision | Diterima (berbasis bukti; tidak memerlukan JEV) | — | — |
| [ADR-0008](0008-apple-wallet-access-program-sekarang.md) | Ajukan Apple Wallet Access Program sekarang (M0); kanal W di R2 dengan Aliro | Diterima | `apply_now` | 1 |
| [ADR-0009](0009-akses-kunci-user-presence.md) | Kontrol akses kunci in-app: `.userPresence` | Diterima | `user_presence` | 0.93 |
| [ADR-0010](0010-masa-berlaku-sertifikat-7-hari.md) | Masa berlaku sertifikat kredensial default 7 hari | Diterima (provisional — tinjau ulang di akhir pilot M3) | `days_7` | 0.78 |
| [ADR-0011](0011-pilot-ganda.md) | Pilot ganda: Indonesia (BLE) + Singapura/Malaysia (NFC + BLE) | Diterima | `dual_pilot` | 0.84 |
| [ADR-0012](0012-ble-hands-free-ditunda.md) | BLE hands-free ditunda (P2); R1 hanya Tap | Diterima | `foreground_tap_only` | 1 |
| [ADR-0013](0013-anggota-kanal-wallet.md) | Anggota kanal W lewat security code di app; Wallet sharing nonaktif | Diterima | `app_security_code` | 0.89 |
| [ADR-0014](0014-topologi-backend-r1.md) | Topologi backend R1: multi-region primary + hot standby | Diterima (keputusan pengguna setelah eskalasi) | `multi_region_passive` | 0.48 |
| [ADR-0015](0015-batas-anggota-default.md) | Batas anggota default 4 per kartu (dapat diatur gedung) | Diterima (provisional — tinjau ulang di akhir pilot M3) | `max_4` | 0.65 |
| [ADR-0016](0016-strategi-reader-r1.md) | Strategi reader R1: reader referensi Anastrophe (NFC + BLE) | Diterima (provisional — tinjau ulang di akhir M1 (setelah survei reader U03)) | `reference_reader` | 0.66 |
| [ADR-0017](0017-entitas-hukum-entitlement.md) | Entitas hukum untuk entitlement NFC & SE (terbuka) | Diusulkan — butuh keputusan manusia (eskalasi) | `investigate` | 0.27 |
| [ADR-0018](0018-jev-sebagai-decision-layer.md) | JEV sebagai lapisan pengambil keputusan desain | Diterima (berbasis bukti; tidak memerlukan JEV) | — | — |
| [ADR-0019](0019-strategi-pemindaian-ble.md) | Strategi pemindaian BLE Tap: pindai saat lembar dibuka + early exit | Diterima (keputusan pengguna setelah eskalasi) | `prescan_early_exit` | 0.51 |
| [ADR-0020](0020-bahasa-backend-r1.md) | Bahasa backend R1: Go | Diterima (provisional — tinjau ulang di akhir M1) | `go` | 0.7 |
| [ADR-0021](0021-cbor-cose-minimal.md) | CBOR/COSE minimal ditulis sendiri untuk CredentialCert | Diterima | `keep_minimal` | 0.98 |
| [ADR-0022](0022-reader-uji-ble-tanpa-service-data.md) | Reader uji BLE untuk M1 tanpa service data (terbuka) | Diusulkan — butuh keputusan manusia (eskalasi) | — (escalate) | 0.18 |
| [ADR-0023](0023-perpanjangan-sertifikat-autentikasi-tap.md) | Perpanjangan sertifikat memakai autentikasi tap | Diterima | `renew_on_user_auth` | 0.98 |
| [ADR-0024](0024-rantai-audit-per-gedung.md) | Rantai hash audit per gedung | Diterima | `per_site_chain` | 0.95 |
| [ADR-0025](0025-audit-pseudonim-sejak-ditulis.md) | Audit pseudonim sejak ditulis | Diterima | `pseudonymous_at_write` | 0.96 |
| [ADR-0026](0026-hapus-kartu-bukti-kepemilikan.md) | Hapus kartu dengan bukti kepemilikan kunci | Diterima | `pop_revoke` | 0.98 |
