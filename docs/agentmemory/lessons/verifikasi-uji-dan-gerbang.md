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
