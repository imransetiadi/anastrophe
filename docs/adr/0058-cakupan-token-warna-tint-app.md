# ADR-0058: Cakupan token warna dan tint app `secondary` (NFR-A01, TC-UX-03)

- **Status:** Diterima (JEV 0,95)
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** NFR-A01, TC-UX-01, TC-UX-03, `docs/design-system/anastrophe/pages/ios-app.md` §3, ADR-0018, ADR-0057, spesifikasi `docs/superpowers/specs/2026-11-02-audit-aksesibilitas-design.md` ("Keputusan sesudah bukti audit pertama" butir 1)

## Konteks

Audit pertama ADR-0057 menunjukkan sebagian teks app masih memakai warna sistem iOS. Inventaris warna diukur di runtime iOS 26.5 (simulator iPhone Air 3x, piksel screenshot dalam sRGB, rumus WCAG 2.x). Hasilnya di commit `ee09123`, terang/gelap:

| Elemen | Warna efektif | Kontras | Ditandai audit otomatis? |
|---|---|---|---|
| Nilai `LabeledContent` (5 tempat) dan hitungan "Lihat semua" | `secondaryLabel` | 3,44 / 6,07 | tidak (elemen gabungan) |
| 7 header dan 2 footer seksi | `secondaryLabel` | 3,38 / 6,30 | ya |
| Deskripsi daftar kosong | `secondaryLabel` | 3,38 / 6,30 | ya |
| "Hapus kartu" | `systemRed` | 3,57 / 5,20 | ya |
| Teks `ShareLink` Bantuan | `systemBlue` (tint bawaan) | 3,52 / 5,52 | ya |
| Placeholder `ANTextField` | `placeholderText` | 1,72 / 2,45 | tidak |
| Tombol merah `confirmationDialog` | `systemRed` di atas kaca | 2,46 / 3,80 | tidak |
| Chevron `NavigationLink` (non-teks, 3:1) | `tertiaryLabel` | 1,72 / 2,44 | tidak |

Hasil lain yang relevan:
- App tidak punya aset AccentColor. Akibatnya tint bawaan adalah `systemBlue` #0088FF / #0091FF, yang hanya 3,52:1 di atas putih.
- `performAccessibilityAudit` menerapkan ambang WCAG 2.x persis, tetapi tidak melihat nilai `LabeledContent`, placeholder, dialog, dan chevron.
- Prototipe tint `secondary` dengan token untuk sisa teks mengukur semua yang dikendalikan app ≥ 9,4:1, kecuali "Hapus kartu" (`destructive`, 4,83 / 6,45).

## Hasil JEV

- **Hasil:** `token_semua_tint_secondary` · confidence **0.95** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round43.input.json`](jev-log/2026-11-02-round43.input.json), [`jev-log/2026-11-02-round43.output.json`](jev-log/2026-11-02-round43.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `token_semua_tint_secondary` | 0.96 | ketiganya *supported* |
| `token_semua_tint_primary` | 0.00 | ketiganya *contradicted* |
| `hanya_yang_ditandai` | 0.00 | kontras dan peran warna *contradicted*; tanpa perubahan token *supported* |

## Keputusan

- **Semua teks yang dikendalikan app memakai token:**
  - nilai `LabeledContent`, hitungan "Lihat semua", header dan footer seksi, deskripsi daftar kosong, serta placeholder `ANTextField` memakai `mutedForeground`;
  - "Hapus kartu" memakai `destructive`.
- **Tint app `secondary`:**
  - `.tint(ANColor.secondary)` dipasang sebagai modifier terluar `KeysView`, sesudah `.sheet`, agar menjangkau semua lembar;
  - aset AccentColor bernilai sama dengan token `secondary` (#1E3A8A / #93C5FD) agar alert, share sheet, dan menu ikut;
  - sebuah test menjaga aset tetap sama dengan token.
- **Elemen sistem yang tidak bisa diwarnai app** (tombol merah `confirmationDialog`, chevron `NavigationLink`) dicatat sebagai keterbatasan yang diketahui di QA §11.1, beserta rasionya. Audit otomatis tidak menandai elemen ini, jadi tidak ada entri pengecualian audit untuknya.
- **Lint menolak gaya tombol terisi** `.borderedProminent` dan `.glassProminent`. Tanpa warna eksplisit, gaya itu memberi teks putih di atas tint gelap #93C5FD (1,80:1).
- **Nilai token tidak berubah.** Klaim design system §3 dan TC-UX-03 tidak dipersempit.

## Konsekuensi

- Item toolbar dan ikon berubah dari hitam/putih atau biru sistem menjadi `secondary` (biru tua di mode terang, biru muda di mode gelap). Bilah kaca tetap tanpa isi.
- Token tidak menguat saat Increase Contrast aktif, berbeda dengan warna sistem. Namun semua token teks sudah ≥ 4,6:1.
- Kontras teks app tidak lagi bergantung pada perubahan warna sistem di rilis iOS berikutnya.
