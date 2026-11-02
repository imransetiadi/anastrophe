# ADR-0054: Fokus berikutnya: observabilitas backend — log akses terstruktur dan metrik (NFR-O01 sebagian)

- **Status:** Diterima (JEV 0,99)
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** NFR-O01, NFR-P05, NFR-PR01, CLAUDE.md aturan 6, TC-PERF-05

## Konteks

NFR-O01 menuntut log terpusat, metrik, alert, dan on-call. Backend saat ini hanya menulis log galat, tanpa log akses per permintaan, request id, atau metrik. Akibatnya insiden sulit dilacak, dan target latensi NFR-P05 (p95 ≤ 300 ms) tidak bisa diamati.

Kandidat FR P0 lain sebagian besar terblokir: butuh akun, push, portal, dokumen legal, atau keputusan pengguna.

## Hasil JEV

- **Hasil:** `observability_nfr_o01` · confidence **0.99** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round39.input.json`](jev-log/2026-11-02-round39.input.json), [`jev-log/2026-11-02-round39.output.json`](jev-log/2026-11-02-round39.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `observability_nfr_o01` | 0.99 | ketiganya *supported* |
| `privacy_manifest_nfr_pr04` | 0.01 | P0: *contradicted* (deklarasi data menunggu legal) |
| `laporan_fr58` | 0 | P0: *unknown* |
| `akses_cepat_fr24` | 0 | P0: *contradicted* (P1) |
| `polling_test_konkurensi` | 0 | P0: *unknown* |

## Keputusan

- **Log akses terstruktur per permintaan:** request id, pola rute, status, durasi, dan ukuran respons.
  - Tidak mencatat path mentah, query string, body, header, atau alamat IP (aturan 6, NFR-PR01).
  - Request id dikirim balik di header `X-Request-ID` dan ikut di log galat.
- **Endpoint metrik teks:** jumlah permintaan per rute/status, histogram durasi per rute (dengan batas 0,3 dtk untuk NFR-P05), dan permintaan yang sedang berjalan.
  - Hanya stdlib, di listener internal terpisah yang aktif bila dikonfigurasi.
- **Di luar cakupan (infrastruktur):** pengiriman dan penyimpanan log terpusat, alert, on-call, tracing.

Desain dan rencananya ada di `docs/superpowers/specs/2026-11-02-observabilitas-backend-design.md` dan `docs/superpowers/plans/2026-11-02-observabilitas-backend.md`.

## Konsekuensi

- Insiden bisa dilacak dari request id di respons sampai log galat.
- Latensi per rute bisa diamati.
- NFR-O01 baru sebagian: alert dan on-call butuh infrastruktur.
