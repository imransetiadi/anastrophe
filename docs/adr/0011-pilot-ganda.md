# ADR-0011: Pilot ganda: Indonesia (BLE) + Singapura/Malaysia (NFC + BLE)

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** O-A08, I-06, PRD §13

## Konteks

Pasar utama tim ada di Indonesia, sementara NFC in-app hanya tersedia di wilayah eligible dan butuh entitas di wilayah tersebut.

## Keputusan

R1 menjalankan **dua pilot**: satu gedung di Indonesia (kanal B) dan satu di Singapura/Malaysia (kanal N + B).

## Konsekuensi

Dibutuhkan entitas/akun Apple di wilayah eligible untuk pilot NFC (ADR-0017), dan reader referensi dikirim ke dua lokasi.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Where should Anastrophe run its R1 pilot?
- **Prioritas yang diberikan:** Validate product-market fit in the company's home market while proving NFC tap on iPhone in a real building; keep legal/entity overhead in R1 manageable.
- **Hasil:** `dual_pilot` · confidence **0.84** · escaped: false
- **Biaya:** 1869 token input + 332 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `dual_pilot` | 0.87 | Two pilots: one Indonesian building on BLE and one Singapore or Malaysia building on NFC + BLE. |
| `ask_user` | 0.04 | _escape hatch_ |
| `investigate` | 0.04 | _escape hatch_ |
| `none` | 0.03 | _escape hatch_ |
| `sg_my_hk` | 0.01 | Pilot only in Singapore/Malaysia/Hong Kong with NFC + BLE. |
| `indonesia_ble` | 0.01 | Pilot only in Indonesia with BLE. |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | Validates NFC tap on iPhone in a real building. | supported |
| 1 | Validates the product with end users in Indonesia. | supported |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
