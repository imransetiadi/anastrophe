# Observabilitas backend: log akses terstruktur dan metrik (NFR-O01 sebagian) — desain

**Status:** fokus dari ADR-0054 (JEV 0,99). Mode iterasi otomatis; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

Saat ini tidak ada jejak per permintaan dan tidak ada angka latensi atau galat per rute. Akibatnya insiden tidak bisa dilacak dan target NFR-P05 tidak bisa diamati. Unit ini menambah keduanya tanpa dependensi baru dan tanpa data pribadi di log.

## Tujuan

1. **Log akses:** satu baris per permintaan (`msg = "http request"`) dengan:
   - `request_id`;
   - `route`, yaitu pola ServeMux yang cocok, misalnya `POST /v1/enrollments/{id}/credentials`, dan `/` untuk rute tak dikenal;
   - `status`, `duration_ms`, dan `bytes`.
2. **Yang tidak dicatat:** path mentah, query string, body, header, dan alamat IP (*keputusan builder*: IP termasuk data pribadi menurut UU PDP/GDPR; log load balancer di luar cakupan).
3. **Request id:**
   - 8 byte acak (16 heksadesimal) per permintaan, dikirim di header respons `X-Request-ID`;
   - header `X-Request-ID` dari klien diabaikan (*keputusan builder*: mencegah spoofing dan injeksi log);
   - log galat handler memakai `slog.*Context` sehingga membawa `request_id` yang sama.
4. **Metrik** (format teks eksposisi Prometheus 0.0.4, ditulis dengan stdlib):
   - `anastrophe_http_requests_total{route,status}`;
   - `anastrophe_http_request_duration_seconds{route}`, histogram dengan bucket 0,005; 0,01; 0,025; 0,05; 0,1; 0,25; 0,3; 0,5; 1; 2,5; 5; 10;
   - `anastrophe_http_requests_in_flight`.
   - Output terurut agar deterministik, dan nilai label di-escape.
5. **Eksposur metrik:** `/metrics` hanya di listener internal `ANASTROPHE_METRICS_ADDR`. Bila variabel itu kosong, listener tidak dibuat. Port publik tidak pernah melayani `/metrics`.
6. **Format log:** `ANASTROPHE_LOG_FORMAT=json` untuk log terpusat; bawaannya teks (*keputusan builder*: perilaku lama tetap).
7. **Panic:** log panic memakai pola rute, bukan path mentah.

## Non-goal

Pengiriman dan penyimpanan log terpusat, alert, on-call, tracing terdistribusi, metrik database dan pekerjaan latar, serta retensi log (NFR-PR03).

## Anti-goal

- Identitas kartu, kontak, token, rahasia enrolment, id dari path, atau IP muncul di log atau label metrik.
- Kardinalitas label metrik yang tidak terbatas, misalnya path mentah sebagai label.
- `/metrics` terjangkau dari port publik.
- Panic yang tidak tercatat sebagai 500 di log akses dan metrik.

## Uji

- **Log akses:**
  - satu permintaan dengan query, body, dan id di path menghasilkan log berisi pola rute, status, durasi, dan `request_id` yang sama dengan header;
  - nilai query, body, id path, dan IP tidak muncul di log.
- **Request id:** unik, 16 heksadesimal, dan header klien diabaikan.
- **Korelasi galat:** log galat handler membawa `request_id`.
- **Metrik:**
  - hitungan per rute dan status untuk rute terdaftar, rute tak dikenal (`/`), 405, dan panic (500);
  - bucket histogram kumulatif, `+Inf` = `_count`, ada `le="0.3"`;
  - in-flight kembali ke 0;
  - escape label;
  - port publik `/metrics` → 404.
- **Konfigurasi:** listener metrik hanya bila diatur; format JSON dan teks.

## Review Focus

1. Tidak ada data pribadi atau id di log maupun label metrik, termasuk di jalur galat dan panic.
2. Pola rute tetap tertangkap walau `withDeadline` membuat salinan request.
3. Kardinalitas label terbatas pada pola ServeMux.
4. `/metrics` tidak terjangkau dari port publik.
5. Overhead dan keamanan konkurensi: metrik aman dipakai bersamaan (`-race`).

## Diserahkan ke builder

Nama tipe dan fungsi, susunan berkas, dan format pesan log.
