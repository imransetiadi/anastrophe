---
type: decision
project: anastrophe
date: 2026-11-07
adr: ADR-0062
jev: accept
confidence: 1.0
status: Diterima
---
# ADR-0062 — Fokus berikutnya: race pembatalan pindai BLE (test flaky)

- **Pilihan:** `ble_flaky_test_fix` — ganti `async let scanned` di `BLETapCoordinator.run()` dengan `Task` eksplisit yang di-`cancel()`+`await .result` sebelum `finish()` menutup stream, sehingga pembatalan pindai BLE deterministik.
- **Status:** Diterima (JEV 1,0, tanpa eskalasi).
- **Akar masalah:** `async let` dibatalkan & di-`await` implisit oleh Swift di akhir scope `run()`, yaitu *setelah* `finish()` sudah menutup stream — pengamat bisa memeriksa `scanWasCancelled` sebelum handler pembatalan sempat jalan.
- **Kandidat lain:** `provisioning_concurrency_test_hardening` (sleep 300 ms di tiga test backend Go) — JEV 0; tidak bersinggungan dengan aturan keras CLAUDE.md, tetap kandidat untuk fokus berikutnya.
- **Verifikasi:** `ANChannelBLETests` 25× berturut-turut (host) dan `xcodebuild` simulator iPhone 17 Pro, keduanya lulus tanpa flaky.
- **Dokumen lengkap:** `docs/adr/0062-fokus-berikutnya-ble-scan-cancel-race.md`. Sesi: [race pembatalan pindai BLE](../sessions/2026-11-07-ble-scan-cancel-race.md). Lihat juga [[ADR-0061]], [[ADR-0019]].
