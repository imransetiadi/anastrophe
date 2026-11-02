---
type: decision
project: anastrophe
date: 2026-11-02
adr: ADR-0058
jev: accept
confidence: 0.95
status: Diterima
---
# ADR-0058 — Cakupan token warna dan tint app `secondary`

- **Pilihan:** semua teks dan warna interaktif yang dikendalikan app memakai token:
  - `ANMutedText` untuk judul/catatan seksi dan deskripsi daftar kosong, `ANValueRow` untuk nilai baris, placeholder `ANTextField` bertoken `mutedForeground`;
  - "Hapus kartu" memakai `destructive`;
  - `.tint(ANColor.secondary)` paling luar di `KeysView`, ditambah aset AccentColor yang sama.
- **Bukti:** warna sistem iOS 26.5 gagal di mode terang (abu-abu 3,38–3,44:1, biru 3,52:1, merah 3,57:1, placeholder 1,72:1). Audit otomatis tidak melihat nilai `LabeledContent` maupun placeholder.
- **Penjaga:** lint `tanpaWarnaTeksSistem` dan `AccentColorAssetTests`.
- **Tetap sistem:** tombol merah `confirmationDialog` dan chevron `NavigationLink`, dicatat di QA §11.1.
- **Dokumen lengkap:** `docs/adr/0058-cakupan-token-warna-tint-app.md`. Sesi: [audit aksesibilitas](../sessions/2026-11-02-audit-aksesibilitas.md).
