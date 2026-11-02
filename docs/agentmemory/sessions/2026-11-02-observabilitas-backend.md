---
type: session
project: anastrophe
date: 2026-11-02
status: selesai
tags: [backend, observabilitas, nfr-o01, privasi]
---
# 2026-11-02 — Observabilitas backend: log akses dan metrik (NFR-O01 sebagian)

Keputusan: [ADR-0054](../decisions/ADR-0054-fokus-observabilitas-backend.md) (JEV 0,99). Rencana: `docs/superpowers/plans/2026-11-02-observabilitas-backend.md`.

## Perubahan

- **Log akses per permintaan:** request id (juga di header `X-Request-ID`), pola rute, status, durasi, dan ukuran. Tidak mencatat path, query, body, header, maupun IP.
- **Korelasi galat:** log galat handler dan log panic membawa `request_id` yang sama.
- **Metrik teks Prometheus:** hanya di listener internal, dengan histogram yang memuat bucket 0,3 dtk untuk NFR-P05.
- **Format log:** JSON lewat `ANASTROPHE_LOG_FORMAT=json`.

## Bukti

- Mutasi 19/19 tertangkap; Go 11 paket lulus dengan `-race`; uji asap biner nyata lulus.
- Review akhir menemukan kunci metrik yang dipegang selama menulis ke jaringan, sehingga scraper macet bisa membekukan API. Kini metrik dirender sebelum ditulis, listener metrik punya timeout, dan shutdown mendahulukan server publik.
- Temuan di luar unit: PEM root Apple dari ADR-0052 diabaikan `*.pem`. Kini ter-commit dan diverifikasi dengan clone baru.

`jev_gate`: eskalasi, dicatat tanpa diajukan ulang. Minor ada di [backlog](../backlog.md).

## Pelajaran

- [Verifikasi uji dan gerbang commit](../lessons/verifikasi-uji-dan-gerbang.md): `git add <direktori>` diam-diam melewati berkas yang cocok dengan `.gitignore`. Berkas yang di-embed (`go:embed`) atau dirujuk build harus diperiksa dengan `git ls-files`, atau dengan build dari clone baru.
- **Jangan memegang kunci selama I/O jaringan.** Render dulu di bawah kunci, lalu tulis sesudah kunci dilepas.
