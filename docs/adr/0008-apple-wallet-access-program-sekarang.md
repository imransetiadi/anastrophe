# ADR-0008: Ajukan Apple Wallet Access Program sekarang (M0); kanal W di R2 dengan Aliro

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** O-W03, O-W18, O-L02, I-08, U07

## Konteks

Kanal W memberi paritas UX tertinggi (Express, power reserve, Apple Watch). Prosesnya: kuesioner, diligence, ABR, sertifikasi IOT reader, dan uji E2E bersama Apple. Ketersediaan wilayah dan biaya belum diketahui.

## Keputusan

Kirim kuesioner partisipan ke Apple **di M0**. Diligence berjalan paralel dengan R1. Target model single-party (Anastrophe = Credential Manager + Credential Provider Aliro).

## Konsekuensi

Unknown U07/U12 terungkap lebih awal. Tim harus menyiapkan peran wajib (sponsoring exec, signing authority, on-call) sejak awal.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** When should Anastrophe apply to the Apple Wallet Access Program?
- **Prioritas yang diberikan:** Reach Samsung-level UX as early as possible without derailing R1; surface unknowns (regions, fees) early; avoid wasted effort if Apple declines.
- **Hasil:** `apply_now` · confidence **1** · escaped: false
- **Biaya:** 1299 token input + 203 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `apply_now` | 1 | Send the participant questionnaire during M0 (now), run diligence in parallel with R1 engineering. |
| `after_r1_ga` | 0 | Apply only after R1 general availability. |
| `partner_existing_provider` | 0 | Do not apply directly; partner with an existing Wallet credential provider (e.g., a reader vendor) for R2. |
| `ask_user` | 0 | _escape hatch_ |
| `investigate` | 0 | _escape hatch_ |
| `none` | 0 | _escape hatch_ |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | Surfaces regional availability and fee unknowns before R1 general availability. | supported |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
