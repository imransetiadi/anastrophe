# ADR-0001: Tidak meng-clone kartu fisik; terbitkan kredensial baru

- **Status:** Diterima (berbasis bukti; tidak memerlukan JEV)
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** Tim produk (berbasis bukti)
- **Rujukan:** I-02, I-11, O-A23, PRD NG1

## Konteks

Samsung meng-clone identitas kartu UID-based ke eSE (I-01). Di iPhone, API publik hanya mengemulasikan ISO 7816-4 lewat AID terdaftar; UID diacak per tap; MIFARE Classic tidak dapat diemulasikan (I-02, O-A23).

## Keputusan

Anastrophe **tidak** meng-clone UID/data sektor kartu fisik. Setiap kartu digital adalah **kredensial baru** (kunci asimetris) yang diterbitkan setelah operator gedung memetakannya ke hak akses kartu fisik.

## Konsekuensi

Reader harus mendukung protokol kredensial (ANP/1, Aliro, DESFire, atau Seos). Reader yang hanya membaca UID/CSN dan reader 125 kHz tidak didukung (PRD NG2).

