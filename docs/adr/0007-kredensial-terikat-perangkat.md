# ADR-0007: Kredensial terikat perangkat; pindah perangkat = re-provision

- **Status:** Diterima (berbasis bukti; tidak memerlukan JEV)
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** Tim produk (berbasis bukti)
- **Rujukan:** O-S15, O-W05, O-W09, NFR-S01

## Konteks

Samsung mengikat kartu ke perangkat (O-S15). Kunci di Secure Enclave/SE tidak dapat diekspor.

## Keputusan

Kredensial in-app tidak ikut backup/restore. Transfer ke iPhone baru menerbitkan kredensial baru dan mencabut yang lama. Kanal W memakai Easy Provisioning dari Apple.

## Konsekuensi

Pengguna perlu online saat pindah perangkat. Restore iCloud harus terdeteksi dan diarahkan ke alur transfer.

