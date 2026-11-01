# Anastrophe — Kartu Akses NFC untuk iPhone

Anastrophe adalah aplikasi iOS untuk menyimpan **hingga 8 kartu akses gedung** (apartemen, kantor, kampus, lift, parkir) di iPhone dan membuka akses dengan menempelkan iPhone ke pembaca kartu. Fiturnya mengacu pada [Samsung Wallet NFC Access Card](https://www.samsung.com/hk_en/support/mobile-devices/nfc-access-card/).

> **Penting.** iPhone **tidak bisa meng-clone** kartu akses fisik seperti Samsung: UID iPhone diacak per tap, dan app hanya dapat mengemulasikan ISO 7816-4 lewat AID terdaftar. Anastrophe memakai **kredensial digital baru yang disetujui operator gedung**, lewat tiga kanal:
> - **W** — Apple Wallet Access pass (Aliro), rilis R2
> - **N** — NFC dalam aplikasi (`CredentialSession` di wilayah eligible / `CardSession` di EEA)
> - **B** — BLE dalam aplikasi, berlaku di semua wilayah termasuk **Indonesia**
>
> Indonesia **belum** eligible untuk NFC dalam aplikasi (dicek live 2026-11-01). Lihat [ledger bukti](docs/research/RESEARCH_EVIDENCE.md).

## Status

Dokumen v2 (2026-11-01). Keputusan desain diambil lewat lapisan keputusan **JEV** ([ADR](docs/adr/README.md)). **Satu keputusan menunggu Anda:** [ADR-0017](docs/adr/0017-entitas-hukum-entitlement.md), entitas hukum di wilayah eligible untuk entitlement NFC & SE. ADR-0014 (topologi backend) dan ADR-0019 (strategi pindai BLE) sudah diterima.

## Dokumen

| Dokumen | Isi |
|---|---|
| [docs/PRD.md](docs/PRD.md) | Requirement produk: strategi kanal, 67 FR, 32 NFR, user story, roadmap, risiko |
| [docs/SDD.md](docs/SDD.md) | Desain: arsitektur, kanal W/N/B, protokol ANP/1, backend, reader, keamanan, privasi |
| [docs/QA_SUITE.md](docs/QA_SUITE.md) | Strategi uji, matriks perangkat/reader, 180+ kasus uji, Gherkin, traceability |
| [docs/adr/](docs/adr/README.md) | 18 ADR, termasuk catatan keputusan JEV (probabilitas, cek requirement) dan log mentah |
| [docs/research/RESEARCH_EVIDENCE.md](docs/research/RESEARCH_EVIDENCE.md) | Ledger bukti metode REA (E01–E30; observation/inference/unknown) |
| [GLOSSARY.md](GLOSSARY.md) | Bahasa domain bersama |
| [docs/design-system/anastrophe/](docs/design-system/anastrophe/MASTER.md) | Design system (UI/UX Pro Max): MASTER untuk portal web, [`pages/ios-app.md`](docs/design-system/anastrophe/pages/ios-app.md) untuk app iOS |

## Struktur repo

```
.
├── CLAUDE.md                     # aturan kerja agen & kontributor
├── GLOSSARY.md                   # bahasa domain (skill domain-modeling)
├── Anastrophe.xcodeproj          # app shell iOS (target Anastrophe, iOS 26.0)
├── App/                          # @main + aset app
├── Packages/                     # Swift package lokal: modul AN* (SDD §5.1) + unit test
├── docs/
│   ├── PRD.md · SDD.md · QA_SUITE.md
│   ├── adr/                      # NNNN-slug.md + jev-log/ (input/output JEV)
│   ├── design-system/anastrophe/ # MASTER.md + pages/ios-app.md
│   ├── research/                 # ledger bukti REA
│   └── superpowers/plans/        # rencana implementasi (mis. R1 tracer bullet)
├── scripts/docs/                 # pengecek konsistensi dokumen & render Mermaid
└── .claude/
    ├── settings.json             # plugin proyek: superpowers, mattpocock-skills
    └── skills/                   # reverse-engineer-anything (REA), ui-ux-pro-max
```

## Tooling & skill

| Alat | Jenis | Scope | Fungsi di proyek ini |
|---|---|---|---|
| **JEV** (`@jkudish/jev-mcp`, TypeSafe) | MCP server | Lokal (key di `~/.claude.json`, **bukan** di repo) | Lapisan keputusan: `jev_decide` untuk ADR, `jev_verify` untuk cek fakta dokumen, `jev_gate` untuk gerbang rilis |
| **agentmemory** (`@agentmemory/mcp`) | MCP server + daemon lokal (`localhost:3111`) | User | Memori lintas sesi (keputusan, konteks proyek) |
| **claude-mem** | Plugin + worker lokal (`127.0.0.1:37701`) | User | Menangkap observasi sesi otomatis; provider lokal, cloud sync **off** |
| **superpowers** | Plugin | Proyek | Disiplin kerja: brainstorming → spec → plan, TDD, verifikasi sebelum selesai, git hygiene |
| **mattpocock-skills** | Plugin | Proyek | `domain-modeling` (glosarium/ADR), `to-tickets`, `grill-with-docs`, `tdd`, dll. |
| **ui-ux-pro-max** | Skill | Proyek | Design system & aturan UX/aksesibilitas (SwiftUI) |
| **reverse-engineer-anything** (REA) | Skill | Proyek | Metodologi riset berbasis bukti; analisis biner hanya untuk target sah (SDD §17) |

Plugin dan server MCP baru aktif setelah **restart Claude Code** (atau `/mcp` untuk reconnect).

## Build & test

Prasyarat: Xcode 27.2+ (SDK iOS 27.2), simulator iPhone 17 Pro.

```bash
swift test --package-path Packages                                   # unit test di host
(cd Packages && xcodebuild -scheme AnastropheKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test)    # unit test di simulator iOS
xcodebuild -project Anastrophe.xcodeproj -scheme Anastrophe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build     # build app
```

Kanal N (`CardSession`/`CredentialSession`) butuh entitlement Apple yang belum dimiliki (PRD D1/D7). Sampai entitlement itu ada, kanal N selalu tertahan di gating dan app tidak crash. Kanal B dan seluruh logika protokol bisa dikembangkan dan diuji sekarang. Rencana kerja berikutnya: [`docs/superpowers/plans/2026-11-01-r1-tracer-bullet.md`](docs/superpowers/plans/2026-11-01-r1-tracer-bullet.md).

## Cek dokumen

```bash
python3 scripts/docs/check_docs.py .        # traceability FR/NFR → TC, ID, tautan
python3 scripts/docs/check_mermaid.py . /tmp/mmd <path-mmdc> <puppeteer.json>   # render semua diagram
```

## Langkah berikutnya

1. Putuskan ADR-0017 (entitas); ini tidak menghalangi rencana [R1 tracer bullet](docs/superpowers/plans/2026-11-01-r1-tracer-bullet.md) sisi app, tetapi menghalangi entitlement NFC.
2. M0: survei reader gedung pilot, kontrak 2 operator pilot, ajukan entitlement NFC & SE, kirim kuesioner Apple Wallet Access Program.
3. Setelah restart: jalankan `/setup-matt-pocock-skills`, lalu `/to-tickets` untuk memecah PRD/SDD menjadi tiket *tracer-bullet* R1.
