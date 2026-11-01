---
type: lesson
project: anastrophe
date: 2026-11-01
tags: [jev, gate, proses]
---
# jev_gate memverifikasi klaim hanya dari butir evidence

- Kolom `tests` dipakai untuk review patch, bukan untuk verifikasi klaim. Log uji yang hanya ada di `tests` membuat klaim jumlah test, uji mutasi, dan katalog string berstatus *unsupported*.
- Tulis klaim persis seperti bunyi log (misalnya baris `Test run with N tests … passed`), bukan angka turunan seperti "234 lulus".
- Taruh kutipan log verbatim sebagai butir `evidence` tersendiri (host, simulator, mutasi, isi katalog).
- Gate ulang paling banyak sekali, dan hanya dengan bukti baru (ADR-0018). Bila tetap tereskalasi, catat lognya dan teruskan ke pengguna.
- Kasus: [Perbaikan review riwayat tap](../sessions/2026-11-01-perbaikan-riwayat-tap.md).
