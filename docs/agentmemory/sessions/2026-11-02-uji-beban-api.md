---
type: session
project: anastrophe
date: 2026-11-02
status: selesai
tags: [backend, uji-beban, tc-perf-05, nfr-p05]
---
# 2026-11-02 — Uji beban API dan baseline lab (TC-PERF-05)

Keputusan: [ADR-0055](../decisions/ADR-0055-fokus-uji-beban-api.md) (JEV 0,95). Rencana: `docs/superpowers/plans/2026-11-02-uji-beban-api.md`.

## Perubahan

- **Alat `anastrophe-loadtest` (stdlib):**
  - skenario config, lookup kode gedung, enrol (enrolment + provisioning), dan renew (tantangan + perpanjangan);
  - laporan p50/p95/p99, galat per status, dan porsi ≤ 0,3 dtk per rute dari `/metrics`.
- **Batas aman:**
  - hanya kartu sintetis (awalan `084c54`);
  - hanya host loopback kecuali `-allow-remote`, dan redirect tidak diikuti;
  - rahasia enrolment dan kunci kredensial hanya hidup di memori.
- **Sesudah review akhir:**
  - enrol mengikuti jalur app (`Idempotency-Key`, `status_token_hash`);
  - `-rate` menghitung token yang terlewat dan gagal bila lebih dari 5%;
  - run yang berhenti lebih awal keluar dengan exit 3, dan kegagalan `/metrics` dilaporkan;
  - batas galat inklusif.

## Bukti

- **Baseline lab:** build `4d31e51`, 8 run, semua exit 0, 0 galat, histogram server 100% ≤ 0,3 dtk. Angka per run, c=8 / c=32:

  | Skenario | Laju |
  |---|---|
  | config | 69,7 rb / 67,6 rb rps |
  | lookup | 40,0 rb / 37,2 rb rps |
  | enrol | 1.114 / 869 iterasi/dtk |
  | renew | 2.226 / 1.635 iterasi/dtk |

  Ini bukan bukti produksi; angka lengkap ada di QA §11.1.
- **Jejak database cocok dengan jalur app:** 40.086 instance ber-hash token dan 157.416 baris idempotency.
- **Suite dan mutasi:** suite backend 13 paket lulus dengan `-race`, dan mutasi pada perbaikan 15/15 tertangkap.
- **Cacat alat:** baseline pertama membuka tiga cacat, dan review akhir menemukan tiga lagi. Semuanya diperbaiki dengan test lebih dulu sebelum baseline final.

`jev_gate`: eskalasi (komposit 0,81, rubrik pembatas *test_gap*), tidak diajukan ulang. Klaim tentang suite lemah karena log suite hanya ada di kolom `tests`, dan kalimatnya mencakup dua perbaikan dokumen yang tidak punya test. Minor yang ditunda ada di [backlog](../backlog.md).

## Pelajaran

- **Uji beban harus menempuh jalur klien sungguhan.** Header atau field opsional yang selalu dikirim app (di sini `Idempotency-Key` dan `status_token_hash`) memilih jalur server yang berbeda. Cocokkan skenario dengan klien, lalu buktikan lewat jejak di database.
- **Laju terjadwal harus melaporkan kekurangannya.** Pekerja closed-loop yang lambat diam-diam menurunkan laju (coordinated omission). Hitung token yang terlewat dan gagalkan run bila target tidak benar-benar diuji.
- **Angka lab bervariasi antar-sesi.** Renew c=8 naik dari 1.827 ke 2.226 iterasi/dtk dengan permintaan yang sama. Bandingkan angka hanya dalam satu sesi lab dengan build yang sama.
- [jev_gate memverifikasi klaim hanya dari butir evidence](../lessons/jev-gate-butir-evidence.md): log uji harus menjadi butir `evidence`, dan klaim harus setepat buktinya.
