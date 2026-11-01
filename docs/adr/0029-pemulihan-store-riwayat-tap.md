# ADR-0029: Store riwayat tap dibuat ulang hanya bila rusak atau tak termigrasi

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** FR-30, TC-UPG-02, SDD §5.3

## Konteks

`AppServices.live()` membuka store riwayat tap dengan `try`. Bila pembukaan gagal, app jatuh ke mode "penyimpanan tidak tersedia" tanpa kartu, padahal store kartu dan Keychain sehat (temuan review akhir I1). Probe review: 8 KB data acak di `taps.store` membuat `SwiftDataTapHistoryStore.init` melempar `SwiftDataError.loadIssueModelContainer`. Perubahan skema `TapEntity` yang gagal dimigrasi otomatis atau downgrade build akan memicu hal yang sama.

`SwiftDataError` menyembunyikan galat Cocoa di dalamnya, sehingga jenis galat dibaca lewat API publik Core Data. Probe di host:

| Kasus | `metadataForPersistentStore` | Klasifikasi |
|---|---|---|
| Berkas bukan database (SQLite 26) | galat Cocoa 259 (`fileReadCorruptFile`) | rusak |
| Skema store tidak cocok dengan model | metadata terbaca, `isConfiguration(…compatibleWithStoreMetadata:)` = false | tak termigrasi |
| Berkas tidak bisa dibaca (izin) atau tidak ada | galat Cocoa 260 | lain |
| Store sehat | metadata terbaca, cocok | lain |

## Keputusan

Pembukaan riwayat tidak pernah gagal:

1. Coba buka store SwiftData seperti biasa.
2. Bila gagal, baca metadata store. Store **dibuat ulang sekali** hanya bila berkasnya rusak (galat 259) atau skemanya tidak cocok dengan model saat ini. Direktori `TapHistory` hanya berisi riwayat, jadi seluruh direktori dihapus.
3. Galat lain, atau pembuatan ulang yang gagal, memakai `InMemoryTapHistoryStore` untuk sesi itu tanpa menghapus berkas apa pun. Peluncuran berikutnya mencoba lagi.

## Konsekuensi

- Kartu dan presentasi tidak lagi bergantung pada log riwayat.
- Riwayat lama yang memang tidak terbaca hilang sekali, lalu pencatatan berlanjut tanpa reinstall.
- Riwayat yang masih terbaca tidak dihapus, termasuk saat berkas terkunci proteksi data atau tidak bisa dibuka karena izin.
- Sisa risiko: bila migrasi gagal karena sebab lain (misalnya disk penuh) pada store yang skemanya memang perlu dimigrasi, store tetap dibuat ulang.
- Perubahan skema `TapEntity` berikutnya tetap wajib diuji migrasinya (TC-UPG-02). Pemulihan ini hanya jaring pengaman.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** How should the iOS app recover when the local tap-history store cannot be opened at launch?
- **Prioritas yang diberikan:** membuka pintu tidak bergantung pada log riwayat; riwayat kembali persisten tanpa reinstall; riwayat yang masih terbaca tidak dihapus; kode kecil dan teruji di host.
- **Hasil:** `reset_on_corruption_only` · confidence **0.87** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-01-round13.input.json`](jev-log/2026-11-01-round13.input.json), [`jev-log/2026-11-01-round13.output.json`](jev-log/2026-11-01-round13.output.json)

| Kandidat | Probabilitas |
|---|---|
| `reset_on_corruption_only` | 0.89 |
| `reset_then_fallback` | 0.1 |
| `fallback_in_memory` | 0.01 |
