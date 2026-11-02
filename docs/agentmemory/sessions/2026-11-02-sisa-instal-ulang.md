---
type: session
project: anastrophe
date: 2026-11-02
status: selesai
tags: [app, keychain, fr-43, privasi]
---
# 2026-11-02 — Pembersihan sisa Keychain saat instal ulang (FR-43 sebagian)

Keputusan: [ADR-0053](../decisions/ADR-0053-fokus-sisa-keychain-instal-ulang.md). JEV memberi 0,39 (eskalasi); unit ini diterapkan karena berisiko rendah. Rencana: `docs/superpowers/plans/2026-11-02-sisa-instal-ulang.md`.

## Perubahan

- `SecretStore.deleteAll()` menghapus semua item service app dengan satu query kelas + service, tanpa account.
- Pembersihan berjalan bila penanda instalasi tidak ada dan tidak ada kartu lokal. Penanda baru dibuat hanya sesudah penghapusan berhasil.
- `AppServices.prepareInstall()` dijalankan di `makeServices()` sebelum UI menerima layanan. Store kartu yang gagal dibaca dianggap berisi kartu.

## Bukti

- Host 364 dan simulator 362 test lulus; build Debug sukses.
- Mutasi 11/11 bermakna tertangkap.
- Review akhir tidak menemukan jalur yang menghapus kunci kartu yang masih ada.
  - `FakeKeychain` kini memeriksa kelas item, karena regresi kelas sebelumnya lolos.
  - Klaim platform kini merujuk E42/E43 dan diverifikasi `jev_verify` 5/5.

`jev_gate`: eskalasi, dicatat tanpa diajukan ulang. Sisa minor ada di [backlog](../backlog.md).

## Pelajaran

- **Test double harus meniru kunci pencocokan yang sebenarnya** (kelas, service, account). Fake yang hanya mengunci per account membuat regresi query yang paling berbahaya lolos.
- **Mutasi dengan literal yang kebetulan sama dengan data test adalah mutasi ekuivalen.** Pilih nilai pengganti yang bermakna, misalnya nama service produksi atau menghapus atributnya.
