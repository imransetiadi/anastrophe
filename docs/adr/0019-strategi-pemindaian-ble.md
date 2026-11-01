# ADR-0019: Strategi pemindaian BLE Tap: pindai saat lembar dibuka + early exit

- **Status:** Diterima (keputusan pengguna, 2026-11-01) — sebelumnya dieskalasi karena confidence JEV 0,51
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** NFR-P04, FR-80, FR-83, O-B04, ADR-0012, SDD §6.3

## Konteks

SDD §6.3 menulis "pemindaian 5 dtk" sebelum memilih reader dengan RSSI tertinggi di atas ambang (FR-83). NFR-P04 menuntut intent → keputusan reader ≤ 1,5 dtk p95. Review kode akhir menemukan bahwa pemindaian tetap 5 dtk membuat NFR-P04 dan TC-PRSB-01 pasti gagal. Ini kontradiksi spesifikasi, bukan bug kode.

## Keputusan

**`prescan_early_exit`.** JEV condong ke opsi ini dengan confidence rendah (0,51) sehingga keputusan dieskalasi; pengguna menyetujuinya pada 2026-11-01 ("approve semua saran"). Kedua kandidat teratas sama-sama memakai aturan *early exit*: berhenti memindai segera setelah reader pertama memenuhi ambang RSSI, ditambah jeda ±300 ms untuk membandingkan RSSI, maksimal 5 dtk. `fixed_5s` bertentangan dengan NFR-P04 (probabilitas 0).

Aturan early exit (`ScanWindow`, `BLETapCoordinator.scanSettle`) diimplementasikan lebih dulu karena sama di kedua kandidat teratas. Pemindaian yang dimulai sejak lembar presentasi dibuka (paralel dengan Face ID) diimplementasikan setelah keputusan ini.

## Konsekuensi

Dengan early exit, waktu pindai biasanya ±0,3–0,6 dtk (interval iklan reader 100–250 ms). Bila `prescan_early_exit` dipilih, pindai dimulai sebelum autentikasi selesai; connect tetap hanya setelah autentikasi berhasil, dan tetap foreground saja (ADR-0012). Angka akhir divalidasi di HIL (TC-PRSB-01).

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** How should the Anastrophe BLE "Tap" flow scan for readers so that the R1 app meets its latency target while keeping strongest-reader selection?
- **Prioritas yang diberikan:** Meet NFR-P04 (<= 1.5 s p95 intent-to-decision) in the R1 pilots; keep FR-83; stay foreground-only (ADR-0012); keep the implementation simple and testable without hardware.
- **Hasil:** `prescan_early_exit` · confidence **0.51** · escaped: false
- **Biaya:** 2677 token input + 455 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `prescan_early_exit` | 0.59 | Start the filtered scan when the presentation sheet opens, in parallel with Face ID, with the early-exit rule; connect only after authentication succeeds. |
| `early_exit` | 0.39 | Treat 5 s as the maximum: stop as soon as a reader at/above the threshold is seen plus ~300 ms settle, then pick the strongest. |
| `investigate` | 0.01 | _escape hatch_ |
| `none` | 0.01 | _escape hatch_ |
| `fixed_5s` | 0 | Keep a fixed 5-second scan window (SDD §6.3 as written). |
| `ask_user` | 0 | _escape hatch_ |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | Can achieve intent-to-decision <= 1.5 s at p95 when a reader is within ~30 cm (NFR-P04). | supported |
| 1 | Processes only the strongest reader at or above the RSSI threshold (FR-83). | supported |
| 2 | Performs no Bluetooth scanning while the app is in the background (ADR-0012). | supported |

> `fixed_5s` dinilai *contradicted* untuk requirement 0. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
