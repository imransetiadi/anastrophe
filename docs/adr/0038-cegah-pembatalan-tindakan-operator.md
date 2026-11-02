# ADR-0038: Pemegang kartu tidak boleh membatalkan suspend/revoke operator (terbuka)

- **Status:** Diusulkan — butuh keputusan manusia (eskalasi)
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-39, FR-51, US-11, ADR-0026, ADR-0027, ADR-0031, ADR-0032, ADR-0035, ADR-0036, temuan review akhir siklus hidup C1

## Konteks

Setelah operator menangguhkan atau mencabut card instance, pemegang kartu masih bisa mendapat kredensial baru untuk kartu fisik yang sama tanpa tindakan operator. Review akhir mereproduksinya lewat HTTP terhadap PostgreSQL:

1. **Suspend:** kartu ditangguhkan → pengguna menghapus kartunya (ADR-0027 mengizinkan untuk `SUSPENDED`) → mendaftar ulang kartu fisik yang sama → `PROVISIONING` → kredensial baru, `ACTIVE`.
2. **Revoke:** kartu dicabut (mis. `--reason pindah`) → mendaftar ulang → `PROVISIONING`.

Penyebabnya, enrolment jalur kartu hanya menganggap instance aktif sebagai pemegang. Instance `REVOKED` diabaikan, dan belum ada perintah untuk menandai kartu `REMOVED` di registri.

## Opsi

| Opsi | Inti | Probabilitas JEV |
|---|---|---|
| `hold_pending_approval` | Suspend/revoke memasang *hold* pada kartu fisik. Selama ada hold, enrolment jalur kartu menjadi `PENDING_APPROVAL` dan undangan berkartu tidak berlaku. Resume atau approve melepas hold. | 0.53 |
| `block_reenrol_code` | Enrolment jalur kartu ditolak 409 `ENR-CARD-BLOCKED` sampai operator melepas blokir (resume atau perintah baru). | 0.25 |
| `revoke_removes_card` | Revoke juga menandai kartu `REMOVED` di registri; pengguna tidak boleh menghapus kartu yang ditangguhkan (409). Penerimaan kembali lewat impor ulang. | 0.19 |
| `explicit_registry_remove` | Perintah `remove` terpisah dan dokumentasi; tanpa blokir otomatis. | 0 |

## Hasil JEV

- **Hasil:** `hold_pending_approval` · confidence **0.45** · escaped: false · tanpa requirement *contradicted*
- Confidence di bawah 0,60, jadi keputusan dieskalasi ke pengguna (ADR-0018) dan tidak diajukan ulang tanpa bukti baru.
- **Log mentah:** [`jev-log/2026-11-02-round22.input.json`](jev-log/2026-11-02-round22.input.json), [`jev-log/2026-11-02-round22.output.json`](jev-log/2026-11-02-round22.output.json)

## Rekomendasi penulis

`hold_pending_approval`. Opsi ini memakai mekanisme yang sudah dikenal operator (`PENDING_APPROVAL` lalu `approve`/`reject`), mencakup suspend maupun revoke, tidak membuat pesan pengguna menyesatkan (kartu tidak dilaporkan "tidak terdaftar"), dan memberi jalur penerimaan kembali yang jelas.

## Keterbatasan sampai diputuskan

- Suspend dan revoke oleh operator **bisa dilewati** dengan pendaftaran ulang kartu fisik yang sama. CLI mencetak peringatan ini setelah `suspend` dan `revoke`.
- TC-ADM-03 tetap "sebagian lulus", dan FR-51 belum dinyatakan terpenuhi.
