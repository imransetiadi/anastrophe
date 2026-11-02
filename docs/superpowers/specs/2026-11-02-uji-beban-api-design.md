# Uji beban API dan baseline lab (TC-PERF-05) — desain

**Status:** fokus dari ADR-0055 (JEV 0,95). Mode iterasi otomatis; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

Belum ada angka latensi atau kapasitas API di bawah beban. Unit ini membuat alat uji beban yang bisa diulang dan mengukur baseline lab untuk menemukan titik panas sebelum lingkungan Load tersedia.

## Tujuan

1. **Paket `backend/internal/loadtest`:**
   - **Runner:** N pekerja selama durasi tertentu, dengan laju target opsional bersama semua pekerja dan pembatalan context.
   - **Perekam latensi per langkah:** p50/p95/p99/maks, jumlah sukses, dan jumlah galat per status.
   - **Laporan teks.**
2. **Skenario** (satu iterasi = urutan langkah HTTP; latensi dicatat per langkah):
   - `config`: `GET /v1/config`.
   - `lookup`: `GET /v1/sites/lookup?code=<kode>`.
   - `enrol`:
     - `POST /v1/enrollments` dengan device id acak baru, kartu berikutnya dari pool sintetis, dan hash rahasia enrolment;
     - lalu `POST /v1/enrollments/{id}/credentials` dengan `Authorization: Bearer <rahasia>`, `Idempotency-Key`, kanal `ble`, dan kunci P-256 baru;
     - kredensial yang terbit disimpan untuk skenario `renew`.
   - `renew`: `POST /v1/credentials/{cred}:challenge`, lalu `POST …:renew` dengan `Idempotency-Key` dan tanda tangan `"ANP1-RENEW" ‖ cred_id ‖ nonce` (raw r‖s). Kredensial disiapkan lewat enrolment di awal run.
   - Laju 1.000 rps tidak dipaksakan di laptop. Laju dan konkurensi diatur lewat flag.
3. **Pool kartu sintetis:**
   - `anastrophe-loadtest gen-cards -n N` menulis CSV impor registri (`tech,card_id,holder_contact,zones`). Isinya UID `iso14443a` 7 byte dengan awalan tetap `08 4C 54` ("LT"), tanpa kontak (*keputusan builder*).
   - Berkas yang sama dibaca `run`. Operator mengimpornya dengan `anastrophe-registry import`.
4. **CLI `cmd/anastrophe-loadtest run`:**
   - flag: `-base`, `-scenario`, `-duration`, `-concurrency`, `-rate`, `-site`, `-code`, `-cards`, `-metrics`;
   - bila `-metrics` diisi, alat mengambil `/metrics` sebelum dan sesudah, lalu mencetak porsi permintaan per rute yang ≤ 0,3 dtk;
   - host selain loopback ditolak kecuali `-allow-remote` (*keputusan builder*: mencegah membebani server sungguhan tanpa sengaja).
5. **Baseline lab:**
   - jalankan tiap skenario pada beberapa konkurensi terhadap API + PostgreSQL lab;
   - catat lingkungan (mesin, Go, PostgreSQL, pool) dan hasilnya di QA §11.1 sebagai baseline, bukan bukti produksi;
   - titik panas yang ditemukan dicatat di backlog.

## Non-goal

Beban terdistribusi, 1.000 rps di laptop, endpoint Apple (TC-PERF-06), tuning database, dan perubahan perilaku API.

## Anti-goal

- Alat yang tanpa sengaja menembak server non-lokal.
- Identitas kartu nyata, kontak, rahasia, atau kunci yang ditulis ke log atau laporan. Rahasia dan kunci hanya hidup di memori.
- Angka lab yang disajikan sebagai bukti TC-PERF-05 produksi.

## Uji

- **Unit:**
  - persentil (termasuk sampel kosong dan satu sampel);
  - runner dengan server `httptest` (jumlah iterasi, galat per status, pembatalan, laju);
  - format CSV `gen-cards` dan awalan sintetis;
  - penolakan host non-loopback.
- **Integrasi** (API in-process + PostgreSQL uji): skenario `config`, `lookup`, `enrol`, dan `renew` berjalan beberapa iterasi dengan 0 galat, dan kredensial dari `enrol` dipakai `renew`.
- **Parsing `/metrics`:** porsi ≤ 0,3 dtk dihitung dari selisih bucket.

## Review Focus

1. Persentil benar (indeks, pembulatan, sampel kecil).
2. Laju target tidak terlampaui dan pekerja berhenti tepat saat durasi habis.
3. Skenario memakai format protokol yang benar (rahasia enrolment, tanda tangan perpanjangan), dan galat tidak tertutupi.
4. Tidak ada rahasia, kunci, atau identitas di keluaran.
5. Penjaga host loopback tidak bisa dilewati tanpa flag.

## Diserahkan ke builder

Nama tipe dan fungsi, format laporan, dan susunan berkas.
