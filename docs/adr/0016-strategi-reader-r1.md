# ADR-0016: Strategi reader R1: reader referensi Anastrophe (NFC + BLE)

- **Status:** Diterima (provisional — tinjau ulang di akhir M1 (setelah survei reader U03))
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** O-R01, I-12, U03, D3

## Konteks

Pilot membutuhkan ANP/1 lewat NFC dan BLE. Reader transparan OSDP umumnya tanpa BLE. Firmware vendor butuh kerja sama SDK. R2 butuh reader ECP v2.3/Aliro bersertifikat.

## Keputusan

Pasang **reader referensi Anastrophe** (NFC + BLE, SE untuk kunci reader group, keluaran OSDP/Wiegand ke panel yang ada) di pintu pilot. Gateway untuk reader OSDP Transparent Mode tetap menjadi jalur retrofit opsional.

## Konsekuensi

Tim memerlukan kapabilitas hardware (desain, sertifikasi radio lokal). Ditinjau ulang setelah survei reader pilot.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Which reader strategy should Anastrophe use for the R1 pilots?
- **Prioritas yang diberikan:** R1 pilots must work on schedule in both pilot buildings (one BLE-only in Indonesia, one NFC + BLE in Singapore/Malaysia); minimize dependence on vendor SDK negotiations; keep a path to Aliro/ECP readers for R2.
- **Hasil:** `reference_reader` · confidence **0.66** · escaped: false
- **Biaya:** 2753 token input + 593 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `reference_reader` | 0.71 | Anastrophe reference reader (NFC + BLE, SE for the reader-group key) installed next to/in place of the pilot doors' readers, outputting OSDP/Wiegand to the existing panel. |
| `reference_plus_gateway` | 0.28 | Reference reader for pilot doors, plus the transparent-mode gateway as the retrofit path for buildings with compatible OSDP readers. |
| `investigate` | 0.01 | _escape hatch_ |
| `vendor_firmware` | 0 | Partner vendor readers loaded with ANP/1 firmware through the vendor's SDK. |
| `transparent_gateway` | 0 | Keep existing OSDP Transparent Mode readers and run ANP/1 in an Anastrophe edge gateway (NFC only). |
| `ask_user` | 0 | _escape hatch_ |
| `none` | 0 | _escape hatch_ |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | Supports BLE at the Indonesian pilot doors. | supported |
| 1 | Does not require a vendor SDK agreement before the R1 pilot. | supported |
| 2 | Supports NFC tap at the Singapore/Malaysia pilot doors. | supported |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
