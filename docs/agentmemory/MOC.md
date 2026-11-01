---
type: moc
project: anastrophe
updated: 2026-11-01
---
# Anastrophe — Map of Content

Vault memori proyek. Buka folder `docs/agentmemory/` sebagai vault di Obsidian. Log kronologis lengkap ada di `Memory.md` di root repo; vault ini memuat catatan per sesi, keputusan, dan pelajaran yang saling bertaut untuk graph view. Tautan memakai format Markdown relatif agar tetap terbaca di GitHub.

Aturan: tidak ada secret, kredensial, token, kontak pengguna, atau identitas kartu fisik di vault ini (CLAUDE.md aturan 6 dan 9).

## Sesi

- [2026-11-01 — Minor riwayat tap, fokus registri, push ke GitHub](sessions/2026-11-01-minor-riwayat-tap-dan-registri.md)
- [2026-11-01 — Perbaikan review riwayat tap](sessions/2026-11-01-perbaikan-riwayat-tap.md)
- [2026-11-01 — Memory.md dan vault Obsidian](sessions/2026-11-01-memory-dan-obsidian.md)
- [2026-11-01 — Riwayat tap lokal 30 hari](sessions/2026-11-01-riwayat-tap.md)

## Keputusan

- [ADR-0032 — Perangkat tambahan menunggu persetujuan sebelum ada akun](decisions/ADR-0032-perangkat-tambahan-menunggu-persetujuan.md) · JEV 0,71 (provisional)
- [ADR-0031 — Fokus berikutnya: registri kartu fisik dan enrolment](decisions/ADR-0031-fokus-registri-enrolment-server.md) · JEV 0,88
- [ADR-0030 — Lima tap terbaru dan riwayat 30 hari](decisions/ADR-0030-tampilan-riwayat-tap.md) · JEV 0,95
- [ADR-0029 — Store riwayat dibuat ulang hanya bila rusak](decisions/ADR-0029-pemulihan-store-riwayat-tap.md) · JEV 0,87
- ADR sebelumnya (ADR-0001 sampai ADR-0028): indeks di `docs/adr/README.md`.

## Pelajaran

- [SwiftDataError menyembunyikan galat Core Data](lessons/swiftdata-galat-tersembunyi.md)
- [jev_gate memverifikasi klaim hanya dari butir evidence](lessons/jev-gate-butir-evidence.md)

## Menunggu pengguna

- Klarifikasi ADR-0001: kalimat Keputusan kini "meng-clone", bertentangan dengan CLAUDE.md aturan 1 dan PRD NG1/FR-11.
- ADR-0017 (entitas hukum untuk entitlement) dan ADR-0022 (bentuk reader uji BLE).
- Tinjauan gate JEV yang tereskalasi: lab, perpanjangan, audit, hapus kartu, riwayat tap.
- Integrasi branch `feat/r1-scaffold`: merge ke `main` atau PR (sudah di-push ke GitHub private).
- `DEVELOPMENT_TEAM` serta iPhone dan reader untuk uji bertipe H.
