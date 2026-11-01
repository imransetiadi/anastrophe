---
type: lesson
project: anastrophe
date: 2026-11-01
tags: [swiftdata, core-data, pemulihan]
---
# SwiftDataError menyembunyikan galat Core Data

- `ModelContainer` yang gagal dibuka hanya melempar `SwiftDataError.loadIssueModelContainer`. Galat Cocoa aslinya ada di field privat, dan `NSError` hasil bridging tidak memuat `NSUnderlyingErrorKey`.
- Klasifikasi lewat API publik: `NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at:)`, lalu `NSManagedObjectModel.makeManagedObjectModel(for:)` dan `isConfiguration(withName:compatibleWithStoreMetadata:)`.
- Hasil probe di host macOS:

| Kasus | Hasil |
|---|---|
| Berkas berisi data acak | galat 259 (`fileReadCorruptFile`) |
| Berkas tanpa izin baca, atau tidak ada | galat 260 |
| Skema store tidak cocok dengan model | metadata terbaca, `compatible = false` |
| Store sehat | metadata terbaca, `compatible = true` |
| Berkas kosong | SwiftData membuka normal |

- Dipakai di [ADR-0029](../decisions/ADR-0029-pemulihan-store-riwayat-tap.md).
