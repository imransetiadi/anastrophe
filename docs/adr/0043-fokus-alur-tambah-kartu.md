# ADR-0043: Fokus berikutnya: alur Tambah Kartu produksi

- **Status:** Diterima (JEV 0,98)
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-05, FR-10, FR-11, FR-12, FR-13, US-01, US-02, ADR-0018, ADR-0042

## Konteks

Rencana perbaikan minor (ADR-0042) selesai di `48e08a6`. Pemeriksaan kode menemukan celah P0 yang lebih besar dari perkiraan ADR-0042:

- **Belum ada alur Tambah Kartu di build Release.** Tombol `keys.add` hanya ada di dalam `#if DEBUG` dan membuka layar Lab. Pengguna nyata belum bisa menambah kartu.
- **Bagian app lain yang belum ada:** handler `onOpenURL` untuk tautan undangan dan implementasi live `CardOwnershipReader`.
- **Akibatnya,** FR-05, FR-10, FR-11, FR-12, dan FR-13 (semuanya P0) di sisi app belum bisa dipakai, dan US-01/US-02 belum terpenuhi.

ADR-0042 menganggap alur ini terblokir akun, App Attest, dan iPhone fisik. Bukti baru menunjukkan sebaliknya:

- **Akun:** enrolment server tidak memerlukan akun (ADR-0032, ADR-0034, ADR-0040).
- **App Attest:** belum ditegakkan server. NFR-S03 tetap terbuka dan menyusul sebagai unit sendiri.
- **Simulator:** jalur undangan, pesan alasan, pemilihan kanal, dan e2e bisa diuji di simulator dengan PostgreSQL lokal.
- **iPhone fisik:** hanya pembacaan kartu fisik live yang memerlukannya (uji H).

## Hasil JEV

- **Hasil:** `alur_tambah_kartu` · confidence **0.98** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round28.input.json`](jev-log/2026-11-02-round28.input.json), [`jev-log/2026-11-02-round28.output.json`](jev-log/2026-11-02-round28.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `alur_tambah_kartu` | 0.98 | ketiganya *supported* |
| `bantuan_faq` | 0.01 | tidak membuat P0 yang belum bisa dipakai menjadi bisa dipakai |
| `kebijakan_gedung` | 0 | dampak P0 tidak diketahui |
| `anggota_security_code` | 0 | terblokir FR-03/FR-62 dan butuh keputusan keamanan baru |
| `sisa_minor` | 0 | tidak membuka kemampuan pengguna |
| `akses_cepat` | 0 | semua requirement tidak diketahui |

## Keputusan

Unit berikutnya adalah alur Tambah Kartu produksi di app:

- menu "Tambah Kartu Akses" di build Release;
- jalur undangan;
- jalur kartu fisik dengan pembaca live (uji H) dan mock di test;
- kanal dipilih otomatis;
- pesan alasan FR-13 dengan tawaran jalur undangan.

Desainnya ada di `docs/superpowers/specs/2026-11-02-alur-tambah-kartu-design.md`.

## Konsekuensi

- Build Release mendapat alur enrolment pertama. Inti `LabProvisioning` dipindah ke kode produksi, dan layar Lab tetap DEBUG saja.
- Di luar unit ini: App Attest (NFR-S03), security code dan anggota (FR-14, FR-32–FR-36), akun (FR-03), dan perlindungan klaim (FR-18). Semuanya tetap terbuka.
- ADR-0038 dan ADR-0041 tetap menunggu pengguna. Alur baru memakai perilaku server yang ada tanpa mengubahnya.
