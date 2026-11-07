---
type: decision
project: anastrophe
date: 2026-11-07
adr: ADR-0062
jev: accept
confidence: 0.85
status: Diterima
---
# ADR-0062 — Fokus berikutnya: presedensi galat `withDeferredAudits` dan guard audit tak di-flush

- **Pilihan:** `audit_deferred_flush_precedence_test` — pin test bahwa galat `fn` menang atas galat `flushAudits` di `withDeferredAudits` ([[ADR-0051]]), dan tambah guard `Tx.checkFlushed()` yang dipanggil `Store.InTx` agar `deferAudits()` tanpa `flushAudits()` gagal keras (`errUnflushedAudits`), bukan diam-diam kehilangan event audit.
- **Status:** Diterima (JEV 0,85, tanpa eskalasi).
- **Kandidat lain:** `provisioning_concurrency_test_hardening` — JEV 0; butuh `pg_stat_activity` (PostgreSQL hidup), kalah dari kandidat yang bisa diuji murni unit. Tetap kandidat untuk fokus berikutnya.
- **Verifikasi:** `go test ./... -race` (13 paket, PostgreSQL asli) lulus; mutasi (hapus panggilan `checkFlushed()` di `InTx`) tertangkap `TestInTxMenegakkanGuardFlush` sebelum dikembalikan.
- **Catatan percabangan:** dikerjakan di branch `fix/audit-deferred-flush-precedence-test`, fork dari `main` (baru sampai [[ADR-0061]]). Unit `ble_flaky_test_fix` dikerjakan paralel di branch lain juga bernomor ADR-0062 di branch itu — perlu renumber salah satu saat kedua branch digabung.
- **Dokumen lengkap:** `docs/adr/0062-fokus-berikutnya-audit-deferred-flush-precedence.md`. Sesi: [presedensi galat audit deferred](../sessions/2026-11-07-audit-deferred-flush-precedence.md). Lihat juga [[ADR-0024]].
