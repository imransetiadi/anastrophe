# Perbaikan minor tertunda (siklus hidup, provisioning, undangan) — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menutup minor terverifikasi dari tiga review akhir terakhir tanpa mengubah keputusan yang menunggu pengguna (ADR-0038, ADR-0041).

**Architecture:** Perbaikan lokal di store/handler Go, CLI, dan app; tiap minor dibuktikan dengan test yang gagal dulu.

**Tech Stack:** Go 1.27 + PostgreSQL 16, Swift 6 / Swift Testing.

**Spec:** temuan review akhir yang tercatat di `docs/agentmemory/backlog.md` dan Memory.md (siklus hidup M1, M3, M4, M5b, M6, M8; provisioning M1, M2, M4, M5, M6; undangan M4, M6, M7, M9). Fokus dari ADR-0042.

## Global Constraints

- Tidak mengubah semantik ADR-0038 (pendaftaran ulang setelah suspend/revoke) maupun ADR-0041 (penggantian hash saat melanjutkan).
- Rahasia dan identitas mentah tidak pernah disimpan atau di-log (aturan 6, 9). Dokumen Bahasa Indonesia; `check_docs.py` 0 masalah (kode keluarnya yang menahan commit).

## Review Focus

1. Update yang dijaga status tidak pernah menghidupkan instance yang sudah berubah status (`ABANDONED`, `ACTIVE`).
2. Urutan kunci perpanjangan sama dengan transisi operator dan hapus kartu (instance → kredensial).
3. Denylist tidak kedaluwarsa sebelum sertifikat terpanjang yang pernah diterbitkan.
4. Penyegar status tidak menimpa perubahan lain dan tidak bergantung jam dinding.
5. Pemanggil API tidak bisa lupa rahasia enrolment tanpa galat kompilasi.

---

### Task 1: Store dan handler

- [ ] Test gagal lalu perbaikan: `SetProvisioningKeyHash` hanya untuk `PROVISIONING`/`PENDING_APPROVAL` (selain itu `ErrDuplicateEnrollment`); galat `ErrInvalidProvisioningHash` sendiri; resume yang dijaga status (`AND status = 'PROVISIONING'`, coba ulang sekali dalam transaksi yang sama bila instance berubah) di jalur kartu dan undangan; revoke operator menulis `credential.revoked` per kredensial; perpanjangan mengunci instance sebelum kredensial.

### Task 2: Denylist

- [ ] Migrasi 0012 `credentials.max_not_after`; penerbitan dan perpanjangan menyimpan maksimum; denylist memakai maksimum itu; `PurgeDenylist` dipanggil sapuan per jam API.

### Task 3: Test idempotency dan alur persetujuan

- [ ] Provisioning: key sama dengan rahasia lain atau tanpa rahasia → 422; enrolment: key sama dengan hash lain → 422 dan hash tersimpan tetap; alur persetujuan operator lewat HTTP; undangan: key sama dengan token lain → 422; fixture `secrets` dengan mutex.

### Task 4: CLI

- [ ] `--link-base` wajib https dan diakhiri `/`; `invite` mencetak id undangan.

### Task 5: App

- [ ] Parameter rahasia enrolment wajib di `APIClient`; `CardStore.update(id:mutate:)` dipakai penyegar status; penyegar melewati kartu Dicabut dan memakai jam monotonik; perpanjangan menyimpan `serverCardID` dari challenge bila record belum punya.
