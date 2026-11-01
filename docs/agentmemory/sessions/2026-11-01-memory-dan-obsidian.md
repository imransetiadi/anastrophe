---
type: session
project: anastrophe
date: 2026-11-01
status: selesai
tags: [dokumentasi, memori, obsidian]
---
# 2026-11-01 — Memory.md dan vault Obsidian

- Permintaan pengguna: berkas `Memory.md` yang menyimpan setiap perubahan, lalu diintegrasikan dengan Obsidian.
- `Memory.md` di root repo menjadi log kronologis (entri terbaru di atas, format `AREA-YYYY-MM-DD-HHMM - Judul (Status)`). Riwayat sebelum berkas ini diisi dari git.
- Vault ini (`docs/agentmemory/`) mengikuti pola proyek lain milik pengguna: `MOC.md`, `sessions/`, `decisions/`, `lessons/`. State per perangkat (`workspace*.json`, `cache`, `.trash/`) di-ignore; `.obsidian/app.json` di-commit agar tautan baru tetap Markdown relatif.
- Setiap perubahan berikutnya: entri `Memory.md`, catatan sesi di sini, dan pembaruan [MOC](../MOC.md), dalam commit yang sama.
