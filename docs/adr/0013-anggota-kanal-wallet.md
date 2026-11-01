# ADR-0013: Anggota kanal W lewat security code di app; Wallet sharing nonaktif

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** O-S12–O-S14, O-W11, FR-35

## Konteks

Samsung tidak mengizinkan sharing; anggota memakai security code. Wallet sharing bersifat opsional dan dikendalikan Credential Manager.

## Keputusan

Anggota bergabung lewat app dengan security code pemilik, lalu mem-provision pass Wallet masing-masing. Izin sharing Wallet **dinonaktifkan**.

## Konsekuensi

Satu model anggota untuk semua kanal; pemilik selalu dapat melihat dan menghapus anggota di app.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** For the Apple Wallet channel (R2), how should a primary cardholder's family members get access to the same card?
- **Prioritas yang diberikan:** Mirror Samsung's behavior (no sharing to arbitrary parties), keep the owner in control, minimize custom UX and keep one consistent member model across channels.
- **Hasil:** `app_security_code` · confidence **0.89** · escaped: false
- **Biaya:** 1572 token input + 332 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `app_security_code` | 0.91 | Members join in the Anastrophe app with the owner's security code; each member provisions their own Wallet pass; Wallet sharing disabled. |
| `wallet_sharing` | 0.06 | Use Apple Wallet pass sharing with a 6-digit activation code as the member mechanism. |
| `site_configurable` | 0.01 | Default to app security code; sites may enable Wallet sharing. |
| `investigate` | 0.01 | _escape hatch_ |
| `none` | 0.01 | _escape hatch_ |
| `ask_user` | 0 | _escape hatch_ |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | The owner can see and remove members. | unknown |
| 1 | The card cannot be shared to arbitrary third parties. | supported |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
