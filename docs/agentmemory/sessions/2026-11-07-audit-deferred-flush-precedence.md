---
type: session
project: anastrophe
date: 2026-11-07
---
# Sesi 2026-11-07 — Fokus berikutnya pasca ADR-0061: presedensi galat `withDeferredAudits`

## Konteks

Satu kandidat sisa dari [[ADR-0061]] tetap ada (`provisioning_concurrency_test_hardening`). Dicari kandidat kedua dari `docs/agentmemory/backlog.md` bagian "Deadlock enrolment–sapuan (minor review akhir, ADR-0051)": `withDeferredAudits` (`backend/internal/store/audit.go`) punya komentar "Galat fn didahulukan" tanpa test eksplisit, dan `deferAudits()` tanpa `flushAudits()` tidak dijaga.

## Keputusan JEV

`jev_decide` memilih `audit_deferred_flush_precedence_test` (confidence 0,85) atas `provisioning_concurrency_test_hardening` (0) — kandidat kedua butuh `pg_stat_activity` (PostgreSQL hidup), melanggar requirement "bisa diverifikasi tuntas tanpa database PostgreSQL hidup". Lihat [[ADR-0062]].

Catatan percabangan: unit `ble_flaky_test_fix` (kandidat lain dari ADR-0061) dikerjakan paralel di branch `fix/ble-flaky-scan-cancel-test` (belum merge), juga bernomor ADR-0062 di branch itu. Branch sesi ini (`fix/audit-deferred-flush-precedence-test`) di-fork dari `main` yang baru sampai ADR-0061, jadi penomoran berikutnya di sini tetap ADR-0062 — perlu direnumber salah satu saat kedua branch digabung.

## Implementasi

- **Test regresi** (`audit_deferred_test.go`, baru): `fakeAuditTx` — implementasi minimal `pgx.Tx` (hanya `Exec` yang benar-benar dipakai jalur `pg_advisory_xact_lock`; `QueryRow` memanggil `t.Fatal` bila terjangkau, membuktikan jalur gagal lebih awal). `TestWithDeferredAuditsGalatFnMenangAtasGalatFlush` membuktikan galat `fn` menang; `TestWithDeferredAuditsFlushBerhasilMengembalikanHasilFn` membuktikan jalur baseline tidak berubah.
- **Guard baru:** `errUnflushedAudits` dan `Tx.checkFlushed()` (`audit.go`); `Store.InTx` (`lifecycle.go`) memanggilnya setelah `fn` berhasil. Semua pemanggil produksi (`registry.go`, `invitation.go`) sudah memakai `withDeferredAudits` yang selalu flush sendiri, jadi guard ini tidak mengubah perilaku jalur yang benar — hanya mencegah penyalahgunaan di masa depan gagal diam-diam.
- `TestInTxMenolakAuditTertahanYangTidakDiFlush`/`TestCheckFlushedLulusBilaTidakAdaYangTertahan`: unit murni atas `checkFlushed()`. `TestInTxMenegakkanGuardFlush`: integrasi dengan `freshStore` (PostgreSQL asli) membuktikan `InTx` benar-benar menyambungkan guard-nya, bukan cuma `checkFlushed()` berdiri sendiri.

## Bukti uji

`go build ./...`, `go vet ./...`, `go test ./... -race` (13 paket, PostgreSQL asli via `testpg`) lulus tanpa regresi. `python3 scripts/docs/check_docs.py .` → 0 masalah.

**Mutasi dibuktikan menangkap regresi:** `return t.checkFlushed()` di `InTx` diganti `return nil` — `TestInTxMenegakkanGuardFlush` langsung gagal (`InTx = <nil>, ingin errUnflushedAudits`), lalu dikembalikan dan suite lulus lagi.

## Berikutnya

`provisioning_concurrency_test_hardening` (tiga test backend Go `time.Sleep(300ms)`) tetap kandidat tersisa.
