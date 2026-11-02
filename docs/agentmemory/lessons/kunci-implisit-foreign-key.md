---
type: lesson
project: anastrophe
date: 2026-11-02
tags: [postgresql, deadlock, audit]
---
# Kunci implisit foreign key ikut dalam urutan kunci

- `INSERT` ke tabel dengan foreign key mengambil `FOR KEY SHARE` pada baris induk. Kunci ini bertentangan dengan `FOR UPDATE`, dan juga dengan `UPDATE` pada kolom ber-indeks unik non-parsial, misalnya `sites.join_code`.
- Karena itu "kunci advisory diambil terakhir" belum cukup. Bila insert sesudah kunci advisory menyentuh baris induk yang dipegang `FOR UPDATE` oleh transaksi yang menunggu kunci advisory yang sama, terjadi 40P01.
- **Perbaikan:** ambil kunci baris induk yang dibutuhkan insert secara eksplisit sebelum kunci advisory (`SELECT 1 FROM sites WHERE id = $1 FOR KEY SHARE`).
- **Cara menguji tanpa jeda tetap:** transaksi lain menahan baris; polling `pg_stat_activity` (`datname = current_database()`, `wait_event_type = 'Lock'`); lalu `pg_try_advisory_lock` dari koneksi lain harus berhasil.
- Kasus: [deadlock enrolment–sapuan](../sessions/2026-11-02-deadlock-enrolment-sapuan.md).
