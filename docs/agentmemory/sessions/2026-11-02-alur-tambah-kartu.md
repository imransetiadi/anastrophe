---
type: session
project: anastrophe
date: 2026-11-02
status: selesai
tags: [app, backend, enrolment, tambah-kartu, keamanan]
---
# 2026-11-02 — Alur Tambah Kartu produksi

Keputusan:
- [ADR-0043](../decisions/ADR-0043-fokus-alur-tambah-kartu.md): fokus, JEV 0,98.
- [ADR-0044](../decisions/ADR-0044-kode-gedung-untuk-enrolment-kartu.md): kode gedung, 0,96.
- [ADR-0045](../decisions/ADR-0045-perangkat-dibuat-saat-enrolment.md): perangkat dibuat saat enrolment, 0,77 Provisional.

Rencana: `docs/superpowers/plans/2026-11-02-alur-tambah-kartu.md`.

## Mengapa

Build Release belum punya cara menambah kartu: tombolnya hanya di DEBUG dan membuka Lab. FR-05 dan FR-10–FR-13 (P0) belum bisa dipakai penghuni pilot.

## Perubahan

- **Backend:**
  - `sites.join_code` + `GET /v1/sites/lookup` (404 `SITE-NOT-FOUND` identik, `no-store`) + CLI `site-code`; devseed mencetak `join_code`.
  - Baris perangkat dibuat di transaksi enrolment (`ON CONFLICT DO NOTHING`).
  - Batas 4 permintaan menunggu per kartu (`ENR-PENDING-LIMIT`, ADR-0047).
- **App:**
  - `SiteJoinCode`, `lookupSite`, dan `KeychainDeviceIdentityStore` (penanda instalasi dikecualikan dari backup).
  - `BackendConfiguration`: Info.plist `ANAPIBaseURL`, https.
  - `CardProvisioner` produksi dengan kanal otomatis N-HCE > B.
  - Pembaca Core NFC yang hanya membaca identifier, setelah `connect` berhasil.
  - `AddCardModel`/`AddCardView` dan tombol "Tambah kartu akses" di semua build.
  - `onOpenURL` yang hanya mengisi field undangan.
- **E2e:** argumen lab `-ANAPIBaseURL`, `-ANLabCardReader`, `-ANLabAddCode`, `-ANLabOpenURL`.

## Bukti

- Go 10 paket lulus. Swift host 334 test, simulator 332 test.
- Build Debug dan Release sukses.
- Mutasi tertangkap: aturan Bluetooth, guard ketuk ganda (setelah test diperkuat dengan `GatedReader`), dan batas pending.
- E2e simulator dengan PostgreSQL sementara dan API `127.0.0.1:8099`:
  - instal baru + kode gedung → kartu aktif, perangkat 1→2;
  - instal ulang + kartu tak terdaftar → pesan + tawaran undangan, perangkat tetap 2;
  - undangan → kartu aktif, perangkat 3;
  - teks ID dan "Layanan belum tersedia" tampil benar.

## Review akhir (opus)

Verdict "With fixes": 0 Critical, 3 Important, 8 Minor.

- **Diperbaiki:**
  - #2 banjir pending: batas 4 per kartu (ADR-0047, tereskalasi; inti bersama 0,98).
  - #3 identifier setelah `connect`.
  - #7 gedung tanpa registri ditawari undangan.
- **#1, oracle tebakan identitas kartu:** dicatat sebagai **gerbang pra-pilot** (ADR-0046, tereskalasi 0,49). Wajib App Attest + pembatas/deteksi kegagalan enrolment sebelum backend dibuka untuk pilot.
- **Minor:** ada di [backlog](../backlog.md).

## Pelajaran

- **SwiftUI:** konten `sheet(item:)` bisa membaca `@State` lama yang diset tepat sebelum sheet dibuka. Data yang dibutuhkan sheet harus ikut di dalam item.
- **Test ketuk ganda:** pembaca palsu yang langsung kembali tidak pernah memicu interleaving, sehingga mutasi tanpa guard lolos. Test perlu pembaca yang benar-benar menahan pembacaan.
- **Folder Xcode tersinkron:** `Info.plist` di folder itu butuh `PBXFileSystemSynchronizedBuildFileExceptionSet`; tanpanya muncul "Multiple commands produce Info.plist".
