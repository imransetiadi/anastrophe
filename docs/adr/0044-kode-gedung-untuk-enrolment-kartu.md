# ADR-0044: Kode gedung untuk enrolment kartu fisik

- **Status:** Diterima (JEV 0,96)
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-11, FR-13, US-01, ADR-0031, ADR-0043

## Konteks

`POST /v1/enrollments` jalur kartu wajib membawa `site_id` karena server menghitung HMAC identitas kartu dengan kunci per gedung (ADR-0031). Identitas ISO 14443A 4 byte tidak unik global, jadi server tidak bisa mencocokkan kartu ke semua gedung. `sites.site_code` adalah 8 byte biner untuk sertifikat, bukan kode yang bisa diketik. Belum ada endpoint pencarian gedung, domain Universal Link belum ditentukan, dan simulator tidak punya kamera.

## Hasil JEV

- **Hasil:** `kode_gedung_lookup` · confidence **0.96** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round29.input.json`](jev-log/2026-11-02-round29.input.json), [`jev-log/2026-11-02-round29.output.json`](jev-log/2026-11-02-round29.output.json)

| Kandidat | Probabilitas | Requirement yang gagal |
|---|---|---|
| `kode_gedung_lookup` | 0.97 | — |
| `kode_gedung_langsung` | 0.01 | nama gedung tidak bisa dikonfirmasi sebelum tempel kartu |
| `tautan_gedung` | 0.01 | butuh menyalin teks panjang; nama tidak terkonfirmasi |
| `daftar_gedung` | 0 | membuka daftar gedung pelanggan |

## Keputusan

- **Kolom baru:** `sites.join_code`, 8 karakter Crockford base32 (±40 bit), unik, ditampilkan sebagai `XXXX-XXXX`. Operator membuat atau merotasinya lewat `anastrophe-registry site-code`.
- **Endpoint baru:** `GET /v1/sites/lookup?code=` mengembalikan `{site_id, name}`. Kode yang tak dikenal, tidak berbentuk sah, atau kosong dijawab identik: 404 `SITE-NOT-FOUND`.
- **Normalisasi kode:** huruf besar; `-` dan spasi dibuang; `O` dibaca `0`; `I` dan `L` dibaca `1`. App dan server memakai aturan yang sama.
- **Alur app:** pengguna mengetik kode dari poster atau surat pengelola, lalu mengonfirmasi nama gedung sebelum menempelkan kartu.

## Konsekuensi

- Kode gedung bukan rahasia; ia boleh dicetak di poster. Gedung tetap tidak bisa didaftar tanpa mengetahui kodenya, karena ruang 40 bit tidak praktis ditebak. Pembatasan laju diserahkan ke infrastruktur.
- Rotasi kode membuat kode lama langsung tidak berlaku.
- Tautan gedung dan QR bisa menyusul di atas kode yang sama setelah domain Universal Link ada.
