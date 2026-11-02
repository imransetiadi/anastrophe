---
type: session
project: anastrophe
date: 2026-11-02
status: selesai
tags: [keamanan, tc-sec-11, nfr-s09, dependensi, secret]
---
# 2026-11-02 — Pemindaian secret dan dependensi (TC-SEC-11)

Keputusan: [ADR-0056](../decisions/ADR-0056-fokus-pemindaian-secret-dependensi.md) (JEV 0,93). Rencana: `docs/superpowers/plans/2026-11-02-pemindaian-secret-dependensi.md`.

## Perubahan

- **Pemindai `scripts/security/scan.py`** dengan `.gitleaks.toml`:
  - secret: gitleaks ≥ 8.30 atas seluruh riwayat git, perubahan yang di-stage, dan produk build (langsung dan lewat string cetak);
  - dependensi: govulncheck v1.9.0 (kerentanan terpanggil = gagal), app iOS tanpa paket remote, dan OSV untuk dependensi alat Python;
  - exit 0/1/2, dan nilai secret tidak pernah dicetak.
- **Kenaikan versi dari temuan nyata:** pgx v5.9.2, x/text v0.41.0, direktif `go 1.25.0` dengan `toolchain go1.27.3`, dan `cryptography==50.*`.

## Bukti

- **Run nyata** dengan venv yang mengikuti requirements: secret di 169 commit + staged 0, build Release simulator 0, Go 0 terpanggil, Swift 0, Python 0 → exit 0.
  - Dengan interpreter pyenv pengguna exit 1, karena `cryptography` 49.0.0 masih terpasang.
- **Run pertama** menemukan 13 kerentanan Go terpanggil (10 stdlib, 1 pgx, 2 x/text) dan CVE-2026-69247 di `cryptography`. Semuanya ditutup dengan kenaikan versi:
  - suite backend 13/13 dengan go1.27.3;
  - Swift host 364 test (1 dilewati);
  - test anp1 7/7, dan vektor ANP/1 yang dibangkitkan ulang identik.
- **Pemindai sendiri:** 42 test, dan semua mutasi tertangkap (13 + 10 + 19).
- **Review akhir** menemukan 1 Critical dan 4 Important; semuanya diperbaiki dengan test lebih dulu:
  - saat git gagal, gitleaks 8.30 tetap exit 0 dengan laporan kosong;
  - clone dangkal hanya memindai commit terakhir;
  - `gitleaks:allow` dan `.gitleaksignore` bisa menembus kebijakan allowlist;
  - pemindaian build melewatkan aturan berbasis path seperti `.p12`;
  - halaman OSV yang hanya berisi token lolos.

`jev_gate`: eskalasi (komposit 0,66, rubrik pembatas *correctness*). Satu klaim dibantah karena fungsinya dikirim sebagai ringkasan, bukan kode. Tidak diajukan ulang. Minor yang ditunda ada di [backlog](../backlog.md).

## Pelajaran

- [Verifikasi uji dan gerbang commit](../lessons/verifikasi-uji-dan-gerbang.md):
  - exit code alat bukan bukti hasil;
  - pemindai secret kini ikut menggerbangi setiap commit.
- [jev_gate memverifikasi klaim hanya dari butir evidence](../lessons/jev-gate-butir-evidence.md): kirim kode yang diklaim apa adanya, bukan ringkasan.
- **Temuan dependensi sering ditutup oleh kenaikan versi yang kecil.** pgx v5.9.2 sekaligus membuang x/crypto dari graf modul, jadi 18 temuan informasinya hilang tanpa menaikkan direktif `go` ke 1.26.
