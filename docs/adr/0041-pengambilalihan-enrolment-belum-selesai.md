# ADR-0041: Pengambilalihan enrolment yang belum selesai lewat id perangkat (terbuka)

- **Status:** Diusulkan — butuh keputusan manusia (eskalasi)
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-19, ADR-0017, ADR-0034, ADR-0035, ADR-0040, temuan review akhir provisioning aman I1

## Konteks

ADR-0040 menutup penerbitan kredensial lewat id instance dari `:challenge`. Namun aturan "hash diganti saat perangkat yang sama melanjutkan instance" juga berlaku untuk siapa pun yang mengirim `device_id` perangkat itu. Review akhir mereproduksinya terhadap PostgreSQL:

1. Perangkat D mendaftarkan kartu C, dan instance I berstatus `PROVISIONING` dengan hash milik D.
2. Penyerang mengirim enrolment dengan `device_id` D, kartu C, dan hash miliknya sendiri. Jawabannya 200 dengan instance I, dan hash I diganti.
3. Provisioning oleh D gagal 404, sedangkan penyerang mendapat sertifikat dengan zona kartu itu. Enrolment D berikutnya dijawab `ENR-DUPLICATE`.
4. Varian `PENDING_APPROVAL`: penyerang mendapat 200 sesaat setelah operator menyetujui.

Syaratnya: `device_id` (tidak rahasia; terlihat di audit), identitas mentah kartu fisik (butuh kartunya atau basis data kartu gedung) atau token undangan, dan waktu selama instance belum selesai. Ini bukan regresi, karena sebelum ADR-0040 masukan yang sama langsung memberi id instance. Autentikasi perangkat (App Attest) dan akun bergantung pada ADR-0017 yang belum diputuskan.

## Opsi

| Opsi | Inti | Probabilitas JEV |
|---|---|---|
| `first_writer_wins` | Server tidak pernah mengganti hash yang ada. App menyimpan rahasia di Keychain (`afterFirstUnlockThisDeviceOnly`) dan memakainya ulang saat melanjutkan dan saat promosi. Rahasia yang hilang membuat instance tertahan sampai `ABANDONED` (15 menit) atau ditolak operator. | 0.53 |
| `document_residual_risk` | Aturan sekarang dipertahankan; risiko sisa didokumentasikan, dan ditutup nanti oleh autentikasi perangkat. | 0.22 |
| `replace_with_old_secret` | Penggantian hash butuh rahasia lama sebagai bukti kesinambungan. | 0.22 |

## Hasil JEV

- **Hasil:** `first_writer_wins` · confidence **0.44** · escaped: false · tanpa requirement *contradicted*
- Confidence di bawah 0,60, jadi keputusan dieskalasi ke pengguna (ADR-0018) dan tidak diajukan ulang tanpa bukti baru.
- **Log mentah:** [`jev-log/2026-11-02-round26.input.json`](jev-log/2026-11-02-round26.input.json), [`jev-log/2026-11-02-round26.output.json`](jev-log/2026-11-02-round26.output.json)

## Rekomendasi penulis

`first_writer_wins`. Opsi ini menutup celah tanpa bergantung pada akun atau App Attest. Biayanya kecil dan terbatas: instance tertahan paling lama 15 menit bila rahasia hilang karena app dipasang ulang di tengah enrolment.

## Keadaan sampai diputuskan

- Aturan ganti saat melanjutkan tetap berlaku. `TestRahasiaDigantiSaatMelanjutkan` mengunci perilaku ini supaya perbaikan nanti mengubahnya dengan sengaja.
- ADR-0040, SDD §8.4.1, catatan keamanan tracer, glosarium, dan QA TC-ENR-19 menyebut risiko sisa ini. Backlog mencatatnya sebagai prioritas tinggi.
