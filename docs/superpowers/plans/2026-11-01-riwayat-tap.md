# Riwayat Tap Lokal 30 Hari (FR-30) — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Detail kartu menampilkan riwayat tap lokal 30 hari terakhir (FR-30, TC-MGT-01). Riwayat disimpan di perangkat saja (SDD §5.3) dan dihapus bersama kartunya.

**Architecture:** `TapHistoryStore` (ANStorage, SwiftData terpisah dengan proteksi file `.complete` dan tanpa backup), dekorator `RecordingLauncher` (ANFeatures) yang mencatat event `granted`/`denied` dari launcher mana pun, `KeysViewModel` yang memuat dan memangkas riwayat, serta bagian "Riwayat tap" di detail kartu.

**Spec:** PRD FR-30; SDD §5.3 (penyimpanan lokal); QA TC-MGT-01. Tidak ada keputusan desain baru: semua mengikuti SDD.

## Global Constraints

- Yang dicatat hanya transaksi dengan reader: `granted` atau `denied(reason)`. Batal, timeout, reader di luar jangkauan, dan kanal tidak tersedia tidak dicatat.
- Data: id, ID kartu lokal, waktu, kanal, hasil, dan alasan tolak. Tanpa lokasi, tanpa identitas reader.
- Retensi 30 hari: dipangkas saat daftar dimuat. Riwayat kartu dihapus saat kartunya dihapus (FR-31).
- String ID/EN; teks tanpa istilah "NFC".

## Review Focus

1. **Event non-transaksi tercatat.** `cancelled`/`timedOut`/`readerOutOfRange` tidak boleh menambah riwayat. Test: `batalTidakDicatat`.
2. **Riwayat bocor setelah kartu dihapus.** Test: `hapusKartuMenghapusRiwayat`.
3. **Retensi.** Entri > 30 hari tidak tampil dan terhapus. Test: `riwayatLebihDariTigaPuluhHariDipangkas`.

### Task 1: Store, dekorator, model, UI

- [x] Test gagal: `SwiftDataTapHistoryStoreTests` (tambah/urut terbaru dulu, pangkas, hapus per kartu), `RecordingLauncherTests` (granted, denied dengan alasan, `batalTidakDicatat`), `KeysViewModel` (`riwayatLebihDariTigaPuluhHariDipangkas`), `hapusKartuMenghapusRiwayat`.
- [x] Implementasikan; bagian Riwayat di `CardDetailView`; QA TC-MGT-01; `swift test` + simulator → LULUS; screenshot demo.
