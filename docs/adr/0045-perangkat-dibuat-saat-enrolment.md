# ADR-0045: Perangkat dibuat di dalam transaksi enrolment

- **Status:** Provisional (JEV 0,77), ditinjau di milestone M2
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-10, FR-11, FR-12, FR-40, FR-43, NFR-S03, ADR-0041, ADR-0043

## Konteks

Enrolment memanggil `lockDevice`, yang menolak `device_id` tak dikenal dengan 404 `ENR-NOT-FOUND` dan mengunci baris perangkat untuk menegakkan batas 8 kartu secara atomik. Sampai sekarang baris perangkat hanya dibuat oleh devseed, sehingga app produksi tidak bisa mendaftar.

Enrolment berjalan dalam satu transaksi, dan `Store.Idempotent` tidak meng-commit respons 4xx.

## Hasil JEV

- **Hasil:** `otomatis_saat_enrolment` · confidence **0.77** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round30.input.json`](jev-log/2026-11-02-round30.input.json), [`jev-log/2026-11-02-round30.output.json`](jev-log/2026-11-02-round30.output.json)

| Kandidat | Probabilitas | Requirement yang gagal |
|---|---|---|
| `otomatis_saat_enrolment` | 0.81 | — |
| `endpoint_registrasi` | 0.07 | baris tertinggal saat enrolment ditolak; endpoint publik tanpa batas |
| `operator_mendaftarkan` | 0.01 | butuh langkah operator |

## Keputusan

- **App:** membuat `device_id` UUID v4 acak dan menyimpannya di Keychain `afterFirstUnlockThisDeviceOnly`, sehingga tidak ikut ke perangkat lain.
- **Instal ulang:** penanda instalasi di Application Support (dikecualikan dari backup) mendeteksi instalasi baru, lalu `device_id` dibuat ulang (FR-43).
- **Server:** enrolment kartu dan undangan menjalankan `INSERT INTO devices (id) VALUES ($1) ON CONFLICT (id) DO NOTHING` sebelum `lockDevice`, di transaksi yang sama. Enrolment yang ditolak ikut me-rollback baris perangkat.

## Konsekuensi

- Tidak ada endpoint baru. Jumlah baris perangkat dibatasi jumlah kartu terdaftar dan undangan yang sah.
- App Attest (NFR-S03) nanti ditempel ke enrolment pertama yang membuat perangkat; keputusan ini tidak menutup jalan itu.
- ADR-0041 tidak berubah: `device_id` tetap acak dan tidak pernah ditampilkan atau di-log.
- **Status Provisional:** ditinjau di M2 bersama App Attest. Bila attestation per perangkat menuntut registrasi terpisah, `endpoint_registrasi` dipertimbangkan ulang dengan bukti baru.
