---
type: session
project: anastrophe
date: 2026-11-02
status: selesai
tags: [backend, app, kebijakan-gedung, kanal, cli]
---
# 2026-11-02 — Kebijakan gedung (FR-55 sebagian)

Keputusan: [ADR-0049](../decisions/ADR-0049-fokus-kebijakan-gedung.md) (JEV 0,63, Provisional). Rencana: `docs/superpowers/plans/2026-11-02-kebijakan-gedung.md`.

## Perubahan

- **CLI `anastrophe-registry policy`:**
  - membaca kebijakan dan mengubah masa berlaku (1–30 hari) serta kanal (`ble`, `nfcHCE`, `semua`);
  - audit `site.policy_updated`;
  - peringatan bila tidak ada kanal efektif.
- **Store:** pembaruan lewat `jsonb_set`/`-` di SQL, sehingga `zones_bitmap` 64-bit tetap utuh. Pembacaan aman untuk nilai yang ditulis lewat SQL: `null` = tanpa pembatasan, bentuk lain = tidak ada kanal.
- **Kanal efektif gedung:** kebijakan ∩ kanal layanan. Dikirim di lookup kode gedung dan respons enrolment. Provisioning menolak kanal terlarang (`ENR-INVALID-CHANNEL`), tetapi hanya sesudah rahasia enrolment diperiksa.
- **App:**
  - jalur kartu memeriksa kanal gedung sebelum enrolment (tanpa slot terbuang);
  - kanal dipilih ulang dari respons enrolment (jalur undangan);
  - pesan dibedakan antara penyebab perangkat dan bukan perangkat;
  - "Coba lagi" mencari ulang kode gedung.

## Bukti

- Go 10 paket lulus. Swift host 354 test, simulator 352 test.
- Mutasi tertangkap: pemilihan ulang kanal, "Coba lagi".
- E2e lab:
  - gedung `nfcHCE` saja + layanan `ble` → pesan tanpa card instance;
  - `semua` → kartu `ble` aktif, berlaku 3,0 hari setelah `--cert-validity-days 3`.

## Review akhir (opus)

Verdict "With fixes".
- **#1:** `policy.channels` bukan array membuat lookup/enrolment/hapus kartu gagal 500. Diperbaiki.
- **Minor 1–3:** dinaikkan dan diperbaiki: "Coba lagi", pesan netral, peringatan CLI.
- **Minor 4:** test penerbitan dari `UpdateSitePolicy` ditambahkan.
- Sisanya ada di [backlog](../backlog.md).

`jev_gate`: review (composite 0,79, `test_gap`).

## Pelajaran

- **JSON di Postgres:** JSON yang diubah lewat Go (`map[string]any`) merusak bilangan 64-bit (`float64`). Perbarui kunci JSONB di SQL.
- **Ekspresi SQL atas JSONB yang bisa diedit operator:** lindungi dengan `jsonb_typeof`. Satu nilai `null` sudah cukup menggagalkan semua endpoint yang membaca kebijakan itu.
- **Alat operator:** harus membaca dengan SQL yang sama dengan server, agar yang ditampilkan sama dengan yang ditegakkan.
