---
type: session
project: anastrophe
date: 2026-11-02
status: selesai-dengan-keterbatasan
tags: [backend, app, siklus-hidup, status, fr-38, fr-51]
---
# 2026-11-02 — Siklus hidup kartu oleh operator dan status kartu di app

Keputusan: [ADR-0036](../decisions/ADR-0036-fokus-siklus-hidup-kartu-operator.md) (fokus), [ADR-0037](../decisions/ADR-0037-token-baca-status-kartu.md) (token baca status), dan [ADR-0038](../decisions/ADR-0038-cegah-pembatalan-tindakan-operator.md) (terbuka, menunggu pengguna). Spesifikasi: `docs/superpowers/specs/2026-11-01-siklus-hidup-kartu-design.md`; rencana: `docs/superpowers/plans/2026-11-01-siklus-hidup-kartu.md`.

## Perubahan

- **Store (migrasi 0010):** `card_instances.status_token_hash` (SHA-256 saja) dan `denylist_entries`.
  - Transisi oleh operator mengunci instance dan memeriksa status asal; kredensial mengikuti status. Audit `card.suspended`, `card.resumed`, `card.revoked {reason, credentials}`.
  - Hapus kartu dan pencabutan operator berbagi helper, jadi keduanya mengisi denylist sampai sertifikatnya kedaluwarsa.
- **HTTP:** `GET /v1/cards/{id}/status` dengan token baca status sebagai bearer.
  - Semua kegagalan dijawab 404 `CARD-NOT-FOUND` yang identik, dengan `Cache-Control: no-store`.
  - Provisioning hanya memasang hash bila belum ada; `:renew` boleh menggantinya.
- **CLI:** `list` (id, status, asal, kanal; tanpa identitas), `suspend`, `resume`, `revoke --reason <kode>`.
- **App:** `StatusToken` dan `KeychainStatusTokenStore` (`afterFirstUnlockThisDeviceOnly`), serta `CardStatusRefresher` di layar Kunci (pemuatan pertama dan saat app kembali aktif, paling sering sekali per menit). Tidak ada prompt autentikasi.

## Bukti

- Go: 10 paket lulus. Swift: host 281 test, simulator 279 test.
- Uji mutasi tertangkap di setiap task: store 7, HTTP 6, CLI 4, token app 5, penyegar 4, fix pass 2.
- Lab simulator: `suspend` → Suspended → `resume` → Active → `revoke --reason hilang` → Revoked, dengan denylist dan audit lengkap; log API tanpa token.

## Review akhir dan perbaikan

- **C1:** pemegang kartu bisa membatalkan suspend/revoke dengan menghapus kartu yang ditangguhkan lalu mendaftar ulang, atau mendaftar ulang setelah revoke.
  - JEV `hold_pending_approval` 0,45, jadi dieskalasi ke pengguna (ADR-0038).
  - CLI mencetak peringatan; README, ADR-0036, dan QA mencatat keterbatasannya.
- **I1:** hash token bisa ditimpa lewat provisioning, yang hanya dilindungi id instance.
  - Server memasang hash hanya bila belum ada.
  - App menghapus token yang ditolak dan memakai ulang token yang sudah ada.
- **I2:** ID QA ganda. Kasus baru menjadi TC-MGT-15, dan `check_docs.py` kini menolak ID ganda.
- **M2** (dinaikkan): `:renew` membocorkan penangguhan kepada pemegang `cred_id`. Status kini diperiksa setelah bukti kepemilikan.
- **Celah pra-ada (declined to judge):** kredensial bisa diterbitkan untuk kanal yang belum diprovisikan lewat id instance dari `:challenge`. Tercatat di SDD dan menjadi prioritas tinggi di [backlog](../backlog.md).

Minor tertunda (M1, M3–M8, sisa M10): [backlog](../backlog.md) bagian Siklus hidup kartu.

`jev_gate` tereskalasi (composite 0,74, `test_gap`). Log: `docs/adr/jev-log/2026-11-02-siklus-hidup-gate.json`.
