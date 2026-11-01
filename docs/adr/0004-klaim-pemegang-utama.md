# ADR-0004: Kartu fisik = bukti kepemilikan lemah; PRIMARY wajib cocok registri

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** I-04, FR-18, FR-59

## Konteks

UID kartu fisik bisa dibaca siapa pun yang meminjam kartu, dan bisa di-clone ke *magic card*. Pendaftar pertama menetapkan security code yang wajib dimasukkan anggota berikutnya.

## Keputusan

Peran **PRIMARY** hanya diberikan bila kontak terverifikasi (OTP) cocok dengan pemegang di registri. Jika tidak cocok, enrolment menunggu persetujuan admin. Pemegang sah dapat mengajukan sengketa.

## Konsekuensi

Registri perlu menyimpan HMAC kontak pemegang (FR-52). Portal admin membutuhkan antrean sengketa (FR-59).

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** What default policy should decide who becomes the PRIMARY holder when a physical card is first enrolled?
- **Prioritas yang diberikan:** Prevent card hijacking by someone who borrowed a card, keep enrollment fast for legitimate holders, keep admin workload low.
- **Hasil:** `holder_match_else_approval` · confidence **1** · escaped: false
- **Biaya:** 1558 token input + 335 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `holder_match_else_approval` | 1 | PRIMARY only when the user's verified phone/email matches the registry holder; otherwise the enrollment waits for admin approval; the legitimate holder can file a dispute. |
| `admin_approval_always` | 0 | Every PRIMARY enrollment requires admin approval. |
| `first_tap_wins` | 0 | Whoever enrolls the card first becomes PRIMARY. |
| `ask_user` | 0 | _escape hatch_ |
| `investigate` | 0 | _escape hatch_ |
| `none` | 0 | _escape hatch_ |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | Someone who briefly borrows a card cannot become PRIMARY without additional verification. | supported |
| 1 | A legitimate holder with matching contact data can finish enrollment without waiting for an admin. | supported |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
