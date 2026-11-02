---
type: moc
project: anastrophe
updated: 2026-11-02
---
# Anastrophe — Map of Content

Vault memori proyek. Buka folder `docs/agentmemory/` sebagai vault di Obsidian. Log kronologis lengkap ada di `Memory.md` di root repo; vault ini memuat catatan per sesi, keputusan, dan pelajaran yang saling bertaut untuk graph view. Tautan memakai format Markdown relatif agar tetap terbaca di GitHub.

Aturan: tidak ada secret, kredensial, token, kontak pengguna, atau identitas kartu fisik di vault ini (CLAUDE.md aturan 6 dan 9).

## Sesi

- [2026-11-02 — Uji beban API dan baseline lab](sessions/2026-11-02-uji-beban-api.md)
- [2026-11-02 — Observabilitas backend: log akses dan metrik](sessions/2026-11-02-observabilitas-backend.md)
- [2026-11-02 — Pembersihan sisa Keychain saat instal ulang](sessions/2026-11-02-sisa-instal-ulang.md)
- [2026-11-02 — Verifier App Attest di backend](sessions/2026-11-02-verifier-app-attest.md)
- [2026-11-02 — Deadlock enrolment–sapuan per jam](sessions/2026-11-02-deadlock-enrolment-sapuan.md)
- [2026-11-02 — Filter daftar kartu](sessions/2026-11-02-filter-daftar-kartu.md)
- [2026-11-02 — Kebijakan gedung](sessions/2026-11-02-kebijakan-gedung.md)
- [2026-11-02 — Layar Bantuan dan FAQ](sessions/2026-11-02-bantuan-faq.md)
- [2026-11-02 — Alur Tambah Kartu produksi](sessions/2026-11-02-alur-tambah-kartu.md)
- [2026-11-02 — Perbaikan minor tertunda](sessions/2026-11-02-perbaikan-minor.md)
- [2026-11-02 — Provisioning kredensial yang aman](sessions/2026-11-02-provisioning-aman.md)
- [2026-11-02 — Siklus hidup kartu oleh operator dan status kartu di app](sessions/2026-11-02-siklus-hidup-kartu.md)
- [2026-11-01 — Enrolment via undangan](sessions/2026-11-01-undangan.md)
- [2026-11-01 — Registri kartu fisik dan enrolment berbasis kartu](sessions/2026-11-01-registri-kartu.md)
- [2026-11-01 — Minor riwayat tap, fokus registri, push ke GitHub](sessions/2026-11-01-minor-riwayat-tap-dan-registri.md)
- [2026-11-01 — Perbaikan review riwayat tap](sessions/2026-11-01-perbaikan-riwayat-tap.md)
- [2026-11-01 — Memory.md dan vault Obsidian](sessions/2026-11-01-memory-dan-obsidian.md)
- [2026-11-01 — Riwayat tap lokal 30 hari](sessions/2026-11-01-riwayat-tap.md)

## Keputusan

- [ADR-0055 — Fokus berikutnya: uji beban API dan baseline lab](decisions/ADR-0055-fokus-uji-beban-api.md) · JEV 0,95
- [ADR-0054 — Fokus berikutnya: observabilitas backend](decisions/ADR-0054-fokus-observabilitas-backend.md) · JEV 0,99
- [ADR-0053 — Fokus berikutnya: bersihkan sisa Keychain saat instal ulang](decisions/ADR-0053-fokus-sisa-keychain-instal-ulang.md) · JEV 0,39 (eskalasi; diterapkan risiko rendah)
- [ADR-0052 — Fokus berikutnya: verifier App Attest di backend](decisions/ADR-0052-fokus-verifier-app-attest.md) · JEV 0,60 (provisional)
- [ADR-0051 — Fokus berikutnya: deadlock enrolment–sapuan per jam](decisions/ADR-0051-fokus-deadlock-enrolment-sapuan.md) · JEV 0,96
- [ADR-0050 — Fokus berikutnya: filter kanal dan pencarian daftar kartu](decisions/ADR-0050-fokus-filter-daftar-kartu.md) · JEV 1,0
- [ADR-0049 — Fokus berikutnya: kebijakan gedung](decisions/ADR-0049-fokus-kebijakan-gedung.md) · JEV 0,63 (provisional)
- [ADR-0048 — Fokus berikutnya: layar Bantuan dan FAQ in-app](decisions/ADR-0048-fokus-bantuan-faq.md) · JEV 0,99
- [ADR-0045 — Perangkat dibuat di dalam transaksi enrolment](decisions/ADR-0045-perangkat-dibuat-saat-enrolment.md) · JEV 0,77 (provisional)
- [ADR-0044 — Kode gedung untuk enrolment kartu fisik](decisions/ADR-0044-kode-gedung-untuk-enrolment-kartu.md) · JEV 0,96
- [ADR-0043 — Fokus berikutnya: alur Tambah Kartu produksi](decisions/ADR-0043-fokus-alur-tambah-kartu.md) · JEV 0,98
- [ADR-0042 — Fokus berikutnya setelah provisioning aman](decisions/ADR-0042-fokus-setelah-provisioning-aman.md) · JEV 0,41 (eskalasi; rekomendasi diterapkan)
- [ADR-0041 — Pengambilalihan enrolment yang belum selesai lewat id perangkat](decisions/ADR-0041-pengambilalihan-enrolment-belum-selesai.md) · JEV 0,44 (eskalasi)
- [ADR-0040 — Rahasia enrolment untuk kredensial pertama](decisions/ADR-0040-rahasia-enrolment-kredensial-pertama.md) · JEV 0,83
- [ADR-0039 — Fokus berikutnya: provisioning kredensial yang aman](decisions/ADR-0039-fokus-provisioning-aman.md) · JEV 0,92
- [ADR-0038 — Pemegang kartu tidak boleh membatalkan suspend/revoke operator](decisions/ADR-0038-cegah-pembatalan-tindakan-operator.md) · JEV 0,45 (eskalasi)
- [ADR-0037 — Token baca status kartu](decisions/ADR-0037-token-baca-status-kartu.md) · JEV 0,96
- [ADR-0036 — Fokus berikutnya: siklus hidup kartu oleh operator](decisions/ADR-0036-fokus-siklus-hidup-kartu-operator.md) · JEV 0,98
- [ADR-0035 — Undangan berkartu menyetujui instance yang belum selesai](decisions/ADR-0035-undangan-berkartu-menyetujui-instance.md) · JEV 0,94
- [ADR-0034 — Enrolment yang belum selesai dilanjutkan](decisions/ADR-0034-lanjutkan-enrolment-belum-selesai.md) · JEV 0,81
- [ADR-0033 — Fokus berikutnya: enrolment via undangan](decisions/ADR-0033-fokus-enrolment-undangan.md) · JEV 0,89
- [ADR-0032 — Perangkat tambahan menunggu persetujuan sebelum ada akun](decisions/ADR-0032-perangkat-tambahan-menunggu-persetujuan.md) · JEV 0,71 (provisional)
- [ADR-0031 — Fokus berikutnya: registri kartu fisik dan enrolment](decisions/ADR-0031-fokus-registri-enrolment-server.md) · JEV 0,88
- [ADR-0030 — Lima tap terbaru dan riwayat 30 hari](decisions/ADR-0030-tampilan-riwayat-tap.md) · JEV 0,95
- [ADR-0029 — Store riwayat dibuat ulang hanya bila rusak](decisions/ADR-0029-pemulihan-store-riwayat-tap.md) · JEV 0,87
- ADR sebelumnya (ADR-0001 sampai ADR-0028): indeks di `docs/adr/README.md`.

## Pelajaran

- [SwiftDataError menyembunyikan galat Core Data](lessons/swiftdata-galat-tersembunyi.md)
- [jev_gate memverifikasi klaim hanya dari butir evidence](lessons/jev-gate-butir-evidence.md)
- [Kunci implisit foreign key ikut dalam urutan kunci](lessons/kunci-implisit-foreign-key.md)
- [Verifikasi uji dan gerbang commit](lessons/verifikasi-uji-dan-gerbang.md)

## Backlog

- [Minor tertunda, terverifikasi terhadap kode](backlog.md)

## Menunggu pengguna

- ADR-0017 (entitas hukum untuk entitlement), ADR-0022 (bentuk reader uji BLE), ADR-0038 (cegah pembatalan suspend/revoke; rekomendasi `hold_pending_approval`), ADR-0041 (pengambilalihan enrolment yang belum selesai; rekomendasi `first_writer_wins`), ADR-0046 (kontrol enumerasi kartu sebagai gerbang pra-pilot; rekomendasi deteksi per gedung + App Attest), ADR-0047 (kedaluwarsa permintaan menunggu), penyambungan App Attest (ADR-0053: pengikatan kunci attested ke `device_id`, endpoint wajib, bypass dev, kategori produksi).
- Tinjauan gate JEV yang tereskalasi: lab, perpanjangan, audit, hapus kartu, riwayat tap, minor riwayat tap, registri kartu, undangan, siklus hidup kartu, provisioning aman, perbaikan minor, alur Tambah Kartu, layar Bantuan, kebijakan gedung (review), filter daftar kartu (review), deadlock enrolment–sapuan, verifier App Attest, sisa Keychain instal ulang, observabilitas backend, uji beban API.
- Integrasi branch `feat/r1-scaffold`: merge ke `main` atau PR (sudah di-push ke GitHub private).
- `DEVELOPMENT_TEAM` serta iPhone dan reader untuk uji bertipe H.
