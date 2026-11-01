# ADR-0023: Perpanjangan sertifikat memakai autentikasi tap

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-45, SDD §5.5 dan §8.4.2, ADR-0009, ADR-0010, O-W10, O-A25, O-A26, O-A27, I-15

## Konteks

SDD §8.4.2 meminta bukti kepemilikan berupa tanda tangan kunci kredensial atas nonce server. SDD §5.5 meminta perpanjangan dari `BGAppRefreshTask`. ADR-0009 melindungi kunci kredensial dengan `.userPresence`, sehingga setiap pemakaian butuh autentikasi pengguna. Tugas background tidak punya UI untuk autentikasi (I-15), jadi ketiganya tidak bisa dipenuhi bersamaan.

`LAContext` yang sudah diautentikasi dapat dipakai ulang untuk operasi kunci tanpa prompt kedua (O-A25). App sudah melakukan ini untuk tanda tangan ANP/1 pada setiap tap.

## Keputusan

Perpanjangan hanya terjadi **setelah pengguna mengautentikasi untuk tap**. App memakai ulang `LAContext` yang sama untuk menandatangani nonce server dengan kunci kredensial.

- Sisa masa berlaku < 50%: perpanjangan berjalan paralel dengan tap.
- Sertifikat sudah kedaluwarsa: perpanjangan berjalan lebih dulu (setelah Face ID/passcode yang sama), lalu tap dilanjutkan.
- `BGAppRefreshTask`, pembukaan app, dan silent push `cert_renewal_due` hanya memeriksa masa berlaku dan memperbarui status; ketiganya **tidak pernah** menandatangani.

## Konsekuensi

- Tidak ada prompt tambahan; perlindungan kunci ADR-0009 tidak berubah; server tetap menerima bukti kepemilikan dari kunci kredensial (SDD §8.4.2).
- Pengguna yang tidak memakai kartu sampai sertifikatnya kedaluwarsa butuh koneksi internet saat tap berikutnya, karena perpanjangan harus berhasil sebelum presentasi.
- SDD §5.5 diubah sesuai keputusan ini. App Attest tetap bagian dari §8.4.2 dan ditambahkan setelah tim pengembang Apple tersedia.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** How should Anastrophe authorize certificate renewal (FR-45), given that SDD §8.4.2 requires a credential-key signature over a server nonce, SDD §5.5 wants renewal from BGAppRefreshTask, and ADR-0009 protects credential keys with .userPresence?
- **Prioritas yang diberikan:** ikuti SDD/ADR; jangan ubah perlindungan kunci ADR-0009; tanpa prompt tambahan; harus jalan tanpa App Attest; manajemen kunci minimal.
- **Hasil:** `renew_on_user_auth` · confidence **0.98** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round7.input.json`](jev-log/2026-11-01-round7.input.json), [`jev-log/2026-11-01-round7.output.json`](jev-log/2026-11-01-round7.output.json)

| Kandidat | Probabilitas |
|---|---|
| `renew_on_user_auth` | 0.98 |
| `renew_prompt_on_open` | 0.01 |
| `renew_attest_only` | 0 |
| `renew_device_key` | 0 |
