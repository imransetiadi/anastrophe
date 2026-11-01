# ADR-0015: Batas anggota default 4 per kartu (dapat diatur gedung)

- **Status:** Diterima (provisional — tinjau ulang di akhir pilot M3)
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-36

## Konteks

Samsung tidak menyebut batas anggota. Rumah tangga di pasar target umumnya 2–6 orang.

## Keputusan

Default **4 anggota** per kartu; gedung dapat mengubahnya.

## Konsekuensi

Ditinjau ulang dengan data pilot (distribusi jumlah anggota).

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** What default maximum number of members per card should Anastrophe use (sites can override)?
- **Prioritas yang diberikan:** Cover typical households without encouraging credential sprawl; sites can override.
- **Hasil:** `max_4` · confidence **0.65** · escaped: false
- **Biaya:** 649 token input + 74 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `max_4` | 0.71 | Default 4 members per card. |
| `max_6` | 0.26 | Default 6 members per card. |
| `investigate` | 0.02 | _escape hatch_ |
| `ask_user` | 0.01 | _escape hatch_ |
| `max_2` | 0 | Default 2 members per card. |
| `none` | 0 | _escape hatch_ |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
