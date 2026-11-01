# ADR-0022: Reader uji BLE untuk M1 tanpa *service data* (terbuka)

- **Status:** Diusulkan — butuh keputusan manusia (eskalasi)
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** O-B05, O-B06, SDD §6.3 dan §7, QA rig R2/R7, TC-PRSB-01, rencana R1 Task 11 Step 2, ADR-0016

## Konteks

TC-PRSB-01 (kriteria keluar M1) butuh reader uji BLE. Tim punya Mac dan iPhone, tetapi belum punya dev board maupun reader referensi R2 (ADR-0016).

Peripheral berbasis CoreBluetooth (macOS/iOS) hanya bisa mengiklankan nama lokal dan service UUID (O-B05, O-B06). App saat ini mengabaikan pengiklan service ANP yang tidak membawa *service data* berisi `group_id` 8 B (`Packages/Sources/ANChannelBLE/LiveBLECentral.swift:139-147`). Padahal nilai itu tidak dipakai untuk memilih reader; pemilihan hanya berdasarkan RSSI (FR-83).

Keamanan tidak bergantung pada iklan. Ponsel tidak mengungkap identitas sebelum `sig_R` reader group valid, dan group tak dikenal dijawab identik dengan tanda tangan salah (`6982`, SDD §7, ADR-0003).

## Opsi

| Opsi | Ringkas | Probabilitas JEV |
|---|---|---|
| `mac_reader_optional_group` | Reader uji macOS (CoreBluetooth, memakai ulang logika reader Swift). App menerima iklan tanpa `group_id` di **semua** build; SDD §6.3 diubah menjadi "reader sebaiknya mengiklankan `group_id`, ponsel tidak mewajibkannya". | 0,27 |
| `mac_reader_debug_fallback` | Reader uji macOS yang sama. Iklan tanpa `group_id` diterima **hanya di build DEBUG**; Release tetap ketat. | 0,30 |
| `devboard_r7_firmware` | Firmware R7 di dev board (nRF52/ESP32) yang mengiklankan *service data*; app tetap ketat. Perlu membeli dev board dan menulis ulang logika reader dalam C. | 0,03 |
| `wait_for_r2` | Tidak membuat reader uji; tunggu R2. | 0,01 |

*Escape hatch:* `ask_user` 0,09 · `investigate` 0,10 · `none` 0,20.

## Keputusan

**Belum diputuskan.** Confidence 0,18 (< 0,60). Requirement 3 ("jalur discovery yang diuji di lab sama dengan yang dirilis") dinilai *contradicted* untuk kedua opsi Mac, sehingga keputusan dieskalasi ke pengguna (ADR-0018). Keputusan ini tidak diajukan ulang ke JEV tanpa bukti baru.

Pertukaran yang perlu dipilih pengguna:

- **`mac_reader_optional_group`:** satu jalur kode di semua build. Ponsel juga menerima pengiklan ANP tanpa `group_id`; ini aman secara protokol, tetapi isi iklan reader lab berbeda dari reader produksi.
- **`mac_reader_debug_fallback`:** Release tetap ketat sesuai SDD §6.3, tetapi uji lab memakai cabang discovery khusus DEBUG.
- **`devboard_r7_firmware`:** jalur discovery identik dengan produksi, tetapi butuh perangkat keras baru dan implementasi C kedua.

## Konsekuensi

Sampai keputusan ini diambil, TC-PRSB-01 tetap tertunda dan reader uji tidak dibangun. Pekerjaan lain yang tidak bergantung pada pilihan rig tetap berjalan.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** How should Anastrophe obtain a BLE test reader for the M1 lab tap test (TC-PRSB-01, R1 plan Task 11 Step 2) now, given that CoreBluetooth peripherals cannot advertise the service-data group_id the app currently requires?
- **Prioritas yang diberikan:** unblock TC-PRSB-01 dengan perangkat yang ada (Mac + iPhone); jangan melemahkan ANP/1; jalur discovery lab = Release; jaga jalan ke R7/R2.
- **Hasil:** `selected: null` · status `escalate` · confidence **0.18** · requirement 3 *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round6.input.json`](jev-log/2026-11-01-round6.input.json), [`jev-log/2026-11-01-round6.output.json`](jev-log/2026-11-01-round6.output.json)
