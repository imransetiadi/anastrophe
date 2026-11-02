# Filter Daftar Kartu (FR-50) — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `anastrophe-registry list` memfilter berdasarkan kanal dan awalan id card instance.

**Architecture:** filter disatukan di `CardInstanceFilter` pada store; `ListCardInstances` lama mendelegasikan ke sana.

**Tech Stack:** Go 1.27, PostgreSQL 16 (pgx v5, testpg).

**Spec:** `docs/superpowers/specs/2026-11-02-filter-daftar-kartu-design.md` (ADR-0050).

## Global Constraints

- **Kanal:** `ble` atau `nfcHCE`.
- **Awalan id:** `^[0-9a-f-]{1,36}$` setelah huruf kecil.
- **Tampilan:** tanpa identitas kartu atau kontak.
- **Commit:** pesan berbahasa Indonesia dan diakhiri `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Tanpa push.
- **Verifikasi:** `env ANASTROPHE_REQUIRE_PG=1 go -C backend test ./...` dan `check_docs` exit 0.

## Review Focus

1. **Tanpa injeksi pola `LIKE`.** Test: Task 1 `TestFilterDaftarMenolakPolaLike`.
2. **Filter digabung AND.** Test: Task 1 `TestFilterDaftarKanalDanAwalan`.
3. **Kanal dari kredensial `ACTIVE`/`SUSPENDED` saja.** Test: Task 1 `TestFilterKanalAbaikanKredensialDicabut`.

---

### Task 1: Store + CLI

**Files:** `backend/internal/store/lifecycle.go`, `backend/internal/store/lifecycle_test.go`, `backend/cmd/anastrophe-registry/main.go`, `backend/cmd/anastrophe-registry/main_test.go`

**Interfaces:**
- Produces:
  - `type CardInstanceFilter struct { Status, Channel, IDPrefix string }`;
  - `(*Store) ListCardInstancesFiltered(ctx, siteID string, f CardInstanceFilter) ([]CardInstanceSummary, error)`;
  - galat `ErrInvalidFilter`.

- [ ] **Step 1: Tulis test yang gagal:**
  - store: `TestFilterDaftarKanalDanAwalan`, `TestFilterDaftarMenolakPolaLike`, `TestFilterKanalAbaikanKredensialDicabut`;
  - CLI: `TestListFilterKanalDanId`, `TestListFilterTidakValid`.
- [ ] **Step 2: Jalankan.** Expected: FAIL.
- [ ] **Step 3: Implementasikan.**
- [ ] **Step 4: Jalankan seluruh Go.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(registry): filter kanal dan pencarian awalan id di list (FR-50)`.

### Task 2: Dokumen

- [ ] **Step 1: Perbarui dokumen:** README (`list`), QA hasil TC-ADM-15, SDD revisi; `check_docs` exit 0.
- [ ] **Step 2: Commit** `docs: filter daftar kartu (FR-50)`.
