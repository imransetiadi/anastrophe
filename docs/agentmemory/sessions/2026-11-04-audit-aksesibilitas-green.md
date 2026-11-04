---
type: session
project: anastrophe
date: 2026-11-04
status: selesai-kecuali-gate
tags: [aksesibilitas, nfr-a01, tc-ux-01, tc-ux-02, tc-ux-03, tc-ux-04, tc-ux-09, xcuitest]
---
# 2026-11-04 — Audit aksesibilitas app: GREEN di dua perangkat

Lanjutan [sesi 2026-11-02](2026-11-02-audit-aksesibilitas.md): sisa Task 4 (Step 6–11) dan Task 5 dari rencana `docs/superpowers/plans/2026-11-02-audit-aksesibilitas.md`.

Keputusan yang dipakai:
- [ADR-0057](../decisions/ADR-0057-fokus-audit-aksesibilitas.md): fokus unit;
- [ADR-0058](../decisions/ADR-0058-cakupan-token-warna-tint-app.md): cakupan token;
- [ADR-0059](../decisions/ADR-0059-pengecualian-kontras-per-elemen.md): pengecualian per elemen dengan bukti.

Tidak ada keputusan JEV baru.

## Perubahan

- **App (`a240a52`):**
  - Di AX5, pilihan cara Tambah Kartu dan status cara akses Bantuan ditumpuk, sehingga kata tidak terpecah ("undanga/n").
  - Identifier `present.title` dan `present.detail`.
  - Lint host `tanpaPemotongTeks`.
- **Harness UI test (`83c9f41`, `4d4e1e7`):**
  - Posisi gulir yang dipindah audit dipulihkan dengan seretan terukur: maju ≤ 500 pt, mundur ≤ 100 pt agar lembar tidak tertutup.
  - Kesinambungan halaman dicek per kemunculan label.
  - Gulir pendek di ujung isi tetap menjadi halaman baru.
  - Audit yang habis waktu diulang dua kali, lalu sekali lagi sesudah isi digeser 48 pt.
  - `elementDetection` ikut aturan zona kaca bilah.
  - Penjaga mode terang/gelap dari kecerahan screenshot.
  - `KunciFungsionalTests`: "Gunakan" membuka lembar presentasi, dan ketukan di area kosong sel FAQ membuka jawaban.
- **Pengecualian per elemen** (36 entri). Empat entri `dynamicType` juga berlaku di AX5, dengan bukti screenshot elemen dari audit itu sendiri: pemberitahuan ditangguhkan dan "Hapus kartu", masing-masing ID dan EN.
- **Dokumen:**
  - QA §11.1: TC-UX-01, -02, -03, -04, -09, dan baris pengecualian;
  - SDD §5.10 dan versi 2.35;
  - README: ±75 menit per perangkat, `-resultBundlePath`;
  - backlog dan [pelajaran](../lessons/audit-aksesibilitas-otomatis.md).

## Bukti

- **Swift host:** 394 test di 10 run, 1 dilewati, 0 gagal.
- **iPhone 17 Pro atas `4d4e1e7`:** 37/37 lulus (`TEST SUCCEEDED`, 59 menit). 147 halaman, 0 isu dihitung, 315 dikecualikan dengan alasan, 31 `AUDIT-SKIP`.
- **iPhone 17e atas `83c9f41`:** 36/37 lulus (75 menit). 155 halaman, 0 isu dihitung, 369 dikecualikan, 43 `AUDIT-SKIP`. Satu-satunya yang gagal, riwayat AX5, gagal karena audit habis waktu di halaman 2; test itu lulus atas `4d4e1e7`.
- **Mutasi UI 2/2 tertangkap:**
  - bingkai `present.cancel` dipindah ke luar tombol → 37 × 19 pt dan `hitRegion`;
  - tombol Bantuan tanpa label → `sufficientElementDescription`.
- **Build Release simulator** lulus. `strings` biner tanpa `demo.invalid`, `presentation-denied`, `ANDemoScreen`, `detail-suspended`, dan `bluetooth-denied`.
- **Screenshot** daftar, detail, presentasi, dan Tambah Kartu (terang, gelap, AX5 ID/EN) diekspor ke `build/audit-evidence/`, di luar git. Result bundle disimpan di `build/results/`.
- **Penjaga mode:** kecerahan layar gelap ≤ 0,12 dan layar terang ≥ 0,79, jauh dari batas 0,25 dan 0,5.

## Belum selesai

Rinciannya di [backlog](../backlog.md):
- review akhir dan `jev_gate`, karena alatnya tidak tersedia di sesi ini;
- VoiceOver manual di iPhone fisik;
- TC-UX-05;
- CI UI test;
- pencocokan pesan galat dengan SDD §15.
