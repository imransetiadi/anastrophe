---
type: session
project: anastrophe
date: 2026-11-02
status: sebagian
tags: [aksesibilitas, nfr-a01, tc-ux-01, tc-ux-02, tc-ux-03, tc-ux-04, xcuitest, design-system]
---
# 2026-11-02 — Audit aksesibilitas app (sebagian)

Keputusan:
- [ADR-0057](../decisions/ADR-0057-fokus-audit-aksesibilitas.md): fokus unit, JEV 0,70, Provisional;
- [ADR-0058](../decisions/ADR-0058-cakupan-token-warna-tint-app.md): cakupan token, 0,95;
- [ADR-0059](../decisions/ADR-0059-pengecualian-kontras-per-elemen.md): pengecualian kontras, 0,93.

Spesifikasi `docs/superpowers/specs/2026-11-02-audit-aksesibilitas-design.md`; rencana `docs/superpowers/plans/2026-11-02-audit-aksesibilitas.md`.

## Perubahan

- **Task 1 (TC-UX-03):** token warna sebagai data (`ANColorToken`). `ContrastTests` memeriksa 15 pasangan teks/permukaan ≥ 4,5:1 di kedua mode, dan memastikan tabel design system §3 sama dengan kode.
- **Task 2:** lint sumber untuk ukuran font tetap dan animasi tanpa Reduce Motion.
- **Task 3:** 16 keadaan layar demo DEBUG (`-ANDemoScreen`) dan identifier penanda. Build Release tidak memuatnya.
- **Task 4 (sebagian):**
  - **Target UI test `AnastropheUITests`:** audit Apple terang/gelap dan AX5 ID/EN atas 16 keadaan, ditambah cek ukuran dan jarak target sentuh sendiri.
  - **Harness (agen A):** setiap layar menggulir kontainernya sendiri. Halaman tergulir dan elemen bilah sistem mengikuti aturan spesifikasi Tujuan 8, dan setiap isu dicetak sebagai `AUDIT-ISSUE`/`AUDIT-EXEMPT` (dengan alasan)/`AUDIT-SKIP`.
  - **Perbaikan target sentuh (agen B):**
    - `ANSecondaryButtonStyle`, `ANCompactAccentButtonStyle`, dan `ANTouchTarget` (44 pt, atau 50 pt dengan `.controlSize(.large)` untuk lembar setengah tinggi);
    - `StatusBadge` bertumpuk di AX5;
    - `ANTextField` berbasis UIKit, ≥ 44 pt;
    - latar baris `card`.
  - **ADR-0058:**
    - `ANMutedText` untuk judul/catatan seksi dan deskripsi daftar kosong, `ANValueRow` untuk nilai baris, placeholder bertoken;
    - "Hapus kartu" memakai `destructive`;
    - tint app `secondary` ditambah aset AccentColor;
    - lint `tanpaWarnaTeksSistem` dan `AccentColorAssetTests`.
- **Paralelisasi:** atas permintaan pengguna, tiga agen bekerja di worktree terpisah: A (harness dan RED penuh), B (perbaikan), C (inventaris warna sistem, hanya baca). Batch berikutnya dibatasi dua agen.

## Bukti

- **Swift host:** 391 test di 10 run, 1 dilewati, 0 gagal (sesudah ADR-0058). Satu run sebelumnya gagal di `autentikasiBatalMembatalkanPemindaian`, flaky BLE yang sudah dikenal saat mesin sibuk; test itu lulus 6/6 saat diulang.
- **Test paket di simulator** (`ANDesignSystemTests`): 7/7. Mutasi placeholder tertangkap di kedua mode.
- **Build:** Debug simulator lulus, `NSAccentColorName = AccentColor`. `build-for-testing` cabang terintegrasi juga lulus.
- **RED (agen A, harness sebelum perbaikan; 33 test, 54 menit; 10 lulus, 23 gagal):**

  | Varian | contrast | textClipped | dynamicType | hitRegion | elementDetection | target sentuh |
  |---|---|---|---|---|---|---|
  | terang | 19 | 18 | 13 | 4 | 6 | 25 |
  | gelap | 6 | 18 | 13 | 4 | 6 | 24 |
  | AX5 ID | 2 | 11 | 0 | 0 | 0 | 9 |
  | AX5 EN | 4 | 9 | 5 | 0 | 0 | 9 |

  Di luar tabel: 55 isu `AUDIT-SKIP` dan 123 isu dikecualikan dengan alasan.
- **Agen B (iPhone 17 Pro):** 102 kegagalan di 10 test → tanpa kegagalan target sentuh selain grabber lembar; `hitRegion` 0.
- **Agen C:** inventaris warna sistem iOS 26.5 dan kalibrasi audit, menjadi bukti ADR-0058/0059. Hasil gelap run RED pertama tidak sah karena screenshot "gelap" ternyata terang; di run agen A mode gelap berlaku.
- **Smoke cabang terintegrasi (iPhone 17 Pro):**
  - `testDaftarKartu` lulus di mode terang dan gelap.
  - `testPresentasiMenunggu` tersisa `elementDetection` ×2 tanpa elemen (latar redup lembar) dan `textClipped` pada "Mencari pembaca…". Keduanya kandidat pengecualian per elemen.

## Belum selesai

Rinciannya di [backlog](../backlog.md):
- GREEN penuh di dua perangkat, mutasi UI, cek `strings` Release, dan screenshot;
- pengecualian per elemen;
- verifikasi mode gelap sebelum audit;
- UI test fungsional "Gunakan";
- dokumen Task 5;
- review akhir dan `jev_gate`.

Atas permintaan pengguna, unit dihentikan di titik ini dan digabung lewat PR ke `feat/r1-scaffold`. Sisanya dikerjakan di [sesi 2026-11-04](2026-11-04-audit-aksesibilitas-green.md).

## Pelajaran

- [Batas audit aksesibilitas otomatis di iOS 26](../lessons/audit-aksesibilitas-otomatis.md)
