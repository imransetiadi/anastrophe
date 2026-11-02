# ADR-0059: Kebijakan isu kontras audit: pengecualian per elemen dengan bukti (TC-UX-01)

- **Status:** Diterima (JEV 0,93)
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** NFR-A01, TC-UX-01, TC-UX-03, ADR-0018, ADR-0057, ADR-0058, spesifikasi `docs/superpowers/specs/2026-11-02-audit-aksesibilitas-design.md` (Tujuan 8; "Keputusan sesudah bukti audit pertama" butir 2), W3C *Understanding SC 1.4.3*

## Konteks

Builder check ADR-0057 menduga audit bisa menandai teks kecil berpasangan token yang sebenarnya ≥ 4,5:1, karena piksel di-antialias. Kalibrasi di runtime iOS 26.5 (simulator iPhone Air 3x) memakai teks berwarna sRGB yang diketahui, dengan setiap baris diverifikasi piksel sebelum diaudit. Hasilnya:

- Ambang WCAG 2.x diterapkan persis:
  - rasio 3,00 → "failed";
  - 3,50–4,49 → "nearly passed";
  - mulai 4,61 → tidak ditandai.
- Teks besar (≥ 18 pt, atau 19 pt tebal) memakai ambang 3:1. Warna tembus pandang dicampur dengan benar.
- Pasangan token 4,62–4,92 pada 17 pt, 13 pt, dan 12 pt semibold tidak pernah ditandai. Perangkat 2x belum diuji.
- Semua kegagalan warna sistem saat ini berada di rentang 3,0–4,49 dan dilaporkan "nearly passed".
- Satu positif palsu: "Gedung Anda" (token `mutedForeground`) terukur 7,24 / 7,87 tetapi dilaporkan "failed". Penyebabnya struktural, bukan token di dekat ambang.

## Hasil JEV

- **Hasil:** `pengecualian_per_elemen_bukti` · confidence **0.93** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round44.input.json`](jev-log/2026-11-02-round44.input.json), [`jev-log/2026-11-02-round44.output.json`](jev-log/2026-11-02-round44.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `pengecualian_per_elemen_bukti` | 0.94 | ketiganya *supported* |
| `aturan_kategori_nyaris_lulus` | 0.02 | menyembunyikan kegagalan nyata dan pengecualian per elemen *contradicted* |
| `token_gagal_eskalasi` | 0.02 | pengecualian per elemen *contradicted* |

## Keputusan

- **Tidak ada aturan kategori** untuk isu kontras "nearly passed". Rentang itu tepat tempat kegagalan warna sistem berada.
- **Isu kontras dikecualikan satu elemen per entri**: jenis audit, identifier atau label persis, dan alasan tertulis. Ketiga syarat ini wajib terpenuhi semua:
  1. elemen memakai warna token;
  2. pasangan tokennya lolos test host (`ContrastTests`) pada permukaan nyatanya;
  3. pengukuran piksel screenshot mengonfirmasi warna yang dirender.
- **Alasan pengecualian** merujuk W3C *Understanding SC 1.4.3*: kontras dinilai dari warna yang ditetapkan, bukan dari piksel hasil antialias.
- **Pengecualian ditinjau ulang** tiap rilis iOS dan tiap kelas perangkat baru.
- **Aturan sempit yang sudah ada tetap berlaku:**
  - kontras komponen nonaktif (pengecualian WCAG 1.4.3);
  - elemen yang beririsan dengan bilah sistem sesudah halaman digulir (spesifikasi Tujuan 8).

## Konsekuensi

- Audit tetap menangkap kegagalan kontras warna sistem. Setiap pengecualian kontras punya bukti piksel yang dicatat di QA §11.1.
- Margin token tertipis adalah `destructive` di atas `background`, 4,62:1. Bila isu berulang pada pasangan token di perangkat 2x, nilai token dinaikkan lewat ADR baru, tidak lewat pengecualian.
