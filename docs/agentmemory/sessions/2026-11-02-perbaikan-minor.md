---
type: session
project: anastrophe
date: 2026-11-02
status: selesai
tags: [backend, app, ketahanan, konkurensi, denylist]
---
# 2026-11-02 — Perbaikan minor tertunda

Keputusan: [ADR-0042](../decisions/ADR-0042-fokus-setelah-provisioning-aman.md). JEV mengeskalasi (0,41); rekomendasi penulis diterapkan atas dasar tujuan iterasi berkelanjutan pengguna. Rencana: `docs/superpowers/plans/2026-11-02-perbaikan-minor.md`.

## Perubahan

- **Konkurensi:**
  - Resume jalur kartu dan undangan dijaga status, dengan pengulangan sekali bila sapuan menandai instance `ABANDONED` di tengah transaksi.
  - Perpanjangan mengunci instance sebelum kredensial.
  - `SetProvisioningKeyHash` hanya untuk instance yang menunggu.
- **Denylist:** `max_not_after` (migrasi 0012) dan `GREATEST`, sehingga entri bertahan sampai sertifikat terpanjang habis; dibuang sapuan per jam.
- **Audit:** revoke operator menulis `credential.revoked` per kredensial.
- **CLI:** id undangan dicetak, dan `--link-base` harus tepat `https://<domain>/i/`.
- **App:**
  - `CardStore.update(id:mutate:)` atomik.
  - Penyegar memakai `ContinuousClock` (ikut berjalan saat tidur) dan melewati kartu Dicabut.
  - Perpanjangan menyimpan `serverCardID` dari challenge.
  - Parameter rahasia enrolment wajib.

## Bukti

- Go: 10 paket lulus. Swift: host 288 test, simulator 286 test.
- Test konkurensi terkendali mereproduksi bug resume, dan test `NOWAIT` mereproduksi urutan kunci yang salah (55P03).
- Uji mutasi tertangkap di setiap task.
- Pelajaran: race acak 14 putaran tidak mereproduksi deadlock, sedangkan test urutan kunci deterministik membuktikan urutannya.

## Review akhir

0 Critical, 0 Important; kelima Review Focus terpenuhi. Fix pass: `GREATEST`, path `/i/`, `ContinuousClock`, serta sinkron SDD dan backlog. Sisa minor dan deadlock enrolment–sapuan (pra-ada) ada di [backlog](../backlog.md).

`jev_gate` tereskalasi (composite 0,73). Log: `docs/adr/jev-log/2026-11-02-perbaikan-minor-gate.json`.
