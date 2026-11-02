---
type: session
project: anastrophe
date: 2026-11-02
status: selesai
tags: [app, bantuan, faq, diagnostik, privasi]
---
# 2026-11-02 — Layar Bantuan dan FAQ

Keputusan: [ADR-0048](../decisions/ADR-0048-fokus-bantuan-faq.md) (JEV 0,99). Rencana: `docs/superpowers/plans/2026-11-02-bantuan-faq.md`.

## Perubahan

- **Pintu masuk:** tombol "Bantuan" di tab Kunci untuk semua build.
- **Cara akses di iPhone ini:** status "Tempel ke pembaca" dan "Bluetooth". Penyebab dari build atau program (mis. build tanpa emulasi) tidak menyalahkan iPhone atau wilayah pengguna.
- **FAQ sepuluh topik FR-60** (ID/EN), sesuai perilaku R1:
  - offline: kartu diperbarui saat dipakai dengan internet;
  - ganti iPhone: hapus di iPhone lama dulu;
  - anggota: perangkat tambahan perlu persetujuan;
  - layar terkunci: buka app + Face ID.
- **iPhone yang didukung (FR-02):** iPhone 11+, SE gen 2/3, iOS 26+.
- **Laporan diagnostik (FR-63)** lewat lembar bagikan:
  - tanpa id, token, nama kartu, zona, atau host layanan;
  - penyimpanan gagal atau kartu tak terbaca dilaporkan apa adanya.

## Bukti

- Host 345 test, simulator 343 test; build Debug dan Release sukses.
- Screenshot ID/EN/AX5.
- Mutasi tertangkap: host layanan bocor, pengabaian `storageFailed`.
- `jev_verify`: 5/5 klaim platform FAQ terverifikasi.

## Review akhir (opus)

Verdict "With fixes": 0 Critical, 3 Important, semuanya diperbaiki:
- jawaban offline vs perpanjangan saat tap;
- laporan menyembunyikan kegagalan penyimpanan;
- panduan ganti iPhone menjebak di persetujuan.

Minor 6 (status yang menyalahkan iPhone/wilayah) dinaikkan dan diperbaiki. Sisa minor ada di [backlog](../backlog.md).

`jev_gate` tereskalasi (composite 0,83; `safe_to_apply` 0,73; klaim universal "never contains" 0,67).

## Pelajaran

- Test isi teks yang memakai `localized()` berjalan di lokal mesin (EN). Untuk memeriksa salinan per bahasa, baca katalog langsung dan buktikan test gagal terhadap salinan lama.
