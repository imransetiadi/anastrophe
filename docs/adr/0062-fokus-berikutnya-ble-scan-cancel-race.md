# ADR-0062: Fokus berikutnya: race pembatalan pindai BLE di `BLETapCoordinator` (test flaky)

- **Status:** Diterima
- **Tanggal:** 2026-11-07
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0)
- **Rujukan:** ADR-0018, ADR-0019, ADR-0061, CLAUDE.md aturan 4 (timing presentment kanal in-app)

## Konteks

ADR-0061 menutup unit `provisioning_secret_hash_type_safety` dan mencatat dua kandidat sisa yang tetap valid untuk fokus berikutnya: `ble_flaky_test_fix` dan `provisioning_concurrency_test_hardening`. Sesi ini memverifikasi ulang keduanya langsung terhadap kode (2026-11-07) — keduanya masih ada persis seperti dicatat ADR-0061 — lalu memakai `jev_decide` untuk memilih satu.

## Hasil JEV

- **Hasil:** `ble_flaky_test_fix` · confidence **1.0** · escaped: false · tanpa requirement *contradicted* untuk kandidat terpilih
- **Log mentah:** [`jev-log/2026-11-07-fokus-berikutnya-ble-flaky.output.json`](jev-log/2026-11-07-fokus-berikutnya-ble-flaky.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `ble_flaky_test_fix` | 1.0 | ketiganya *supported* |
| `provisioning_concurrency_test_hardening` | 0 | req. "bersinggungan dengan aturan keras CLAUDE.md" *contradicted* — murni soal keandalan CI backend, tidak menyentuh jalur yang diatur CLAUDE.md |

Confidence 1,0 ≥ 0,80 (ADR-0018) → **Diterima** tanpa eskalasi.

## Analisis akar masalah

`BLETapTests.autentikasiBatalMembatalkanPemindaian` (`Packages/Tests/ANChannelBLETests/BLETapTests.swift`) memakai assertion OR-toleran `scanCount == 0 || scanWasCancelled` karena race nyata di `BLETapCoordinator.run()`:

`async let scanned = central.scan(...)` dideklarasikan sebelum `await authenticator.authenticate(...)`. Bila autentikasi gagal, `guard ... else { return finish(out, with: .cancelled) }` dieksekusi — `finish()` memanggil `out.yield(event)` lalu `out.finish()`, yang **langsung** membangunkan pembaca stream (`events.rest()` di test). Pembatalan+`await` implisit Swift atas `async let scanned` yang keluar scope terjadi di epilog fungsi `run()`, **setelah** `finish()` sudah dieksekusi di dalam ekspresi `return`. Akibatnya pengamat stream bisa memeriksa `scanWasCancelled` sebelum handler pembatalan `scan()` palsu sempat berjalan dan menyetel flag itu — bukan soal mesin sibuk semata, tapi urutan yang tidak dijamin oleh `async let`.

## Keputusan

Ganti `async let scanned = central.scan(...)` dengan `Task` eksplisit (`let scanTask = Task { try await central.scan(...) }`), dan di kedua jalur keluar dini (autentikasi gagal, provider gagal/app ke background) panggil `scanTask.cancel(); _ = await scanTask.result` **sebelum** `finish(out, with: .cancelled)`. Jalur sukses memakai `try await scanTask.value` menggantikan `try await scanned`. Perilaku runtime presentment BLE (ADR-0019: pindai paralel dengan autentikasi) tidak berubah — ini murni membuat urutan pembatalan deterministik, sesuai CLAUDE.md aturan 4 (timing/cancellation presentment harus tepercaya).

Assertion test diperketat jadi `#expect(h.central.scanWasCancelled)` tanpa toleransi OR, karena sekarang hasilnya deterministik.

`provisioning_concurrency_test_hardening` tetap kandidat valid untuk fokus berikutnya.

Unit berdiri sendiri dan kecil, dikerjakan langsung TDD tanpa dokumen spesifikasi/rencana terpisah, mengikuti preseden ADR-0060/0061.

## Penutupan unit

Diimplementasikan di `ANChannelBLE` (`BLETapCoordinator.run`) dan `ANChannelBLETests` (`BLETapTests.autentikasiBatalMembatalkanPemindaian`).

Bukti verifikasi langsung:
- RED dikonfirmasi analitis: assertion ketat (`scanWasCancelled` tanpa OR) dijalankan 8× berturut-turut dengan kode lama — lolos semua di mesin ini (beban rendah, race jendela sangat sempit, cocok dengan catatan backlog "sesekali gagal saat mesin sangat sibuk"); akar race dibuktikan lewat pembacaan kode (`async let` + epilog Swift), bukan reproduksi kegagalan langsung.
- GREEN: `swift build` lulus; `swift test` penuh (semua target, 9 proses test) lulus tanpa regresi.
- `ANChannelBLETests` dijalankan 25× berturut-turut via `swift test --filter` (host) — lulus semua, termasuk suite penuh, tanpa flaky.
- `xcodebuild -scheme AnastropheKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ANChannelBLETests test` → `TEST SUCCEEDED`.
- `python3 scripts/docs/check_docs.py .` → 0 masalah.

## Konsekuensi

- Tidak ada perubahan kontrak jaringan, UI, atau katalog error SDD §15.
- Modul yang disentuh: `ANChannelBLE` (coordinator), `ANChannelBLETests` (assertion).
- `provisioning_concurrency_test_hardening` menyusul sebagai unit terpisah.
