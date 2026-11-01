# ADR-0047: Batas permintaan perangkat tambahan yang menunggu per kartu (terbuka sebagian)

- **Status:** Tereskalasi (JEV 0,51). Diterapkan: batas 4 permintaan menunggu per kartu, yang menjadi inti bersama dua kandidat teratas (probabilitas gabungan 0,98). Kedaluwarsa permintaan menunggu masih menunggu pengguna.
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-17, FR-36, ADR-0015, ADR-0032, ADR-0034, ADR-0045

## Konteks

Review akhir alur Tambah Kartu (temuan #2) membantah klaim ADR-0045 bahwa jumlah baris perangkat "dibatasi kartu terdaftar dan undangan yang sah".

- **Bukti:** satu identitas kartu terdaftar dengan `device_id` acak baru di setiap permintaan menghasilkan 25 baris perangkat, 24 instance `PENDING_APPROVAL`, dan 25 audit `enrollment.started` dari 25 POST (probe reviewer).
- **Tanpa kedaluwarsa:** `PENDING_APPROVAL` tidak pernah kedaluwarsa, dan audit tidak bisa dipangkas.
- **Risiko operator:** antrean operator terisi permintaan yang tidak bisa dibedakan. Menyetujui permintaan yang salah menyerahkan kredensial.

## Hasil JEV

- **Hasil:** `batas_pending_per_kartu` · confidence **0.51** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round32.input.json`](jev-log/2026-11-02-round32.input.json), [`jev-log/2026-11-02-round32.output.json`](jev-log/2026-11-02-round32.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `batas_pending_per_kartu` | 0.58 | ketiganya *supported* |
| `batas_dan_kedaluwarsa` | 0.40 | ketiganya *supported* |
| `kedaluwarsa_pending` | 0 | tidak membatasi lonjakan |
| `catat_saja` | 0 | tidak membatasi; tidak bisa diuji |

## Keputusan

- **Diterapkan:** paling banyak `MaxPendingPerCard = 4` instance `PENDING_APPROVAL` per kartu fisik, sama dengan default batas anggota (FR-36). Batas ditegakkan di transaksi enrolment yang sudah mengunci baris kartu.
  - Permintaan berikutnya dijawab 409 `ENR-PENDING-LIMIT` ("Kartu ini sudah punya beberapa permintaan yang menunggu pengelola gedung. Hubungi pengelola gedung.") dan me-rollback baris perangkat.
  - Perangkat yang sudah menunggu tetap bisa melanjutkan permintaannya (ADR-0034). Permintaan yang ditolak operator tidak dihitung.
- **Menunggu pengguna:** kedaluwarsa `PENDING_APPROVAL`, misalnya 7 hari, karena mengubah semantik persetujuan operator.

Batas diterapkan meski confidence di bawah 0,60, dengan dua alasan. Pertama, kedua kandidat teratas sama-sama memuatnya. Kedua, batas ini menutup pertumbuhan tanpa batas yang dimunculkan unit ini sendiri (ADR-0045). Batas ini juga bisa dibatalkan dan hanya memengaruhi kartu yang sudah punya 4 permintaan menunggu.

## Konsekuensi

- Penyerang yang tahu satu identitas kartu bisa mengisi 4 slot permintaan kartu itu sampai operator menolaknya. Itu jauh lebih kecil daripada antrean tanpa batas, dan operator tetap melihat semua permintaan.
- CLI `list` belum menampilkan info perangkat untuk membedakan permintaan (backlog).
