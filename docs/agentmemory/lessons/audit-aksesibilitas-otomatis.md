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
- Kasus: [Audit aksesibilitas](../sessions/2026-11-02-audit-aksesibilitas.md).
