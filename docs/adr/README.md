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
| [ADR-0027](0027-hapus-kartu-ditangguhkan.md) | Kartu yang ditangguhkan bisa dihapus pemiliknya | Diterima | `revoke_suspended` | 0.94 |
| [ADR-0028](0028-hapus-kartu-tanpa-kunci.md) | Kartu tanpa kunci dihapus lokal tanpa bukti | Diterima | `local_delete_no_proof` | 1.0 |
| [ADR-0029](0029-pemulihan-store-riwayat-tap.md) | Store riwayat tap dibuat ulang hanya bila rusak atau tak termigrasi | Diterima | `reset_on_corruption_only` | 0.87 |
| [ADR-0030](0030-tampilan-riwayat-tap.md) | Detail kartu: lima tap terbaru + riwayat 30 hari | Diterima | `inline_recent_plus_all` | 0.95 |
| [ADR-0031](0031-fokus-registri-enrolment-server.md) | Iterasi berikutnya: registri kartu fisik dan pencocokan enrolment di server | Diterima | `registry_enrolment_server` | 0.88 |
| [ADR-0032](0032-perangkat-tambahan-menunggu-persetujuan.md) | Sebelum ada akun: perangkat pertama diprovisikan, perangkat tambahan menunggu persetujuan | Diterima (provisional — tinjau ulang saat fondasi akun dibangun) | `pending_for_additional` | 0.71 |
| [ADR-0033](0033-fokus-enrolment-undangan.md) | Iterasi berikutnya: enrolment via undangan | Diterima | `invitation_enrolment` | 0.89 |
| [ADR-0034](0034-lanjutkan-enrolment-belum-selesai.md) | Enrolment yang belum selesai dilanjutkan; PROVISIONING tanpa kredensial kedaluwarsa 15 menit | Diterima | `resume_plus_expiry` | 0.81 |
| [ADR-0035](0035-undangan-berkartu-menyetujui-instance.md) | Undangan berkartu menyetujui instance yang belum selesai milik perangkat yang sama | Diterima | `promote_existing` | 0.94 |
| [ADR-0036](0036-fokus-siklus-hidup-kartu-operator.md) | Fokus berikutnya: siklus hidup kartu oleh operator dan status kartu di app | Diterima | `operator_lifecycle_status` | 0.98 |
| [ADR-0037](0037-token-baca-status-kartu.md) | App membaca status kartu dengan token baca status | Diterima | `status_read_token` | 0.96 |
| [ADR-0038](0038-cegah-pembatalan-tindakan-operator.md) | Pemegang kartu tidak boleh membatalkan suspend/revoke operator (terbuka) | Diusulkan — butuh keputusan manusia (eskalasi) | — (escalate) | 0.45 |
| [ADR-0039](0039-fokus-provisioning-aman.md) | Fokus berikutnya: provisioning kredensial hanya untuk perangkat yang memulai enrolment | Diterima | `secure_provisioning` | 0.92 |
| [ADR-0040](0040-rahasia-enrolment-kredensial-pertama.md) | Rahasia enrolment untuk kredensial pertama; tambah kanal ke kartu aktif ditolak | Diterima | `secret_first_block_add_channel` | 0.83 |
| [ADR-0041](0041-pengambilalihan-enrolment-belum-selesai.md) | Pengambilalihan enrolment yang belum selesai lewat id perangkat (terbuka) | Diusulkan — butuh keputusan manusia (eskalasi) | — (escalate) | 0.44 |
| [ADR-0042](0042-fokus-setelah-provisioning-aman.md) | Fokus berikutnya setelah provisioning aman | Diterapkan (rekomendasi penulis; persetujuan umum pengguna) | `hardening_minors` (escalate 0.41) | 0.41 |
| [ADR-0043](0043-fokus-alur-tambah-kartu.md) | Fokus berikutnya: alur Tambah Kartu produksi | Diterima | `alur_tambah_kartu` | 0.98 |
| [ADR-0044](0044-kode-gedung-untuk-enrolment-kartu.md) | Kode gedung untuk enrolment kartu fisik | Diterima | `kode_gedung_lookup` | 0.96 |
| [ADR-0045](0045-perangkat-dibuat-saat-enrolment.md) | Perangkat dibuat di dalam transaksi enrolment | Provisional (ditinjau M2) | `otomatis_saat_enrolment` | 0.77 |
| [ADR-0046](0046-oracle-tebak-kartu-gerbang-pra-pilot.md) | Oracle tebak kartu pada enrolment menjadi gerbang pra-pilot (terbuka) | Tereskalasi — inti bersama diterapkan, pilihan kontrol menunggu manusia | `deteksi_per_gedung` (escalate) | 0.49 |
| [ADR-0047](0047-batas-permintaan-menunggu-per-kartu.md) | Batas permintaan perangkat tambahan yang menunggu per kartu (terbuka sebagian) | Tereskalasi — batas 4 diterapkan, kedaluwarsa menunggu manusia | `batas_pending_per_kartu` (escalate) | 0.51 |
| [ADR-0048](0048-fokus-bantuan-faq.md) | Fokus berikutnya: layar Bantuan dan FAQ in-app | Diterima | `bantuan_faq` | 0.99 |
| [ADR-0049](0049-fokus-kebijakan-gedung.md) | Fokus berikutnya: kebijakan gedung (FR-55 sebagian) | Provisional (ditinjau M2) | `kebijakan_gedung` | 0.63 |
| [ADR-0050](0050-fokus-filter-daftar-kartu.md) | Fokus berikutnya: filter kanal dan pencarian daftar kartu (FR-50) | Diterima | `filter_cli_fr50` | 1.0 |
| [ADR-0051](0051-fokus-deadlock-enrolment-sapuan.md) | Fokus berikutnya: deadlock enrolment–sapuan per jam | Diterima | `deadlock_sapuan` | 0.96 |
| [ADR-0052](0052-fokus-verifier-app-attest.md) | Fokus berikutnya: verifier App Attest di backend (NFR-S03, langkah pertama) | Provisional (ditinjau M2) | `app_attest_verifier` | 0.60 |
| [ADR-0053](0053-fokus-sisa-keychain-instal-ulang.md) | Fokus berikutnya: bersihkan sisa Keychain saat instal ulang (FR-43 sebagian) | Tereskalasi — diterapkan (risiko rendah; persetujuan umum pengguna), penyambungan App Attest menunggu manusia | `instal_ulang_fr43` (escalate) | 0.39 |
| [ADR-0054](0054-fokus-observabilitas-backend.md) | Fokus berikutnya: observabilitas backend — log akses terstruktur dan metrik (NFR-O01 sebagian) | Diterima | `observability_nfr_o01` | 0.99 |
| [ADR-0055](0055-fokus-uji-beban-api.md) | Fokus berikutnya: uji beban API dan baseline lab (TC-PERF-05) | Diterima | `uji_beban_api` | 0.95 |
