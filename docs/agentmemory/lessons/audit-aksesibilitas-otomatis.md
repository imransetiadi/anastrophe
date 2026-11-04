---
type: lesson
project: anastrophe
date: 2026-11-02
tags: [aksesibilitas, xcuitest, ios26, proses]
---
# Batas audit aksesibilitas otomatis di iOS 26

- **`performAccessibilityAudit` tidak melihat semuanya.** Nilai `LabeledContent` (satu elemen gabungan per baris), placeholder field, `confirmationDialog`, dan chevron tidak diaudit kontrasnya. Lengkapi dengan lint sumber (pola warna sistem) dan pengukuran piksel screenshot.
- **Ambang kontras audit persis WCAG 2.x** (kalibrasi di 3x): "failed" di bawah 3:1, "nearly passed" 3,5–4,49, tidak ditandai mulai 4,61. Isu pada elemen bertoken biasanya berpenyebab struktural (permukaan, elemen gabungan, bilah kaca), bukan antialiasing.
- **Mode gelap harus diverifikasi sebelum audit.** Di run RED pertama, semua screenshot "gelap" ternyata terang, sehingga hasil gelap run itu tidak sah.
- **Lembar setengah tinggi iOS 26 tampil ±96 %.** Kontrol 44 pt terukur ±42 pt di layar, jadi di lembar itu dipakai `.controlSize(.large)` (50 pt).
- **`TextField` SwiftUI selalu setinggi teksnya.** Bingkai atau padding di luarnya tidak memperbesar elemen aksesibilitas maupun area ketuk; `UITextField` dengan padding di dalam field memperbaikinya.
- **`XCUIDevice` dan simulator berbagi status.** Uji paralel di satu mesin yang sangat sibuk (load > 200) memberi timeout palsu; batasi agen paralel.
- **Audit Dynamic Type memindah posisi gulir.** Sesudah audit, daftar panjang di AX5 bisa kembali ke dekat puncak isi: Bantuan melompat dari posisi 7.301 pt ke ±1.700 pt. Posisi harus dipulihkan dengan seretan terukur sebelum gulir berikutnya, karena tanpa itu sisa isi tidak pernah diaudit. Seretan mundur yang panjang di lembar bisa menutup lembar itu, jadi seretan mundur dibatasi 100 pt.
- **Gulir pakai seretan tanpa momentum.** `swipeUp()` bisa melompati lebih dari satu layar isi AX5. Kesinambungan halaman dicek dengan label yang sama per kemunculan, karena halaman daftar kartu AX5 tidak punya label unik bersama.
- **Audit bisa habis waktu terus-menerus di satu posisi.** Riwayat AX5 halaman 2 di iPhone 17e gagal (-56) di setiap ulangan pada tiga run. Menggeser isi 48 pt lalu mengaudit ulang membuatnya selesai.
- **Positif palsu di AX5 juga ada.** `dynamicType` "partially unsupported" muncul pada baris daftar SwiftUI yang screenshot elemennya, dari audit itu sendiri, menunjukkan teks utuh membesar. `elementDetection` menandai isi pudar di bawah kaca bilah. Buktikan dengan screenshot elemen sebelum mengecualikan.
- **Xcode memangkas result bundle** di `DerivedData/Logs/Test`. Bukti yang perlu disimpan diekspor segera atau dijalankan dengan `-resultBundlePath`.
- Kasus: [Audit aksesibilitas](../sessions/2026-11-02-audit-aksesibilitas.md), [lanjutan GREEN](../sessions/2026-11-04-audit-aksesibilitas-green.md).
