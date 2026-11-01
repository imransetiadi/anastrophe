# ADR-0021: CBOR/COSE minimal ditulis sendiri untuk CredentialCert

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** SDD §7.3, ADR-0016, ADR-0020

## Konteks

ADR-0020 menyebut backend Go memakai pustaka CBOR/COSE. Implementasinya justru menulis sendiri CBOR minimal dan COSE_Sign1 ES256 tanpa dependensi. `CredentialCert` memakai skema tetap: tepat 7 kunci integer, byte string dan bilangan tak bertanda, total ≤ 200 B. Review kode independen menemukan decoder awal terlalu longgar; perbaikannya kini menolak encoding tidak minimal, overflow, kunci ganda, UTF-8 tidak valid, header tak terlindung yang tidak kosong, dan skema lain.

## Keputusan

**Pertahankan CBOR/COSE minimal yang ditulis sendiri** (subset tetap, decoding ketat, uji lintas implementasi dengan `scripts/anp1/lab_ca.py`). ADR-0020 diamandemen oleh ADR ini.

## Konsekuensi

Hanya satu bentuk byte yang sah per sertifikat, dan permukaan dependensi kode keamanan tetap kecil. Subset yang sama harus diimplementasikan di firmware reader (ADR-0016) dan tetap diuji terhadap test vector. Bila skema sertifikat berkembang jauh di luar subset ini, keputusan ditinjau ulang.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Should the Anastrophe Go backend keep its hand-written minimal CBOR/COSE code for CredentialCert, or switch to third-party CBOR/COSE libraries?
- **Prioritas yang diberikan:** Correct, auditable certificate encoding with exactly one valid byte form; small dependency surface for security-critical code; interoperability with the Python lab tool and future reader firmware; maintainability by a small team.
- **Hasil:** `keep_minimal` · confidence **0.98** · escaped: false
- **Biaya:** 1836 token input + 320 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `keep_minimal` | 0.98 | Keep the hand-written minimal CBOR/COSE (fixed schema, strict decoding, cross-implementation tests) and amend ADR-0020 to say so. |
| `use_libraries` | 0.01 | Replace it with fxamacker/cbor (strict deterministic mode) and veraison/go-cose. |
| `investigate` | 0.01 | _escape hatch_ |
| `ask_user` | 0 | _escape hatch_ |
| `none` | 0 | _escape hatch_ |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | Produces exactly one valid byte encoding per certificate and rejects non-canonical input. | supported |
| 1 | Keeps the security-critical dependency surface small. | supported |
| 2 | Stays interoperable with the Python lab tool's CBOR subset. | supported |

> `use_libraries` dinilai *contradicted* untuk requirement 1. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
