# ADR-0006: Minimum iOS 26.0 (iPhone 11+/SE 2+)

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** O-D01, O-D02, O-A08, NFR-CP01

## Konteks

NFC & SE butuh iOS 18.1–26.0 tergantung wilayah (Vietnam 26.0). iOS 27 adalah versi terbaru; iOS 26 tidak lagi mendukung XS/XR.

## Keputusan

Minimum **iOS 26.0**. Dukung iOS 26 dan 27 (N, N-1).

## Konsekuensi

Satu jalur kode untuk semua wilayah NFC & SE; perangkat terendah iPhone 11 dan iPhone SE gen 2.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** What minimum iOS version should the Anastrophe app require at launch?
- **Prioritas yang diberikan:** Cover every targeted NFC & SE region (including Vietnam) with one code path, keep the device/OS test matrix small, and still reach most active iPhones.
- **Hasil:** `ios_26_0` · confidence **0.87** · escaped: false
- **Biaya:** 1853 token input + 332 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `ios_26_0` | 0.89 | Minimum iOS 26.0 (iPhone 11 and later, iPhone SE 2nd gen and later); supports iOS 26 and iOS 27. |
| `none` | 0.06 | _escape hatch_ |
| `investigate` | 0.02 | _escape hatch_ |
| `ios_18_4` | 0.01 | Minimum iOS 18.4 (iPhone XS and later); Vietnam features gated at runtime to iOS 26. |
| `ios_27_0` | 0.01 | Minimum iOS 27.0 (latest only). |
| `ask_user` | 0.01 | _escape hatch_ |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | Meets the minimum iOS version required for NFC & SE in Vietnam without runtime gating. | supported |
| 1 | Supports no more than two major iOS versions at launch. | supported |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
