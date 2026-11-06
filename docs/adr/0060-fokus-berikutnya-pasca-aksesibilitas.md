# ADR-0060: Fokus berikutnya pasca audit aksesibilitas (keempat kandidat disetujui)

- **Status:** Diterima — pengguna menyetujui keempat kandidat dikerjakan berurutan (eskalasi JEV diselesaikan manusia)
- **Tanggal:** 2026-11-06
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) mengusulkan; pengguna menyetujui semua kandidat alih-alih memilih satu
- **Rujukan:** NFR-S03, NFR-S09, NFR-O01, TC-UX-09, ADR-0018, ADR-0052, ADR-0054, ADR-0056

## Konteks

Unit audit aksesibilitas (ADR-0057) ditutup sampai batas otomatis; `jev_gate` penutupannya eskalasi (lihat Memory.md `APP-2026-11-06-0000`, log `jev-log/2026-11-06-audit-aksesibilitas-gate.json`) dan menunggu keputusan pengguna terpisah. Sesi ini mencari fokus kerja berikutnya yang **tidak** tumpang tindih dengan keputusan yang sudah dieskalasi sebelumnya (ADR-0017, 0022, 0038, 0041, 0046, 0047, penyambungan App Attest) dan tidak butuh iPhone fisik atau reader.

`docs/agentmemory/backlog.md` mencatat beberapa kelompok temuan review akhir yang berdiri sendiri dan bisa dikerjakan dengan TDD di host:
1. **App Attest verifier (ADR-0052):** validasi `clientDataHash`/challenge, `Verifier{}` nilai nol panic, penolakan platform non-`iphoneos`, migrasi field `p256PublicKey` yang deprecated — semuanya di paket verifier yang sudah ada, independen dari keputusan penyambungan endpoint.
2. **Observabilitas backend (ADR-0054):** panic sesudah header tercatat 200 bukan 500; 413 tidak menutup koneksi; `ErrorLog` belum ke slog Warn; `ANASTROPHE_LOG_FORMAT` peka huruf besar.
3. **Pemindaian keamanan (ADR-0056):** `-r` di requirements belum diikuti; hanya `Packages/Package.swift` yang diperiksa untuk `.package(`; satu pemeriksaan gagal menghentikan sisanya; alias OSV bisa membuat CVE tercetak dua kali.
4. **Pencocokan pesan galat vs SDD §15 (TC-UX-09 butir 9):** audit dokumen, lingkup kecil.

## Hasil JEV

- **Hasil:** `app_attest_hardening` · confidence **0.38** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-06-fokus-berikutnya.output.json`](jev-log/2026-11-06-fokus-berikutnya.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `app_attest_hardening` | 0.47 | keduanya *supported* |
| `observability_hardening` | 0.26 | keduanya *supported* |
| `error_catalog_alignment` | 0.15 | keduanya *supported* |
| `security_scan_hardening` | 0.10 | keduanya *supported* |

Confidence 0,38 < 0,60 (ADR-0018) → **eskalasi ke pengguna**, meski JEV tidak memilih escape hatch (`escaped: false`). Tidak ada requirement yang *contradicted* pada kandidat manapun — rendahnya keyakinan mencerminkan bahwa keempat kandidat sama-sama valid dan berdiri sendiri, bukan karena salah satunya cacat.

## Keputusan

Pengguna menyetujui **keempat kandidat** untuk dikerjakan, bukan memilih satu. Urutan pengerjaan mengikuti probabilitas JEV (tertinggi dulu), karena probabilitas mencerminkan independensi risiko dan ukuran unit yang disarankan model keputusan:
1. `app_attest_hardening` — pengerasan verifier App Attest (ADR-0052);
2. `observability_hardening` — pengerasan observabilitas backend (ADR-0054);
3. `error_catalog_alignment` — pencocokan pesan galat dengan SDD §15;
4. `security_scan_hardening` — pengerasan pemindaian keamanan (ADR-0056).

Setiap kandidat dikerjakan sebagai unit TDD terpisah dengan commit sendiri, diverifikasi sebelum lanjut ke kandidat berikutnya (superpowers: verification-before-completion).

## Konsekuensi

- Empat unit kerja backend/scripts menyusul di branch `iterasi-r1-lanjutan`, masing-masing dengan test baru dan commit sendiri.
- Tidak satu pun menyentuh keputusan yang sudah dieskalasi sebelumnya (penyambungan App Attest, oracle tebak kartu, dll.) — itu tetap terbuka.
