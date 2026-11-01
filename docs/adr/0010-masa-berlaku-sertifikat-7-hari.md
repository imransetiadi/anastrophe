# ADR-0010: Masa berlaku sertifikat kredensial default 7 hari

- **Status:** Diterima (provisional — tinjau ulang di akhir pilot M3)
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** NFR-R04, FR-45

## Konteks

Reader yang sepenuhnya offline hanya menolak kredensial tercabut ketika sertifikatnya kedaluwarsa. Pengguna bisa offline beberapa hari.

## Keputusan

Default **7 hari** (gedung dapat mengatur 1–30 hari). Sertifikat diperpanjang otomatis saat sisa < 50% dan perangkat online.

## Konsekuensi

Paparan terburuk 7 hari di reader offline. Pengguna offline lebih dari 3,5 hari mungkin melihat peringatan perpanjangan.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** What default validity should Anastrophe's in-app credential certificates have (sites can override between 1 and 30 days)?
- **Prioritas yang diberikan:** Bound the worst-case exposure of a revoked credential on a disconnected reader while avoiding lockouts for users who are offline for a few days.
- **Hasil:** `days_7` · confidence **0.78** · escaped: false
- **Biaya:** 1515 token input + 332 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `days_7` | 0.82 | 7-day certificates, renewed when under 50% remains. |
| `none` | 0.13 | _escape hatch_ |
| `days_1` | 0.02 | 1-day certificates. |
| `ask_user` | 0.02 | _escape hatch_ |
| `investigate` | 0.01 | _escape hatch_ |
| `days_30` | 0 | 30-day certificates. |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | A user who is offline for 3 days can still enter. | supported |
| 1 | A revoked credential stops working on a fully offline reader within one week. | supported |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
