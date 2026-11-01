# Hapus Kartu (FR-31) — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pengguna menghapus kartu dari detail kartu; server mencabut card instance dan kredensialnya dengan bukti kepemilikan kunci (ADR-0026), lalu app menghapus data lokal.

**Architecture:** Endpoint `DELETE /v1/cards/{id}` di paket `enroll` memakai ulang nonce `:challenge` dan helper transaksi; app menambah `APIClient.deleteCard`, `CardRemover`, autentikator di `AppServices`, dan bagian Pengaturan di `CardDetailView`.

**Tech Stack:** Go + PostgreSQL 16, Swift 6.

**Spec:** [`docs/superpowers/specs/2026-11-01-hapus-kartu-design.md`](../specs/2026-11-01-hapus-kartu-design.md); ADR-0026; FR-31; TC-MGT-02.

## Global Constraints

- Pesan tanda tangan: `"ANP1-REVOKE"` ‖ `cred_id` (16 B) ‖ `nonce` (32 B) ‖ UTF-8 `card_instance_id` huruf kecil.
- Kode error: `CARD-NOT-FOUND` 404, `CARD-NOT-REMOVABLE` 409, `CRED-PROOF-INVALID` 400, `CRED-CHALLENGE-INVALID` 400, `REQ-IDEMPOTENCY-KEY` 400.
- Jalur gagal tidak menulis apa pun; audit dalam transaksi yang sama.

## Review Focus

1. **Bukti kredensial kartu lain.** Kredensial A dipakai untuk menghapus kartu B → 400. Test: Task 1, `TestHapusDenganKredensialKartuLainDitolak`.
2. **Slot tidak terbebas.** Setelah dihapus, perangkat dapat mendaftar kartu ke-8 lagi. Test: Task 1, `TestHapusKartuMembebaskanSlot`.
3. **Kartu hilang saat offline.** Server tak terjangkau → kunci, record, dan kartu lokal tetap ada. Test: Task 2, `offlineKartuTetapAda`.

---

### Task 1: Backend `DELETE /v1/cards/{id}`

- [ ] Test gagal:
  - `TestHapusKartuMencabutDanMencatatAudit`: 204, card instance dan kredensial REVOKED, audit `credential.revoked`.
  - `TestHapusKartuMembebaskanSlot`.
  - `TestHapusDenganKredensialKartuLainDitolak`.
  - `TestHapusTandaTanganSalahDitolak`.
  - `TestHapusKartuDuaKali409`.
  - `TestHapusTanpaIdempotencyKeyDitolak`.
  - `TestChallengeTetapBisaSaatKanalDimatikan` (renew tetap 409).
- [ ] Implementasikan; `ANASTROPHE_REQUIRE_PG=1 go test ./...` → LULUS.

### Task 2: App — API, remover, UI, lab

- [ ] Test gagal:
  - `deleteCardMengirimBuktiKepemilikan` (APIClient: path, method DELETE, header, body).
  - `hapusMencabutLaluMenghapusLokal`: tanda tangan diverifikasi atas pesan persis; kunci, record, dan kartu terhapus.
  - `offlineKartuTetapAda`.
  - `sudahDicabutDiServerTetapDihapusLokal` (409).
  - `tanpaBackendHapusLokalSaja`.
  - `provisionViaBackendMenyimpanServerCardID`.
- [ ] Implementasikan, termasuk UI Pengaturan → Hapus (konfirmasi + autentikasi) dan pemicu DEBUG `-ANLabDelete`. Perbarui SDD §8.5/§15 dan QA TC-MGT-02. `swift test` + simulator → LULUS.
- [ ] E2e simulator: provisioning via backend → `-ANLabDelete` → DB menunjukkan card instance dan kredensial REVOKED, daftar app kosong.
