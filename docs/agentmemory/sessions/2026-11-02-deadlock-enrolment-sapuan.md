---
type: session
project: anastrophe
date: 2026-11-02
status: selesai
tags: [backend, postgresql, keandalan, nfr-r02]
---
# 2026-11-02 — Deadlock enrolment–sapuan per jam (NFR-R02)

Keputusan: [ADR-0051](../decisions/ADR-0051-fokus-deadlock-enrolment-sapuan.md) (JEV 0,96). Rencana: `docs/superpowers/plans/2026-11-02-deadlock-enrolment-sapuan.md`.

## Perubahan

- **Penahanan audit:** `Tx` menahan event audit, lalu `EnrollCard`, `EnrollInvitation`, dan sapuan per jam menulisnya di akhir pemanggilan store. Urutannya stabil per rantai, sehingga kunci rantai diambil dalam urutan yang sama di semua transaksi.
- **Jalur galat dan bersarang:** event tetap ditulis saat enrolment gagal (galat fn didahulukan). Penahanan bersarang diserahkan ke pemanggil luar.
- **Lanjutan `PENDING_APPROVAL`:** jalur kartu mengunci baris instance yang dilanjutkan (dijaga status, diulang sekali bila berubah). Langkah handler sesudahnya hanya mengubah baris yang sudah dikunci.
- **Baris gedung (review akhir):** `AppendAudit` mengunci `sites` `FOR KEY SHARE` sebelum kunci rantai, jadi perintah `policy`/`site-code` (`sites FOR UPDATE`) tidak lagi bisa deadlock dengan enrolment.

## Bukti

- 10 test baru dengan pola deterministik: transaksi lain menahan baris, polling `pg_stat_activity` (dibatasi ke database test), lalu `pg_try_advisory_lock` dari koneksi lain.
- RED dilihat untuk setiap perubahan: penahanan, kunci `PENDING_APPROVAL`, dan `KEY SHARE`.
- 10 mutasi tertangkap.
- Probe operator asli: 40P01 tanpa perbaikan, lulus dengan perbaikan.
- Go 10 paket lulus; 5× `-race` lulus.

`jev_gate`: eskalasi (safe_to_apply 0,53, `test_gap`), dicatat tanpa diajukan ulang. Minor ada di [backlog](../backlog.md).

## Pelajaran

- [Kunci implisit foreign key ikut dalam urutan kunci](../lessons/kunci-implisit-foreign-key.md).
- **Test baru harus dijalankan pada kode yang benar sebelum uji mutasi.** Test penahanan bersarang awalnya menghitung event `registry.imported` dari setup. Akibatnya test itu gagal juga pada kode yang benar, sehingga mutasi tampak "tertangkap" karena alasan yang salah.
