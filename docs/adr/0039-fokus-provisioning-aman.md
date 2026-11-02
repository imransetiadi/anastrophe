# ADR-0039: Fokus berikutnya: provisioning kredensial hanya untuk perangkat yang memulai enrolment

- **Status:** Diterima
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-16, ADR-0026, ADR-0027, ADR-0037, SDD §8.4.1, §8.5 (catatan keamanan tracer), review akhir siklus hidup (*declined to judge*)

## Konteks

Review akhir rencana siklus hidup menemukan celah yang sudah ada sebelumnya, dan mereproduksinya dengan jawaban 200 berisi sertifikat:

- `POST /v1/enrollments/{id}/credentials` hanya dilindungi id card instance.
- `POST /v1/credentials/{cred}:challenge` tidak terautentikasi dan mengembalikan id itu kepada siapa pun yang tahu `cred_id`. ADR-0027 memakainya sebagai cadangan untuk hapus kartu.
- `cred_id` terlihat oleh reader yang lolos tanda tangan reader group dan tersimpan di infrastruktur gedung.

Akibatnya, orang dalam yang punya data reader bisa menerbitkan kredensial untuk kanal aktif yang belum diprovisikan pada instance ACTIVE milik orang lain, lalu mendapat zona kartu itu. API dev hanya mengaktifkan `ble`, jadi lab belum bisa dieksploitasi; dengan `ble` dan `nfcHCE` aktif, celah ini terbuka. App Attest belum bisa dipakai karena butuh tim pengembang Apple.

## Keputusan

Iterasi berikutnya menutup celah ini: provisioning kredensial harus membuktikan bahwa permintaannya berasal dari perangkat yang memulai enrolment, dan id instance dari `:challenge` tidak lagi cukup untuk provisioning. Mekanisme dipilih di spesifikasi lewat JEV.

## Konsekuensi

- Data reader atau log gedung tidak lagi cukup untuk mendapat kredensial pada kartu orang lain.
- Klien lama yang tidak membawa bukti baru tidak bisa memprovisikan. Saat ini hanya ada build lab, jadi tidak ada klien produksi yang terdampak.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Which focus should the next autonomous iteration build?
- **Prioritas yang diberikan:** keamanan dulu; tidak terblokir keputusan pengguna, perangkat keras, atau kemampuan Apple; bisa diverifikasi end-to-end di simulator; cukup satu rencana 3–5 task.
- **Hasil:** `secure_provisioning` · confidence **0.92** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round23.input.json`](jev-log/2026-11-02-round23.input.json), [`jev-log/2026-11-02-round23.output.json`](jev-log/2026-11-02-round23.output.json)

| Kandidat | Probabilitas |
|---|---|
| `secure_provisioning` | 0.93 |
| `hardening_backlog` | 0.03 |
| `faq_in_app` | 0.01 |
| `add_card_flow_mocked` | 0 |
| `none` | 0.02 |
