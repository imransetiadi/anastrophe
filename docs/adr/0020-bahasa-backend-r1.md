# ADR-0020: Bahasa backend R1: Go

- **Status:** Diterima (provisional — tinjau ulang di akhir M1)
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** SDD §3.3, §8, §12; ADR-0014; TC-PROTO-01

## Konteks

SDD §3.3 menyebut backend referensi "TypeScript (Node.js 24) atau Go". Topologi sudah diputuskan: region primer + *hot standby* (ADR-0014). Backend menerbitkan `CredentialCert` (COSE_Sign1 ES256) dengan kunci Site CA di HSM/KMS, mengelola kunci reader group, memverifikasi App Attest, dan menegakkan batas 8 kartu per perangkat di PostgreSQL. Keahlian dan ukuran tim belum terdokumentasi.

## Keputusan

**Go (1.24+)** dengan pustaka standar untuk kripto/HTTP/mTLS, PostgreSQL 16 lewat pgx, dan satu biner statis per region. CBOR/COSE untuk `CredentialCert` ditulis sendiri sebagai subset minimal yang ketat (diamandemen oleh ADR-0021). Provisional: ditinjau ulang di akhir M1, terutama bila komposisi tim ternyata lebih kuat di TypeScript.

## Konsekuensi

Kripto inti memakai pustaka standar Go dan test vector `anp1-v1` dipakai ulang di CI backend. Satu biner statis memudahkan deployment identik di dua region. Bila keputusan dibalik, kontrak API (SDD §8.5) dan skema SQL tetap berlaku.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Which language/runtime should the Anastrophe R1 backend (REST /v1 API, enrollment, credential issuance, reader sync) be implemented in?
- **Prioritas yang diberikan:** Correct, auditable cryptography for certificate issuance and key handling; simple, reliable multi-region deployment (ADR-0014); a small team should be able to maintain it; reuse the shared anp1-v1 test vectors in CI.
- **Hasil:** `go` · confidence **0.7** · escaped: false
- **Biaya:** 2169 token input + 317 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `go` | 0.76 | Go (1.24+) service with the standard library for crypto/HTTP/mTLS, a CBOR/COSE library, PostgreSQL 16 via pgx, deployed as a single static binary per region. |
| `investigate` | 0.1 | _escape hatch_ |
| `typescript_node` | 0.08 | TypeScript on Node.js 24 with node:crypto, a CBOR/COSE package, PostgreSQL 16 via a Node driver, deployed as a container with the runtime per region. |
| `ask_user` | 0.06 | _escape hatch_ |
| `none` | 0 | _escape hatch_ |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | Can sign ES256 COSE_Sign1 certificates with a key held in a cloud KMS/HSM without exporting the private key. | supported |
| 1 | Can verify the shared anp1-v1 test vector values (P-256, HKDF-SHA256, AES-128-GCM) using maintained libraries. | supported |
| 2 | Can be deployed identically to a primary and a hot-standby region with automated failover. | unknown |

> Requirement 2 dinilai *unknown* untuk kedua kandidat (bergantung pada infrastruktur, bukan bahasa). Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
