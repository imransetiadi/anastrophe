# ADR-0018: JEV sebagai lapisan pengambil keputusan desain

- **Status:** Diterima (berbasis bukti; tidak memerlukan JEV)
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** Tim produk (berbasis bukti)
- **Rujukan:** skill jev-mcp, skill grilling/domain-modeling

## Konteks

Pengguna menetapkan JEV (TypeSafe, via `jev-mcp`) sebagai *decision maker layer*. Pertanyaan desain disusun sebagai *design tree* (skill `grilling`) dan diputuskan per ronde *frontier*.

## Keputusan

Setiap keputusan desain terbatas (2–6 kandidat) diajukan ke `jev_decide` dengan bukti dari ledger riset, prioritas eksplisit, dan ≤ 3 requirement. Aturan status: confidence ≥ 0,80 → **Diterima**; 0,60–0,80 → **Diterima (provisional)**; < 0,60 atau escape → **eskalasi ke manusia**. Klaim di dokumen diverifikasi dengan `jev_verify`; penyelesaian pekerjaan diperiksa dengan `jev_gate`. Keputusan yang sama tidak diajukan ulang tanpa bukti baru.

## Konsekuensi

Keputusan dapat diaudit (probabilitas, cek requirement, model, biaya token). Kualitas keputusan bergantung pada kelengkapan bukti; keputusan berisiko tinggi tetap ditinjau manusia.

