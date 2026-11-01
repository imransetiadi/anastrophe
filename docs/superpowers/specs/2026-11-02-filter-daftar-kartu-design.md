# Filter kanal dan pencarian daftar kartu (FR-50) — desain

**Status:** fokus dari ADR-0050 (JEV 1,0). Mode iterasi otomatis; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

Operator sudah bisa memfilter daftar card instance berdasarkan status, tetapi belum berdasarkan kanal, dan belum bisa mencari satu instance tanpa menyalin seluruh id dari keluaran panjang. FR-50 meminta keduanya.

## Tujuan

1. **Opsi CLI:** `anastrophe-registry list --site <uuid> [--status S] [--channel ble|nfcHCE] [--id <awalan>]`. Semua filter digabung dengan AND.
2. **`--channel`:** card instance yang punya kredensial `ACTIVE` atau `SUSPENDED` pada kanal itu, sama dengan kolom KANAL di keluaran.
3. **`--id`:** awalan id card instance, 1–36 karakter `0-9`, `a-f`, atau `-`, tidak peka huruf besar. *Keputusan builder:* hanya karakter itu, sehingga tidak ada wildcard `LIKE` dari masukan.
4. **Validasi:** kanal tak dikenal atau awalan tidak sah → exit 2 dengan pesan jelas, tanpa query.
5. **Kolom keluaran tetap:** tanpa identitas kartu atau kontak (aturan 6).

## Non-goal

Pencarian nama, kontak, nomor kartu, atau `acs_card_number`; portal admin; ekspor.

## Review Focus

1. Awalan dengan `%`/`_` atau karakter lain ditolak; tidak ada injeksi pola `LIKE`.
2. Kombinasi filter (status + kanal + id) memakai AND.
3. Kanal mengikuti kredensial `ACTIVE`/`SUSPENDED`, bukan yang dicabut.

## Diserahkan ke builder

Nama fungsi dan pesan galat.
