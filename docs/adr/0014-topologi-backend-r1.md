# ADR-0014: Topologi backend R1: multi-region primary + hot standby

- **Status:** Diterima (keputusan pengguna, 2026-11-01) — sebelumnya dieskalasi karena confidence JEV 0,48
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** O-W14, O-W15, NFR-R02, NFR-R03

## Konteks

Presentasi tetap jalan offline, jadi outage backend hanya memblokir enrolment, perpanjangan, dan aksi admin. R2 (Wallet) mewajibkan DR multi-region dengan failover ≤ 30 menit. Tim sensitif biaya.

## Keputusan

Region primer + region sekunder *hot standby* dengan failover otomatis sejak R1. JEV hanya condong ke opsi ini (confidence rendah) sehingga keputusan dieskalasi; pengguna menyetujui usulan ini pada 2026-11-01 ("approve semua saran"). Alternatif yang tidak dipilih: satu region multi-AZ di R1 lalu multi-region di R2.

## Konsekuensi

Bila disetujui: biaya infrastruktur R1 lebih tinggi, tetapi tanpa re-arsitektur untuk R2. Bila ditolak: NFR-R03 harus dilonggarkan untuk R1.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** What backend deployment topology should Anastrophe use for R1?
- **Prioritas yang diberikan:** Meet R1 objectives cost-effectively while avoiding a rewrite when R2 requires multi-region DR.
- **Hasil:** `multi_region_passive` · confidence **0.48** · escaped: false
- **Biaya:** 1567 token input + 326 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `multi_region_passive` | 0.57 | R1: primary region plus hot-standby secondary region with automated failover; promote to active-active for R2 if needed. |
| `single_region_ha` | 0.35 | R1: single region, multi-AZ HA, cross-region backups; R2: add multi-region. |
| `investigate` | 0.03 | _escape hatch_ |
| `ask_user` | 0.02 | _escape hatch_ |
| `none` | 0.02 | _escape hatch_ |
| `multi_region_active` | 0.01 | R1: active-active in two regions. |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | Can recover from a full region outage within 30 minutes. | supported |
| 1 | Does not require re-architecture to meet R2 disaster-recovery requirements. | supported |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
