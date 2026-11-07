---
type: session
project: anastrophe
date: 2026-11-07
---
# Sesi 2026-11-07 — Fokus berikutnya pasca ADR-0061: race pembatalan pindai BLE

## Konteks

[[ADR-0061]] mencatat dua kandidat sisa yang tetap valid untuk fokus berikutnya: `ble_flaky_test_fix` dan `provisioning_concurrency_test_hardening`. Sesi ini memverifikasi ulang keduanya langsung terhadap kode — keduanya masih ada persis seperti dicatat — lalu memakai `jev_decide` untuk memilih satu (goal sesi: "lakukan improvement gunakan JEV as decision maker").

## Keputusan JEV

`jev_decide` memilih `ble_flaky_test_fix` (confidence 1,0, tanpa requirement *contradicted* untuk kandidat terpilih). `provisioning_concurrency_test_hardening` kalah karena req. "bersinggungan dengan aturan keras CLAUDE.md" *contradicted* — murni soal keandalan CI backend. Lihat [[ADR-0062]].

## Analisis akar masalah

`BLETapTests.autentikasiBatalMembatalkanPemindaian` memakai assertion OR-toleran `scanCount == 0 || scanWasCancelled`. Dibaca kodenya: `async let scanned = central.scan(...)` dideklarasikan sebelum `await authenticator.authenticate(...)` di `BLETapCoordinator.run()`. Bila autentikasi gagal, `return finish(out, with: .cancelled)` dieksekusi — `finish()` memanggil `out.finish()` yang langsung membangunkan pembaca stream (`events.rest()` di test). Pembatalan+`await` implisit Swift atas `async let scanned` yang keluar scope terjadi di epilog fungsi, **setelah** `finish()` sudah berjalan. Race murni urutan, bukan cuma soal mesin sibuk.

## Implementasi

- `BLETapCoordinator.run()`: `async let scanned` diganti `let scanTask = Task { try await central.scan(...) }`. Di kedua jalur keluar dini (autentikasi gagal; provider gagal/app ke background), tambahkan `scanTask.cancel(); _ = await scanTask.result` sebelum `finish(out, with: .cancelled)`. Jalur sukses memakai `try await scanTask.value`.
- `BLETapTests.autentikasiBatalMembatalkanPemindaian`: assertion diperketat ke `#expect(h.central.scanWasCancelled)` tanpa toleransi OR.

## Bukti uji

- RED dikonfirmasi analitis: assertion ketat dijalankan 8× berturut-turut dengan kode lama — lolos semua di mesin ini (beban rendah, jendela race sangat sempit); akar race dibuktikan lewat pembacaan kode, bukan reproduksi kegagalan langsung.
- GREEN: `swift build` dan `swift test` penuh (9 proses test, semua target) lulus tanpa regresi.
- `ANChannelBLETests` dijalankan 25× berturut-turut via `swift test --filter` (host) — lulus semua.
- `xcodebuild -scheme AnastropheKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ANChannelBLETests test` → `TEST SUCCEEDED`.
- `python3 scripts/docs/check_docs.py .` → 0 masalah.

## Berikutnya

`provisioning_concurrency_test_hardening` (tiga test backend Go `time.Sleep(300ms)`) tetap kandidat valid untuk fokus berikutnya.
