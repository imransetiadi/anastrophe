---
type: session
project: anastrophe
date: 2026-11-01
status: berjalan
tags: [ios, riwayat-tap, registri, jev, github]
---
# 2026-11-01 — Minor riwayat tap, fokus registri, push ke GitHub

Lanjutan dari [Perbaikan review riwayat tap](2026-11-01-perbaikan-riwayat-tap.md).

## Minor riwayat tap

Rencana: `docs/superpowers/plans/2026-11-01-riwayat-tap-minor.md`.

- M3: baris yang tak terbaca dilewati (`compactMap`). M1: `removeAll(except:)`, dan entri yatim dibersihkan saat daftar dimuat, hanya bila kartu berhasil dibaca.
- M2: `isLoading` turun setelah daftar siap; riwayat menyusul.
- M4: `switch` exhaustive dan test parameter untuk semua event non-transaksi. M7: test urutan simpan memakai store bergerbang. M6: test lifecycle lewat `RecordingLauncher`. M5: test hapus memakai dua kartu.
- Badge status di AX5 ditumpuk di bawah label (`AnyLayout`). `LabeledContent` dicoba lebih dulu, tetapi merusak baris pada ukuran standar.
- M8 tidak dikerjakan: ID dan EN berurutan sama.
- Bukti: host 242 test, simulator 240 (masing-masing 1 dilewati); uji mutasi tertangkap untuk penjaga gagal-muat, urutan simpan, dan `cancel()`.
- Review akhir masih berjalan.

## Keputusan

- [ADR-0031](../decisions/ADR-0031-fokus-registri-enrolment-server.md): registri kartu fisik dan pencocokan enrolment di server (JEV 0,88).
- [ADR-0032](../decisions/ADR-0032-perangkat-tambahan-menunggu-persetujuan.md): perangkat tambahan menunggu persetujuan sampai akun ada (JEV 0,71, provisional).
- Draf spesifikasi registri: `docs/superpowers/specs/2026-11-01-registri-kartu-design.md`.

## ADR-0001 dan GitHub

- Perubahan ADR-0001 dari pengguna ikut di-commit atas persetujuan eksplisit. Kalimat Keputusan kini "meng-clone UID/data sektor", bertentangan dengan judul dan Konteks ADR itu, CLAUDE.md aturan 1, serta PRD NG1/FR-11; menunggu klarifikasi.
- Branch `feat/r1-scaffold` di-push ke repo GitHub private `imransetiadi/anastrophe` setelah pemindaian secret pada seluruh riwayat.
