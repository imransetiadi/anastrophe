# ADR-0031: Iterasi berikutnya membangun registri kartu fisik dan pencocokan enrolment di server

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-11, FR-13, FR-03, FR-51, SDD §8.1, SDD §8.4.1

## Konteks

Fondasi R1 sudah ada: presentasi, provisioning, perpanjangan, audit, hapus kartu, dan riwayat tap. Backend belum punya autentikasi permintaan maupun model kepemilikan; `StartEnrollment(deviceID, siteID)` langsung membuat card instance. Fitur besar yang tersisa punya dependensi yang belum tersedia:

- Akun (FR-03) butuh Sign in with Apple dan penyedia OTP.
- App Attest dan pembacaan kartu fisik butuh iPhone.
- Portal admin butuh IdP admin.

Ada juga sekitar 30 minor tertunda dari review sebelumnya.

## Keputusan

Iterasi berikutnya membangun **registri kartu fisik dan pencocokan enrolment di server**:

- Tabel `physical_cards` dengan HMAC identitas kartu per gedung; nilai mentah tidak pernah disimpan (CLAUDE.md aturan 6).
- Impor registri lewat CLI operator yang hanya menyimpan HMAC.
- `POST /v1/enrollments` mencocokkan kartu dan memberi alasan spesifik bila tidak didukung (FR-13).

Peran dan kepemilikan (PRIMARY, MEMBER, security code) menyusul setelah fondasi akun ada.

## Konsekuensi

- Jalur kritis pilot (enrolment via kartu fisik) maju tanpa menunggu hardware atau penyedia eksternal.
- Pembacaan kartu di app tetap memakai antarmuka yang bisa di-mock; uji dengan kartu nyata menunggu iPhone.
- Minor tertunda tetap di backlog dan diambil di iterasi terpisah.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Which work should the next autonomous iteration focus on, given that no user decisions, Apple developer team, iPhone, or reader hardware are available?
- **Prioritas yang diberikan:** jalur kritis pilot; bisa diverifikasi otomatis tanpa hardware atau penyedia eksternal; tidak bergantung pada keputusan yang tertunda; keamanan dan kebenaran yang sudah ada.
- **Hasil:** `registry_enrolment_server` · confidence **0.88** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round15.input.json`](jev-log/2026-11-01-round15.input.json), [`jev-log/2026-11-01-round15.output.json`](jev-log/2026-11-01-round15.output.json)

| Kandidat | Probabilitas |
|---|---|
| `registry_enrolment_server` | 0.9 |
| `account_foundation` | 0.05 |
| `hardening_minor_sweep` | 0.03 |
| `admin_actions_cli` | 0.02 |
