---
type: session
project: anastrophe
date: 2026-11-01
status: selesai
tags: [backend, registri, enrolment, fr-11, fr-13, fr-52]
---
# 2026-11-01 — Registri kartu fisik dan enrolment berbasis kartu

Keputusan: [ADR-0031](../decisions/ADR-0031-fokus-registri-enrolment-server.md) (fokus) dan [ADR-0032](../decisions/ADR-0032-perangkat-tambahan-menunggu-persetujuan.md) (perangkat tambahan, provisional). Spesifikasi: `docs/superpowers/specs/2026-11-01-registri-kartu-design.md`. Rencana: `docs/superpowers/plans/2026-11-01-registri-kartu.md`.

## Perubahan

- **`internal/registry`:** identitas kartu kanonik per teknologi (`iso14443a` 4/7/10 B, `iso15693` 8 B, `felica` 8 B, `iso7816` 1–32 B), normalisasi kontak (email dan E.164), serta MAC per gedung. Kunci dev diturunkan dengan HKDF-SHA256; produksi akan memakai KMS. Vektor uji dihitung independen dengan Python.
- **Store:** migrasi 0007 menambah `physical_cards` (hanya HMAC), `card_instances.physical_card_id`, dan status `REJECTED`.
  - `UpsertPhysicalCards`, `StartCardEnrollment`, `DecideEnrollment`, `SiteZoneNames`.
  - Kunci diambil berurutan: perangkat, lalu baris kartu.
  - Zona diambil dari kartu terdaftar, *fail-closed* bila 0.
- **HTTP:** `POST /v1/enrollments` mewajibkan `card`.
  - Galat `ENR-NOT-REGISTERED`, `ENR-SITE-UNSUPPORTED`, `ENR-DUPLICATE`; provisioning `PENDING_APPROVAL` → `ENR-PENDING-APPROVAL`.
  - Hash idempotency memakai HMAC kartu.
  - API menolak start tanpa `ANASTROPHE_DEV_REGISTRY_KEY`.
- **CLI `anastrophe-registry`:** `import` CSV (identitas dan kontak langsung di-HMAC; baris ditolak tanpa mencetak nilai sel) serta `approve`/`reject`. devseed mendaftarkan kartu lab.
- **App:** `CardIdentity` (deskripsi disamarkan) menggantikan placeholder `CardFingerprint` yang bertentangan dengan SDD. `createEnrollment(card:)` mengembalikan `EnrollmentStart`, ditambah teks alasan FR-13 dalam ID/EN dan argumen lab `-ANLabCard`.

## Bukti

- Go: `ANASTROPHE_REQUIRE_PG=1 go test ./...` 10 paket lulus, `go vet` bersih.
- Swift: host 252 test, simulator 250 test (masing-masing 1 dilewati).
- Uji mutasi tertangkap untuk:
  - tanpa kunci baris kartu: 19 dari 20 kartu bertabrakan, setelah test diperkuat;
  - hash idempotency dari identitas mentah;
  - alasan penolakan CLI yang mencetak identitas;
  - tanpa penjaga `PENDING_APPROVAL` di alur lab.
- Lab simulator end-to-end, dengan PostgreSQL sementara dan API lokal:
  - perangkat 1 → `ACTIVE` dengan kredensial;
  - perangkat 2 → `PENDING_APPROVAL` tanpa kredensial, dan app menampilkan "Waiting for approval from the building manager.";
  - `anastrophe-registry approve` → `PROVISIONING`;
  - log API tanpa identitas kartu.

## Review akhir dan perbaikan

Hasil review: siap merge setelah perbaikan. Semua perbaikan berikut dikerjakan dengan test RED lalu GREEN atau uji mutasi:
- **C1:** perpanjangan memakai zona kebijakan gedung, bukan zona kartu (*fail-open* untuk bitmap 0). Kini satu helper `applyZones` dipakai bersama.
- **I1:** perangkat yang sama buntu dengan `ENR-DUPLICATE` untuk instance-nya sendiri. [ADR-0034](../decisions/ADR-0034-lanjutkan-enrolment-belum-selesai.md): enrolment dilanjutkan, dan `ABANDONED` setelah 15 menit.
- **I2:** test kebocoran menggantung 10 menit. Kini baris dikumpulkan sebelum assert.
- **I3:** CSV ber-BOM ditolak dan kutip rusak menelan baris. Kini BOM diterima dan impor dibatalkan dengan baris awalnya.
- **Minor:** perangkat penuh tanpa oracle, pemindaian seluruh tabel, normalisasi ID gedung, urutan impor tanpa deadlock, hex tanpa tanda, pegangan operator, CSV di-ignore, devseed `-new-device`, drift dokumen. Mock `CardIdentityReading` ditunda ke alur Tambah kartu.

Lab ulang: perangkat 2 disetujui operator, lalu melanjutkan instance yang sama sampai `ACTIVE` dengan kredensial.

`jev_gate` tereskalasi (composite 0,55); klaim 1 terlalu luas karena perangkat penuh sengaja menerima `ENR-LIMIT`. Berikutnya: [ADR-0033](../decisions/ADR-0033-fokus-enrolment-undangan.md), enrolment via undangan.
