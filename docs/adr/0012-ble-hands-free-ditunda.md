# ADR-0012: BLE hands-free ditunda (P2); R1 hanya Tap

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** O-B04, U11, FR-81

## Konteks

Pemindaian BLE di background lebih lambat dan tidak otomatis pulih. Hands-free berisiko membuka pintu yang hanya dilewati pengguna.

## Keputusan

R1 hanya mendukung **Tap** dari app/widget. Hands-free dievaluasi setelah uji lapangan.

## Konsekuensi

Tidak perlu izin lokasi "Always" di R1, sehingga jejak izin minimal.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Should R1 include BLE hands-free (background proximity) unlocking?
- **Prioritas yang diberikan:** For R1, reliability and safety over convenience; avoid unintended unlocks; keep the permission footprint minimal.
- **Hasil:** `foreground_tap_only` · confidence **1** · escaped: false
- **Biaya:** 963 token input + 152 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `foreground_tap_only` | 1 | R1 supports BLE Tap from the app or widget only; hands-free is evaluated after field tests (P2). |
| `optin_handsfree_r1` | 0 | R1 ships opt-in hands-free unlocking in the background. |
| `ask_user` | 0 | _escape hatch_ |
| `investigate` | 0 | _escape hatch_ |
| `none` | 0 | _escape hatch_ |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | Avoids unintended door openings. | supported |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
