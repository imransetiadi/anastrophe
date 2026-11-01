# ADR-0005: Security code 6 digit diverifikasi server dengan rate-limit

- **Status:** Diterima (berbasis bukti; tidak memerlukan JEV)
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** Tim produk (berbasis bukti)
- **Rujukan:** O-S05, O-S12, O-S13, NFR-S04, NFR-S05

## Konteks

Samsung memakai security code untuk anggota (O-S12). Kode yang diverifikasi di perangkat rentan brute-force offline.

## Keputusan

Security code 6 digit disimpan sebagai hash Argon2id di server dan diverifikasi server-side. Rate-limit: 5 salah → terkunci 30 menit; 10 salah/24 jam → terkunci + notifikasi pemilik. Kode lemah ditolak.

## Konsekuensi

Bergabung sebagai anggota memerlukan koneksi online (wajar, karena provisioning juga online).

