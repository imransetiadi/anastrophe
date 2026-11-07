# ADR-0063: Fokus berikutnya: presedensi galat `withDeferredAudits` dan guard audit tak di-flush

- **Status:** Diterima
- **Tanggal:** 2026-11-07
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0)
- **Rujukan:** ADR-0018, ADR-0024, ADR-0051, ADR-0061

## Konteks

Satu kandidat sisa dari ADR-0061 tetap ada (`provisioning_concurrency_test_hardening`). Sesi ini mencari kandidat kedua dari `docs/agentmemory/backlog.md` bagian "Deadlock enrolment–sapuan (minor review akhir, ADR-0051)" yang belum pernah dijadikan kandidat `jev_decide`: `withDeferredAudits` (`backend/internal/store/audit.go`) punya komentar "Galat fn didahulukan" tapi tidak ada test eksplisit yang mem-pin-nya; terkait, `deferAudits()` yang dipanggil tanpa `flushAudits()` tidak dijaga — event audit tertahan bisa hilang diam-diam saat transaksi commit.

Catatan percabangan: unit `ble_flaky_test_fix` (kandidat lain dari ADR-0061) dikerjakan paralel di branch terpisah (`fix/ble-flaky-scan-cancel-test`, belum merge saat ADR ini ditulis) dengan nomor ADR-0063 di branch itu. Branch ini (`fix/audit-deferred-flush-precedence-test`) di-fork dari `main` yang baru sampai ADR-0061, sehingga penomoran berikutnya di sini tetap ADR-0063. Siapa pun yang merge kedua branch ke `main` perlu merenumber salah satunya agar tidak bentrok.

## Hasil JEV

- **Hasil:** `audit_deferred_flush_precedence_test` · confidence **0.85** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-07-fokus-berikutnya-audit-deferred-flush.output.json`](jev-log/2026-11-07-fokus-berikutnya-audit-deferred-flush.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `audit_deferred_flush_precedence_test` | 0.88 | ketiganya *supported* |
| `provisioning_concurrency_test_hardening` | 0 | req. "bisa diuji tanpa PostgreSQL hidup" *contradicted* — butuh `pg_stat_activity` |

Confidence 0,85 ≥ 0,80 (ADR-0018) → **Diterima** tanpa eskalasi.

## Keputusan

Dua bagian, keduanya kecil dan berdiri sendiri:

1. **Test regresi:** pin bahwa `withDeferredAudits` mengembalikan galat `fn`, bukan galat `flushAudits`, saat keduanya gagal — perilaku sudah benar di kode (komentar "Galat fn didahulukan"), tapi tidak ada test yang membuktikannya. Diuji dengan `fakeAuditTx` (implementasi minimal `pgx.Tx`), tanpa PostgreSQL hidup.
2. **Guard baru:** `Tx.checkFlushed()` mengembalikan `errUnflushedAudits` bila `deferAudits()` masih aktif atau ada event tertahan yang belum di-`flushAudits()`. `Store.InTx` memanggilnya setelah `fn` berhasil, sehingga transaksi yang salah pakai (lupa flush) dibatalkan dengan galat eksplisit, bukan commit diam-diam kehilangan audit. Semua pemanggil produksi saat ini (`registry.go`, `invitation.go`) memakai `withDeferredAudits`, yang selalu flush sendiri — guard ini tidak mengubah perilaku jalur yang sudah benar, hanya menjaga terhadap penyalahgunaan di masa depan.

`provisioning_concurrency_test_hardening` tetap kandidat valid untuk fokus berikutnya.

Unit berdiri sendiri dan kecil, dikerjakan langsung TDD tanpa dokumen spesifikasi/rencana terpisah, mengikuti preseden ADR-0060/0061.

## Penutupan unit

Diimplementasikan di `backend/internal/store` (`audit.go`: `errUnflushedAudits`, `Tx.checkFlushed`; `lifecycle.go`: `Store.InTx` memanggil `checkFlushed`; `audit_deferred_test.go`: `fakeAuditTx` dan lima test baru).

Bukti verifikasi langsung:
- RED: `go vet` gagal kompilasi sebelum `checkFlushed` ditambahkan (`tx.checkFlushed undefined`).
- GREEN: `go build ./...`, `go vet ./...`, `go test ./... -race` (semua 13 paket, PostgreSQL asli via `testpg`) lulus tanpa regresi.
- **Mutasi dibuktikan menangkap regresi:** `return t.checkFlushed()` diganti `return nil` di `InTx` — `TestInTxMenegakkanGuardFlush` langsung gagal (`InTx = <nil>, ingin errUnflushedAudits`), lalu dikembalikan dan suite lulus lagi.
- `python3 scripts/docs/check_docs.py .` → 0 masalah.

## Konsekuensi

- Tidak ada perubahan kontrak jaringan, UI, atau katalog error SDD §15 — `errUnflushedAudits` adalah galat internal paket `store`, tidak pernah terjadi di jalur produksi saat ini (semua pemanggil sudah benar lewat `withDeferredAudits`).
- Modul yang disentuh: `backend/internal/store` saja.
- `provisioning_concurrency_test_hardening` menyusul sebagai unit terpisah.
