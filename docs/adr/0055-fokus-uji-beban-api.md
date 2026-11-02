# ADR-0055: Fokus berikutnya: uji beban API dan baseline lab (TC-PERF-05)

- **Status:** Diterima (JEV 0,95)
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** NFR-P05, NFR-R02, TC-PERF-05, ADR-0051, ADR-0054

## Konteks

TC-PERF-05 menuntut API (config, renew, enrol) bertahan pada 1.000 rps dengan p95 ≤ 300 ms dan galat < 0,1%. Uji ini belum pernah dijalankan. Backend kini punya histogram durasi per rute (ADR-0054), jadi pengukuran sisi server bisa dibandingkan dengan sisi klien.

Laptop dev tidak mewakili produksi, sehingga hasilnya hanya baseline lab yang menunjukkan titik panas, misalnya kunci rantai audit per gedung (ADR-0051) dan transaksi idempotency.

## Hasil JEV

- **Hasil:** `uji_beban_api` · confidence **0.95** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round40.input.json`](jev-log/2026-11-02-round40.input.json), [`jev-log/2026-11-02-round40.output.json`](jev-log/2026-11-02-round40.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `uji_beban_api` | 0.96 | ketiganya *supported* |
| `audit_aksesibilitas` | 0.03 | ketiganya *supported* |
| `privacy_manifest_teknis` | 0.01 | ketiganya *supported* |
| `laporan_fr58` | 0 | P0: *contradicted* (P1) |
| `akses_cepat_fr24` | 0 | P0: *contradicted* (P1) |

## Keputusan

- **Generator beban Go (stdlib):** skenario config, lookup kode gedung, enrolment + provisioning, dan perpanjangan.
  - Laporan p50/p95/p99 per langkah dan tingkat galat, ditambah porsi permintaan ≤ 0,3 dtk menurut histogram `/metrics` server.
  - Kartu yang dipakai hanya identitas sintetis yang dibuat alat ini (aturan 1 dan 6).
  - Hanya menembak host loopback, kecuali diizinkan eksplisit.
- **Baseline lab** dicatat di QA §11.1 sebagai baseline, bukan bukti produksi. Titik panas yang ditemukan dicatat untuk keputusan berikutnya.

Desain dan rencananya ada di `docs/superpowers/specs/2026-11-02-uji-beban-api-design.md` dan `docs/superpowers/plans/2026-11-02-uji-beban-api.md`.

## Konsekuensi

- Ada alat yang bisa diulang di staging/load environment (NFR-O02) begitu infrastruktur tersedia.
- TC-PERF-05 penuh (1.000 rps) tetap menunggu lingkungan Load.

## Catatan sesudah review akhir

Review akhir menemukan tiga masalah penting yang sudah diperbaiki dengan test lebih dulu sebelum baseline diukur ulang:

- **Redirect:** alat tidak lagi mengikuti redirect, dan garis miring di akhir `-base` dipangkas. Tujuan redirect bisa melewati penjaga loopback, dan setiap sampel sebelumnya menjadi dua permintaan.
- **Jalur enrol:** skenario enrol kini mengirim `Idempotency-Key` saat enrolment dan `status_token_hash` saat provisioning, sama seperti app. Tanpa keduanya yang diukur adalah jalur server yang berbeda.
- **Laju:** pekerja tetap closed-loop. Dengan `-rate`, token yang jatuh tempo saat semua pekerja sibuk dihitung terlewat; laporan memuat laju target dan laju tercapai, dan run gagal (exit 1) bila lebih dari 5% token terlewat. Koreksi coordinated omission, yaitu latensi diukur dari jadwal, masuk backlog.

Selain itu run yang berhenti lebih awal (pool kartu atau kredensial habis) keluar dengan exit 3, kegagalan `/metrics` dilaporkan, dan batas galat inklusif sesuai TC-PERF-05 (< 0,1%).
