# ADR-0033: Iterasi berikutnya membangun enrolment via undangan

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-12, FR-13, FR-51, FR-03, ADR-0031, ADR-0032, SDD §8.1

## Konteks

Registri kartu fisik dan enrolment berbasis kartu sudah dibangun (ADR-0031/0032). Kartu yang tidak terbaca dan gedung tanpa registri belum punya jalur enrolment, padahal FR-13 menawarkan undangan untuk kasus itu dan FR-12 berprioritas P0. Akun (FR-03) masih bergantung pada penyedia eksternal yang belum dipilih.

## Keputusan

Iterasi berikutnya membangun **enrolment via undangan** (FR-12):

- CLI operator membuat undangan sekali pakai: token acak, hanya hash yang disimpan, ada masa berlaku, dan bisa diikat ke kartu terdaftar.
- `POST /v1/enrollments` menerima token undangan sebagai alternatif identitas kartu. Pemakaian tunggal ditegakkan dalam transaksi, disertai audit.
- Alur lab app bisa mendaftar dengan undangan.

## Konsekuensi

- Kartu yang tidak terbaca, termasuk kartu 125 kHz, dan gedung tanpa registri punya jalur enrolment.
- App Clip untuk undangan tetap P2.
- Aksi admin (FR-51) dan fondasi akun (FR-03) menyusul.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Which work should the next autonomous iteration focus on now that the physical-card registry is built?
- **Prioritas yang diberikan:** jalur kritis pilot; bisa diverifikasi otomatis tanpa hardware atau penyedia eksternal; tidak bergantung pada keputusan tertunda; melanjutkan registri.
- **Hasil:** `invitation_enrolment` · confidence **0.89** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round17.input.json`](jev-log/2026-11-01-round17.input.json), [`jev-log/2026-11-01-round17.output.json`](jev-log/2026-11-01-round17.output.json)

| Kandidat | Probabilitas |
|---|---|
| `invitation_enrolment` | 0.91 |
| `admin_actions_cli` | 0.07 |
| `account_foundation` | 0.01 |
| `hardening_minor_sweep` | 0.01 |
