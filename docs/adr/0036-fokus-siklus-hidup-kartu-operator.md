# ADR-0036: Fokus berikutnya: siklus hidup kartu oleh operator dan status kartu di app

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-38, FR-51, FR-62, SDD §8.4.3, ADR-0018, ADR-0033, ADR-0035

## Konteks

Enrolment lewat registri kartu dan undangan sudah selesai. Operator baru bisa menyetujui atau menolak perangkat tambahan (ADR-0032). Belum ada cara menangguhkan, memulihkan, atau mencabut kartu (FR-51, P0). App punya status Ditangguhkan dan Dicabut, tetapi tidak pernah menerimanya dari server (FR-38, P0), dan notifikasi push (FR-62) butuh APNs yang belum bisa dikonfigurasi.

Kandidat lain yang tidak terblokir adalah FAQ in-app (FR-60) dan perbaikan backlog. Alur "Tambah kartu" Release terblokir akun (FR-03), App Attest, dan iPhone fisik.

## Keputusan

Iterasi berikutnya membangun **siklus hidup kartu oleh operator** dan **status kartu di app**:

- CLI operator menangguhkan, memulihkan, dan mencabut card instance, dengan audit. Kredensial mengikuti status instance. Kredensial yang dicabut dicatat di `denylist_entries` untuk sinkron reader nanti.
- App mengetahui status kartunya dari server, sehingga kartu tampil Ditangguhkan atau Dicabut dan tidak bisa dipresentasikan.
- Cara app memperoleh status diputuskan di spesifikasi lewat JEV.

## Konsekuensi

- Operator punya tindakan dasar FR-51 sebelum portal admin ada.
- Status di app mengikuti server tanpa menunggu push.
- Sinkron denylist ke reader tetap menunggu keputusan reader uji (ADR-0022).

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Which focus should the next autonomous iteration build?
- **Prioritas yang diberikan:** P0 yang belum ada dan tidak terblokir keputusan pengguna, perangkat keras, atau kemampuan Apple; kebenaran keamanan; bisa diverifikasi end-to-end di simulator; cukup satu rencana 3–5 task.
- **Hasil:** `operator_lifecycle_status` · confidence **0.98** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round20.input.json`](jev-log/2026-11-01-round20.input.json), [`jev-log/2026-11-01-round20.output.json`](jev-log/2026-11-01-round20.output.json)

| Kandidat | Probabilitas |
|---|---|
| `operator_lifecycle_status` | 0.98 |
| `faq_in_app` | 0.02 |
| `hardening_backlog` | 0 |
| `add_card_flow_mocked` | 0 |
