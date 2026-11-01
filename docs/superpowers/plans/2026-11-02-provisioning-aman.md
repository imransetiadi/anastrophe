# Provisioning kredensial yang aman — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kredensial hanya bisa diterbitkan untuk perangkat yang memulai enrolment, dan tambah kanal ke kartu aktif ditolak.

**Architecture:** App mengirim hash rahasia enrolment; server menyimpannya di card instance (migrasi 0011) dalam transaksi enrolment dan mewajibkan rahasia itu sebagai bearer saat provisioning kredensial pertama.

**Tech Stack:** Go 1.27 + PostgreSQL 16, Swift 6 / Swift Testing.

**Spec:** [`docs/superpowers/specs/2026-11-02-provisioning-aman-design.md`](../specs/2026-11-02-provisioning-aman-design.md); ADR-0039, ADR-0040; FR-16; SDD §8.4.1, §8.5; QA TC-ENR-19 (baru).

## Global Constraints

- Rahasia 32 byte, base64url tanpa padding di header `Authorization: Bearer`; server hanya menyimpan SHA-256 (`provisioning_key_hash`).
- Kegagalan rahasia → 404 `ENR-NOT-FOUND` identik dengan id tak dikenal, diperiksa sebelum status.
- Provisioning hanya untuk `PROVISIONING`; ACTIVE → 409 `ENR-NOT-PROVISIONABLE`. Hash dihapus setelah kredensial pertama.
- Dokumen Bahasa Indonesia; `check_docs.py` 0 masalah.

## Review Focus

1. Jawaban identik: Task 1 `TestProvisioningTanpaRahasiaIdentik`.
2. Tambah kanal ditolak: Task 1 `TestTambahKanalKartuAktifDitolak`.
3. Melanjutkan dan promosi: Task 1 `TestRahasiaDigantiSaatMelanjutkan`.
4. Rahasia tidak bocor: Task 1 `TestRahasiaEnrolmentTidakBocor`.
5. Hash terhapus: Task 1 `TestHashRahasiaDihapusSetelahKredensialPertama`.

---

### Task 1: Store, migrasi 0011, dan HTTP

**Files:** Create `backend/internal/store/migrations/0011_provisioning_key.sql`, `backend/internal/enroll/provisioning_secret_test.go`; Modify `backend/internal/store/store.go` (`Enrollment.ProvisioningKeyHash`, `SetProvisioningKeyHash`, `InTx`, `SaveCredential` menghapus hash), `backend/internal/enroll/credentials.go`, fixture test.

- [ ] Test gagal: lima test Review Focus, plus `provisioning_key_hash` bukan 32 byte → 400.
- [ ] Implementasi; fixture test bertindak sebagai klien yang benar (otomatis mengirim hash dan rahasia); suite Go hijau; mutasi; commit.

### Task 2: App

**Files:** Modify `Packages/Sources/ANNetworking/APIClient.swift`, `Packages/Sources/ANStorage/StatusTokenStore.swift` (`ProvisioningSecret`), `Packages/Sources/ANFeatures/Lab/LabProvisioning.swift`; Tests.

- [ ] Test gagal: body enrolment (kartu dan undangan) memuat `provisioning_key_hash`; provisioning mengirim `Authorization: Bearer <base64url>`; provisioning lab memakai rahasia yang hash-nya dikirim saat enrolment.
- [ ] Implementasi; suite host dan simulator; commit.

### Task 3: E2E lab dan dokumen

- [ ] E2E: provisioning lab berhasil; tanpa rahasia atau dengan id dari `:challenge` → 404; tambah kanal ke kartu aktif → 409.
- [ ] SDD §8.4.1/§8.5/§15 dan catatan keamanan tracer; QA TC-ENR-19 + §14; README; commit.
