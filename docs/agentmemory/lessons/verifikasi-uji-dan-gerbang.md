---
type: lesson
project: anastrophe
date: 2026-11-02
tags: [proses, tdd, mutasi, dokumen]
---
# Verifikasi uji dan gerbang commit

- **Mutasi yang membuat build gagal bukan bukti.** Contohnya mutasi yang membuang satu-satunya pemakaian sebuah import. Ulangi dengan bentuk yang tetap terkompilasi, misalnya `bytes.Equal(x, x)` atau `elliptic.P256() == nil`, lalu pastikan ada `--- FAIL` dari test yang tepat.
- **Test baru dijalankan dulu pada kode yang benar, baru uji mutasi.** Test yang gagal pada kode benar membuat semua mutasi tampak "tertangkap" ([deadlock enrolment–sapuan](../sessions/2026-11-02-deadlock-enrolment-sapuan.md)).
- **Commit dijaga dengan exit code `check_docs`, bukan keluaran yang di-pipe.** Pada `python3 scripts/docs/check_docs.py . | tail -1 && git commit`, status pipeline berasal dari `tail`, sehingga commit lolos dengan 1 masalah ([verifier App Attest](../sessions/2026-11-02-verifier-app-attest.md)). Simpan keluaran ke berkas, lalu periksa `$?`.
- **`git add <direktori>` diam-diam melewati berkas yang cocok dengan `.gitignore`.** PEM root Apple yang di-embed verifier App Attest tidak ter-commit karena aturan `*.pem`, sehingga clone baru gagal build ([observabilitas backend](../sessions/2026-11-02-observabilitas-backend.md)). Untuk berkas yang dibutuhkan build, periksa `git ls-files` dan build dari clone baru sebelum menutup unit.
- **Pemindai secret ikut menggerbangi commit.** Sejak ADR-0056 setiap commit dijaga oleh dua perintah yang sama-sama harus exit 0: `check_docs` dan `python3 scripts/security/scan.py secrets` atas perubahan yang di-stage. Grep buatan sendiri dengan `-i` sebelumnya penuh positif palsu, dan tidak menghentikan commit karena hasilnya tidak dipakai sebagai syarat ([uji beban API](../sessions/2026-11-02-uji-beban-api.md)).
- **Exit code alat bukan bukti hasil.** gitleaks 8.30 tetap exit 0 dengan laporan `[]` saat git gagal (repo ditolak, objek hilang, bukan repo). Hasil hanya dipercaya bila prasyaratnya diperiksa (repo terbaca, bukan clone dangkal), stderr kosong, dan isi laporan konsisten dengan exit code ([pemindaian secret dan dependensi](../sessions/2026-11-02-pemindaian-secret-dependensi.md)).
