# ADR-0056: Fokus berikutnya: pemindaian secret dan dependensi (TC-SEC-11)

- **Status:** Diterima (JEV 0,93)
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** NFR-S09, TC-SEC-11, CLAUDE.md aturan 9, ADR-0018, ADR-0055

## Konteks

TC-SEC-11 (P0) menuntut tidak ada secret di repo maupun build dan tidak ada CVE kritis yang terbuka. Uji ini belum pernah dijalankan. Aturan 9 CLAUDE.md (secret tidak pernah masuk repo) selama ini hanya dijaga dengan disiplin, tanpa pemeriksaan otomatis.

Eksplorasi awal dengan gitleaks 8.30.1 (mode redaksi) atas 165 commit menemukan 10 temuan aturan `generic-api-key`, semuanya positif palsu: anotasi tipe `P256.Signing.PrivateKey` di kode Swift dan heksadesimal vektor uji ANP/1 yang deterministik. App iOS tidak punya paket SPM pihak ketiga. Backend memakai pgx v5.7.5 dan modul `golang.org/x`. Alat uji Python memakai `cryptography`.

## Hasil JEV

- **Hasil:** `pemindaian_secret_dependensi` · confidence **0.93** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round41.input.json`](jev-log/2026-11-02-round41.input.json), [`jev-log/2026-11-02-round41.output.json`](jev-log/2026-11-02-round41.output.json). Panggilan pertama gagal di sisi provider dan diulang sekali dengan masukan yang sama.

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `pemindaian_secret_dependensi` | 0.94 | ketiganya *supported* |
| `audit_aksesibilitas` | 0.04 | ketiganya *supported* |
| `minor_observabilitas` | 0.01 | P0 belum terverifikasi: *contradicted* (TC-OPS-01 sudah lulus) |
| `privacy_manifest_teknis` | 0 | tanpa keputusan privasi/legal baru dan P0: *contradicted* |

## Keputusan

- **Pemindaian secret** dengan gitleaks memakai konfigurasi repo `.gitleaks.toml` yang memperluas aturan bawaan.
  - Cakupan: seluruh riwayat git, perubahan yang di-stage, dan produk build app.
  - Allowlist harus sempit dan beralasan: per nilai atau per path, tidak pernah per aturan.
- **Pemindaian dependensi:** govulncheck (versi terpin) untuk modul backend, pemeriksaan bahwa app tetap tanpa paket pihak ketiga, dan pemeriksaan advisori untuk dependensi alat Python.
- **Pembungkus** `scripts/security/` dengan test, exit code yang jelas, dan keluaran yang tidak pernah mencetak nilai secret.
- **Hasil** dicatat di QA §11.1. Secret nyata yang ditemukan di riwayat tidak ditangani sendiri: rotasi atau penulisan ulang riwayat dieskalasi ke pengguna.

Desain dan rencananya ada di `docs/superpowers/specs/2026-11-02-pemindaian-secret-dependensi-design.md` dan `docs/superpowers/plans/2026-11-02-pemindaian-secret-dependensi.md`.

## Konsekuensi

- Aturan 9 kini bisa diperiksa ulang kapan saja dengan satu perintah, dan siap dijadikan langkah CI begitu CI tersedia.
- TC-SEC-06 (MASVS), TC-SEC-07 (audit `.ipa`), dan TC-SEC-12 (pentest eksternal) tetap terbuka.

## Catatan sesudah review akhir

- **Versi Go:** run nyata pertama menemukan kerentanan yang terpanggil di pgx v5.7.5, `golang.org/x/text` v0.24.0, dan stdlib go1.27.1.
  - pgx dinaikkan ke v5.9.2 dan x/text ke v0.41.0. Keduanya menuntut direktif `go 1.25.0`.
  - `toolchain go1.27.3` menutup 10 kerentanan stdlib. Direktif ini hanya berlaku dengan `GOTOOLCHAIN=auto` (bawaan). Dengan `GOTOOLCHAIN=local`, Go lokal harus ≥ 1.27.3, karena hasil govulncheck untuk stdlib mengikuti Go yang benar-benar dipakai.
- **Pemindai diperketat:**
  - git yang gagal atau menolak repo, clone dangkal, dan `.gitleaksignore` memberi exit 2 (gitleaks 8.30 sendiri tetap exit 0 dengan laporan kosong saat git gagal);
  - komentar `gitleaks:allow` diabaikan;
  - produk build dipindai langsung (aturan berbasis path seperti `.p12`) dan lewat string cetak (biner);
  - halaman OSV yang hanya berisi `next_page_token` diikuti.
- **Batas yang diketahui:** gitleaks tidak membaca blob biner di riwayat git, isi yang hanya ada di commit merge, maupun pesan commit. Saat ini riwayat tidak memuat berkas biner dan tidak ada commit merge.
