---
type: session
project: anastrophe
date: 2026-11-02
status: selesai
tags: [backend, keamanan, app-attest, nfr-s03]
---
# 2026-11-02 — Verifier App Attest di backend (NFR-S03, langkah pertama)

Keputusan: [ADR-0052](../decisions/ADR-0052-fokus-verifier-app-attest.md) (JEV 0,60, Provisional). Rencana: `docs/superpowers/plans/2026-11-02-verifier-app-attest.md`.

## Riset

- **Sumber dan data uji:** dokumentasi Apple dibaca lewat JSON dokumentasinya, dan root CA diambil dari apple.com. Contoh attestation resmi Apple dipakai sebagai data uji.
- **Inkonsistensi di contoh Apple:** contoh resmi tidak cocok dengan teksnya sendiri dalam tiga hal (O-AA05): challenge mentah, hash kunci, dan versi.
- **Data perangkat nyata:** attestation iOS 27.0.1 dan tiga assertion iOS 27 dari repo MIT pihak ketiga hanya dipakai di scratchpad. Hasilnya membuktikan hash ganda pada assertion dan flags yang tidak konsisten (O-AA06).

## Perubahan

- `internal/appattest`: decoder CBOR minimal (≤ 128 item), pengurai authData tanpa flags, `VerifyAttestation`, dan `VerifyAssertion`.
- Root Apple di-embed dengan sidik jari dipin. credCert yang berstatus CA ditolak. `clientDataHash` diberikan pemanggil.
- Dokumen: ADR-0052; indeks ADR dilengkapi 0043–0052; ledger riset; GLOSSARY; SDD §10.4; QA TC-SEC-16.

## Bukti

- Contoh Apple lulus. Sembilan penyimpangan ditolak dengan alasan yang tepat, ditambah vektor sintetis untuk jalur lain.
- Data iOS 27 nyata lulus (scratch).
- Mutasi 28/28 tertangkap; fuzz tiga target tanpa crash; Go 11 paket lulus.
- Review akhir: siap merge. Amplifikasi alokasi CBOR diperbaiki (±8,7 MB → ±10 KB).

`jev_gate`: eskalasi (pembatas `blast_radius`), dicatat tanpa diajukan ulang. Minor untuk unit penyambungan ada di [backlog](../backlog.md).

## Pelajaran

- [Verifikasi uji dan gerbang commit](../lessons/verifikasi-uji-dan-gerbang.md).
- **Contoh resmi vendor bisa keliru.** Validasi dengan data perangkat nyata sebelum mengunci konvensi, tetapi jangan masukkan data pihak ketiga ke repo.
