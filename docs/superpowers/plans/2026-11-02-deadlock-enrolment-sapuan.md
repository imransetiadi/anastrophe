# Deadlock Enrolment–Sapuan — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrolment tidak pernah memegang kunci rantai audit sambil menunggu baris instance, dan semua penulisan audit multi-rantai mengikuti urutan rantai yang sama.

**Architecture:** `Tx` bisa menahan event audit (`deferAudits`). `EnrollCard` dan `EnrollInvitation` menahan event lalu menuliskannya di akhir, berurutan stabil per rantai; sapuan per jam memakai cara yang sama.

**Tech Stack:** Go 1.27, PostgreSQL 16 (pgx v5, testpg).

**Spec:** `docs/superpowers/specs/2026-11-02-deadlock-enrolment-sapuan-design.md` (ADR-0051).

## Global Constraints

- **Isi audit tetap:** isi, hash, aktor, dan subjek tidak berubah.
- **Rollback:** event yang ditahan dibuang bersama rollback.
- **Commit:** pesan berbahasa Indonesia dan diakhiri `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Tanpa push.
- **Verifikasi:** `env ANASTROPHE_REQUIRE_PG=1 go -C backend test ./...` dan `check_docs` exit 0.

## Review Focus

1. **Kunci rantai bebas saat enrolment kartu menunggu baris.** Test: `TestEnrolmentKartuTidakMemegangKunciAuditSaatMenunggu`.
2. **Sama untuk enrolment undangan.** Test: `TestEnrolmentUndanganTidakMemegangKunciAuditSaatMenunggu`.
3. **Event ditulis tepat sekali, termasuk dari percobaan pertama.** Test: dua test di atas memeriksa audit `enrollment.abandoned` sesudah selesai; test pengulangan resume yang sudah ada tetap lulus.
4. **Urutan rantai.** Test: `TestAuditTertundaDiurutkanPerRantai`.

---

### Task 1: Audit ditunda dan berurutan

**Files:** `backend/internal/store/audit.go`, `store.go` (struct `Tx`), `registry.go`, `invitation.go`; test `backend/internal/store/deadlock_test.go`

- [ ] **Step 1: Tulis test yang gagal** (tiga test di atas).
  - Koneksi lain menahan baris instance dengan `SELECT … FOR UPDATE`.
  - Polling `pg_stat_activity` sampai enrolment menunggu kunci.
  - `pg_try_advisory_lock(auditLockNamespace, hashtext(rantai))` harus true.
- [ ] **Step 2: Jalankan.** Expected: FAIL; kunci rantai dipegang enrolment.
- [ ] **Step 3: Implementasikan:**
  - `Tx.deferAudits`, `Tx.pendingAudits`, dan `Tx.flushAudits(ctx)` (urut stabil per `AuditChain`);
  - `AppendAudit` menahan event bila sedang ditunda;
  - `EnrollCard`/`EnrollInvitation` menunda lalu flush;
  - `AbandonStaleEnrollments` menunda lalu flush.
- [ ] **Step 4: Jalankan seluruh Go.** Expected: PASS.
- [ ] **Step 5: Commit** `fix(store): enrolment tidak memegang kunci audit saat menunggu baris (deadlock 40P01, ADR-0051)`.

### Task 2: Dokumen

- [ ] **Step 1: Perbarui dokumen:** SDD (catatan urutan kunci di §8.1/§8.4.1, revisi), backlog (item deadlock dipindah ke "Sudah selesai"), QA catatan keandalan.
- [ ] **Step 2:** `check_docs` exit 0, lalu commit `docs: deadlock enrolment–sapuan (ADR-0051)`.
