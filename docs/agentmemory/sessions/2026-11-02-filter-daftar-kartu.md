---
type: session
project: anastrophe
date: 2026-11-02
status: selesai
tags: [backend, cli, fr-50]
---
# 2026-11-02 — Filter kanal dan pencarian daftar kartu (FR-50)

Keputusan: [ADR-0050](../decisions/ADR-0050-fokus-filter-daftar-kartu.md) (JEV 1,0). Rencana: `docs/superpowers/plans/2026-11-02-filter-daftar-kartu.md`.

## Perubahan

- `anastrophe-registry list --channel ble|nfcHCE --id <awalan>`, digabung AND dengan `--status`.
- Kanal mengikuti kredensial ACTIVE/SUSPENDED, sama dengan kolom KANAL.
- Awalan id hanya `[0-9a-f-]{1,36}` dan dibandingkan dengan `left()`, sehingga tidak pernah menjadi pola `LIKE`. Validasi berjalan sebelum query.
- Kolom keluaran tetap, tanpa identitas kartu atau kontak.

## Bukti

- Go 10 paket lulus.
- Review akhir (opus) menunjukkan dua celah test (SUSPENDED dan AND dengan status) lewat mutasi yang lolos. Test baru menangkap keduanya.

`jev_gate`: review (composite 0,86). Minor ada di [backlog](../backlog.md).

## Pelajaran

- Test yang memakai fixture yang semuanya ACTIVE tidak membuktikan filter status. Setiap klaim AND butuh kasus yang benar-benar dikecualikan oleh filter itu.
