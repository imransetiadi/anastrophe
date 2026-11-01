# ADR-0050: Fokus berikutnya: filter kanal dan pencarian daftar kartu (FR-50)

- **Status:** Diterima (JEV 1,0)
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-50, ADR-0036, ADR-0018

## Konteks

FR-50 (P0) meminta daftar kredensial per gedung dengan filter status/kanal dan pencarian. CLI `anastrophe-registry list` (ADR-0036) baru punya filter status. Portal admin penuh masih terblokir FR-56 (IdP SSO/MFA).

## Hasil JEV

- **Hasil:** `filter_cli_fr50` · confidence **1.0** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round35.input.json`](jev-log/2026-11-02-round35.input.json), [`jev-log/2026-11-02-round35.output.json`](jev-log/2026-11-02-round35.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `filter_cli_fr50` | 1.0 | ketiganya *supported* |
| `laporan_fr58` | 0 | P1 |
| `akses_cepat` | 0 | P1 |
| `minor_klien` | 0 | tidak memajukan P0 |

## Keputusan

`anastrophe-registry list` mendapat dua opsi baru: `--channel ble|nfcHCE` dan `--id <awalan id card instance>`. Daftar tetap tanpa identitas kartu dan kontak (aturan 6).

Desain dan rencananya ada di `docs/superpowers/specs/2026-11-02-filter-daftar-kartu-design.md` dan `docs/superpowers/plans/2026-11-02-filter-daftar-kartu.md`.

## Konsekuensi

- Pencarian hanya memakai awalan id card instance. Pencarian berdasarkan nama pemegang atau nomor kartu menunggu portal dan akun, dan tetap tunduk pada aturan 6.
