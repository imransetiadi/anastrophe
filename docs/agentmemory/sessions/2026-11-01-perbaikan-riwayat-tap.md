---
type: session
project: anastrophe
date: 2026-11-01
status: selesai
tags: [ios, riwayat-tap, review, jev]
---
# 2026-11-01 — Perbaikan review riwayat tap

Lanjutan dari [Riwayat tap lokal 30 hari](2026-11-01-riwayat-tap.md). Rencana: `docs/superpowers/plans/2026-11-01-riwayat-tap.md`.

## Temuan review akhir

- Critical: tidak ada.
- **I1:** store riwayat yang gagal dibuka membuat seluruh app masuk mode "penyimpanan tidak tersedia", padahal kartu dan Keychain sehat.
- **I2:** detail hanya menampilkan 20 baris di bawah judul "30 hari"; entri yang lebih lama tersimpan tetapi tidak bisa dibuka.

## Keputusan

- [ADR-0029](../decisions/ADR-0029-pemulihan-store-riwayat-tap.md): store dibuat ulang hanya bila rusak atau tak termigrasi (JEV 0,87).
- [ADR-0030](../decisions/ADR-0030-tampilan-riwayat-tap.md): lima tap terbaru dan "Lihat semua" (JEV 0,95).

## Perubahan

- `SwiftDataTapHistoryStore.openRecovering(directory:)` tidak pernah gagal. Klasifikasi rusak atau tak termigrasi memakai metadata Core Data ([pelajaran](../lessons/swiftdata-galat-tersembunyi.md)).
- `AppServices.live()` memakai pembukaan itu, jadi riwayat tidak lagi bisa membuat kartu tak tersedia.
- `TapHistoryPreview` (lima terbaru) dan layar `TapHistoryList`. String baru "Lihat semua" / "See all".
- Demo DEBUG kini mengisi delapan entri agar baris "Lihat semua" tampil.

## Bukti

- RED: kompilasi gagal karena `openRecovering` dan `TapHistoryPreview` belum ada. GREEN: empat test pemulihan, dua test ringkasan, dan satu test penjaga view model.
- Mutasi: `isUnusable` selalu `false` menggagalkan test store rusak dan skema lama; selalu `true` menggagalkan test store tak terbaca; batas 20 menggagalkan kedua test ringkasan.
- Suite: host 235 test (8 run, 1 dilewati, tanpa gagal); simulator 233 test (`TEST SUCCEEDED`, 1 dilewati). `check_docs.py` 0 masalah.
- Screenshot demo: mode terang (lima baris), mode gelap dengan build sementara batas 2 ("See all 8", lalu Pengaturan → Hapus kartu), dan AX5 (bagian info membungkus rapi).
- `jev_gate` dua run tereskalasi (composite 0,662 lalu 0,6885) dan menunggu tinjauan pengguna. Lihat [pelajaran gate](../lessons/jev-gate-butir-evidence.md).

## Tertunda

- Minor M1–M8 dari review (entri yatim, waktu muat, baris rusak, switch exhaustive, test dua kartu, lifecycle dengan wrapper, komentar test, format judul).
- Badge status terpotong "Ac-tive" pada AX5 (masalah lama).
- Layar riwayat lengkap belum dilihat langsung di simulator; uji E di perangkat tertunda.
