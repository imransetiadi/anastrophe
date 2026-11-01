# Riwayat Tap: Minor Review dan Baris Status AX5 — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menutup minor tertunda dari review akhir riwayat tap (M1–M7) dan badge status yang terpotong di AX5.

**Architecture:** Perubahan kecil di `TapHistoryStore` (baris rusak dilewati, hapus entri yatim), `KeysViewModel.load()` (daftar dulu, riwayat menyusul, pembersihan yatim hanya bila kartu berhasil dimuat), `RecordingLauncher` (switch exhaustive), test yang lebih tajam, dan `LabeledContent` untuk baris Status.

**Tech Stack:** Swift 6, SwiftData, SwiftUI, Swift Testing.

**Spec:** temuan minor review akhir di `docs/agentmemory/sessions/2026-11-01-perbaikan-riwayat-tap.md`; FR-30; SDD §5.3; ADR-0029/0030; rencana induk `docs/superpowers/plans/2026-11-01-riwayat-tap.md`.

## Global Constraints

- Riwayat hanya di perangkat; tanpa nama reader, lokasi, atau identitas kartu (CLAUDE.md aturan 6).
- String UI dalam ID dan EN; teks presentasi tanpa istilah "NFC".
- `swift test` di host dan suite paket di simulator hijau di setiap task.

## Review Focus

1. **Gagal memuat kartu menghapus semua riwayat.** Pembersihan entri yatim dengan daftar kosong karena galat akan menghapus riwayat semua kartu. Test: Task 2, `gagalMuatKartuTidakMenghapusRiwayat`.
2. **Kartu lain ikut terhapus.** Hapus per kartu dan hapus yatim harus menyisakan kartu yang masih ada. Test: Task 1, `hapusYatimMenyisakanKartuYangAda`; Task 2, `hapusKartuMenghapusRiwayat` (dua kartu).
3. **Hasil tampil sebelum entri tersimpan.** Sheet memuat ulang riwayat saat ditutup, jadi entri harus sudah ada ketika hasil tiba. Test: Task 3, `entriTersimpanSebelumHasilDiteruskan`.
4. **Batal di background tidak sampai ke launcher asli.** Komposisi produksi memakai wrapper pencatat (aturan 4). Test: Task 3, `LifecycleTests` lewat `RecordingLauncher`.
5. **Satu baris dari build lain menyembunyikan riwayat.** Test: Task 1, `barisRusakDilewati`.

---

### Task 1: Store — baris rusak dilewati, hapus entri yatim (M3, M1, M5)

**Files:** Modify `Packages/Sources/ANStorage/TapHistoryStore.swift`; Test `Packages/Tests/ANStorageTests/TapHistoryStoreTests.swift`.

**Interfaces:** Produces `func removeAll(except cardIDs: Set<UUID>) async throws` di protokol `TapHistoryStore` (SwiftData dan in-memory).

- [ ] Test gagal: `barisRusakDilewati` (kanal tak dikenal di satu baris → hanya baris sehat yang kembali), `hapusYatimMenyisakanKartuYangAda` (SwiftData dan in-memory: kartu A, B dipertahankan, C terhapus); `pangkasDanHapusPerKartu` memakai kartu kedua yang tetap utuh.
- [ ] Implementasikan: `compactMap { try? $0.entry() }`; `removeAll(except:)`.

### Task 2: View model — daftar dulu, yatim dibersihkan (M2, M1, M5)

**Files:** Modify `Packages/Sources/ANFeatures/Keys/KeysViewModel.swift`; Test `KeysViewModelTests.swift`, `CardRemoverTests.swift`.

**Interfaces:** Consumes `removeAll(except:)`.

- [ ] Test gagal: `daftarTampilSebelumRiwayatSelesai` (store riwayat bergerbang: saat `entries` dipanggil, `isLoading` sudah false dan kartu tampil), `riwayatYatimDibersihkanSaatMuat`, `gagalMuatKartuTidakMenghapusRiwayat` (penjaga Review Focus 1); `hapusKartuMenghapusRiwayat` memakai kartu kedua.
- [ ] Implementasikan: `isLoading = false` setelah daftar; pemangkasan, pembersihan yatim (hanya bila `cards.all()` berhasil), lalu riwayat per kartu.

### Task 3: RecordingLauncher — switch exhaustive, urutan simpan, lifecycle (M4, M7, M6)

**Files:** Modify `Packages/Sources/ANFeatures/Present/RecordingLauncher.swift`; Test `RecordingLauncherTests.swift`, `LifecycleTests.swift`.

- [ ] Test: `bukanTransaksiTidakDicatat` (parameter: semua event non-transaksi, termasuk `.timedOut` dan `.unavailable`); `entriTersimpanSebelumHasilDiteruskan` (store bergerbang di `append`); `run()` tanpa sleep 50 ms dan komentar yang benar; helper `services(launcher:)` membungkus `SpyLauncher` dengan `RecordingLauncher`.
- [ ] Implementasikan: `switch` tanpa `default`. Uji mutasi: urutan teruskan-lalu-simpan dan `cancel()` yang tidak diteruskan harus menggagalkan test.

### Task 4: Baris Status di AX5

**Files:** Modify `Packages/Sources/ANFeatures/Keys/CardViews.swift`.

- [ ] Ganti `HStack` + `alignmentGuide` dengan `LabeledContent { StatusBadge } label: { Text }`, yang menumpuk label dan nilai pada ukuran aksesibilitas seperti baris lain.
- [ ] Verifikasi dengan screenshot demo AX5 (sebelumnya "Ac-tive") dan ukuran teks standar. Tidak ada infrastruktur snapshot, jadi tanpa unit test.
