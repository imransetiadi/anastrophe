---
type: session
project: anastrophe
date: 2026-11-02
status: selesai-dengan-risiko-sisa
tags: [backend, app, keamanan, provisioning, fr-16]
---
# 2026-11-02 — Provisioning kredensial yang aman

Keputusan: [ADR-0039](../decisions/ADR-0039-fokus-provisioning-aman.md) (fokus), [ADR-0040](../decisions/ADR-0040-rahasia-enrolment-kredensial-pertama.md) (rahasia enrolment), dan [ADR-0041](../decisions/ADR-0041-pengambilalihan-enrolment-belum-selesai.md) (terbuka, menunggu pengguna). Spesifikasi: `docs/superpowers/specs/2026-11-02-provisioning-aman-design.md`; rencana: `docs/superpowers/plans/2026-11-02-provisioning-aman.md`.

## Perubahan

- **Server (migrasi 0011):** `provisioning_key_hash` dipasang dalam transaksi enrolment.
  - Provisioning wajib membawa rahasianya sebagai bearer. Semua kegagalan dijawab 404 yang identik, sebelum status diungkap.
  - Hanya instance `PROVISIONING` yang bisa diprovisikan, dan hash dihapus setelah kredensial pertama.
- **App:** `ProvisioningSecret` hanya di memori; hash dikirim saat enrolment dan bearer saat kredensial pertama.
- **Test:** fixture Go bertindak sebagai klien yang benar, dan `allTablesText` mendekode kolom `bytea`.

## Bukti

- RED membuktikan celahnya: tanpa rahasia, provisioning berhasil (200), dan status menunggu persetujuan bocor (409).
- Go: 10 paket lulus. Swift: host 284 test, simulator 282 test.
- Uji mutasi tertangkap: server 5, app 2, test kebocoran 1.
- Lab simulator: app memprovisikan normal; serangan dengan id instance dari `:challenge` dijawab 404 dan jumlah kredensial tetap 1.

## Review akhir dan perbaikan

- **I2:** test kebocoran buta terhadap base64 di dump yang di-lowercase dan terhadap teks di kolom `bytea`. Kini keduanya terdeteksi (dibuktikan dengan mutasi).
- **I1:** tanpa autentikasi perangkat, pihak yang tahu id perangkat dan identitas kartu (atau token undangan) bisa mengganti hash instance yang belum selesai. JEV 0,44, jadi dieskalasi sebagai ADR-0041 dengan rekomendasi `first_writer_wins`. Dokumen dan backlog sudah dijujurkan.
- **Proses:** `check_docs | tail && git commit` tidak menahan commit; ke depan, kode keluar skrip yang memutuskan.

Minor tertunda (M1, M2, M4, sisa M5, M6): ledger rencana, diringkas di Memory.md.

`jev_gate` tereskalasi (composite 0,74). Log: `docs/adr/jev-log/2026-11-02-provisioning-aman-gate.json`.
