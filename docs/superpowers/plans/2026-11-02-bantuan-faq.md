# Layar Bantuan dan FAQ — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tab Kunci punya layar Bantuan dengan FAQ sepuluh topik, status kanal di iPhone ini, daftar perangkat didukung, penjelasan layar terkunci, dan laporan diagnostik tanpa rahasia.

**Architecture:** konten FAQ diambil dari katalog string lewat `HelpContent`; laporan diagnostik dibuat fungsi murni `DiagnosticsReport` dari input tanpa id/kunci; `HelpView` menampilkan semuanya dalam sheet dari tab Kunci.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, String Catalog.

**Spec:** `docs/superpowers/specs/2026-11-02-bantuan-faq-design.md` (ADR-0048).

## Global Constraints

- **Bahasa:** semua teks ID dan EN di `Packages/Sources/ANFeatures/Resources/Localizable.xcstrings` (format berkas dipertahankan: indent 2, `": "`).
- **Teks:** kunci `help.*` tanpa "NFC", "HCE", "APDU". Nama kanal memakai "Tempel ke pembaca" dan "Bluetooth".
- **Laporan diagnostik:** tidak pernah memuat `cred_id`, id kartu server, `device_id`, token, rahasia, identitas kartu, nama kartu, atau URL layanan.
- **Tanpa jaringan:** Bantuan tidak menghubungi jaringan.
- **UI:** mengikuti `docs/design-system/anastrophe/pages/ios-app.md`.
- **Commit:** pesan berbahasa Indonesia dan diakhiri `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Hanya di `feat/r1-scaffold`, tanpa push.
- **Verifikasi:**
  - host: `swift test --package-path Packages`;
  - simulator: `cd Packages && xcodebuild -scheme AnastropheKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`;
  - build app: Debug dan Release;
  - dokumen: `python3 scripts/docs/check_docs.py .` exit 0.

## Review Focus

1. **Laporan tanpa rahasia:** banyak kartu, kartu tanpa kanal, dan store kosong. Test: Task 2 `laporanTanpaRahasia`, `laporanTanpaKartu`.
2. **Jawaban FAQ akurat** terhadap perilaku R1. Test: Task 1 `faqMencakupSepuluhTopik` + ulasan isi di review akhir.
3. **Status kanal** mengikuti kelayakan. Test: Task 1 `statusKanalMengikutiKelayakan`.
4. **AX5:** teks panjang terbaca. Bukti: screenshot AX5 di Task 3.
5. **Tanpa jargon** di kedua bahasa. Test: Task 1 `teksBantuanTanpaJargon`.

---

### Task 1: Konten FAQ, status kanal, dan string

**Files:**
- Create: `Packages/Sources/ANFeatures/Help/HelpContent.swift`, `Packages/Tests/ANFeaturesTests/HelpContentTests.swift`
- Modify: `Packages/Sources/ANFeatures/Resources/Localizable.xcstrings`, `Packages/Tests/ANFeaturesTests/StringCatalogTests.swift`

**Interfaces:**
- Produces:
  - `enum HelpTopic: String, CaseIterable, Identifiable { case devices, cards, limit, offline, lockedScreen, delete, members, sharing, transfer, lost }` dengan `var question: String` dan `var answer: String` dari `help.faq.<rawValue>.question/.answer`.
  - `enum HelpContent { static func status(for availability: ChannelAvailability?) -> String }`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `faqMencakupSepuluhTopik`: `HelpTopic.allCases.count == 10`, setiap `question`/`answer` tidak kosong dan bukan kunci mentah.
  - `statusKanalMengikutiKelayakan`: `.available` → `help.channel.available`; `.bluetoothOff` → `help.channel.bluetooth_off`; `.bluetoothUnauthorized` → `help.channel.bluetooth_denied`; `.notEligible`/`.regionBlocked`/`.unsupportedDevice`/`.entitlementMissing`/nil → `help.channel.unavailable`.
  - `teksBantuanTanpaJargon` (StringCatalogTests): ada ≥ 25 kunci `help.*`, tanpa NFC/HCE/APDU.
- [ ] **Step 2: Jalankan** `swift test --package-path Packages --filter 'HelpContent|teksBantuanTanpaJargon'`. Expected: FAIL.
- [ ] **Step 3: Implementasikan** `HelpContent.swift` dan string ID/EN:
  - **Topik FAQ:** isi jawaban mengikuti spec §Tujuan 2–7.
  - **Judul bagian:** `help.title`, `help.section.channels`, `help.section.faq`, `help.section.devices`, `help.section.diagnostics`, `help.section.support`.
  - **Perangkat:** `help.devices.list`, `help.devices.note`.
  - **Status kanal:** `help.channel.*`.
  - **Diagnostik:** `help.diagnostics.share`, `help.diagnostics.note`.
  - **Dukungan:** `help.support.text`.
  - **Toolbar:** `keys.help`.
- [ ] **Step 4: Jalankan host.** Expected: PASS, termasuk `setiapStringPunyaIDdanEN` dan `setiapKunciYangDipakaiAdaDiKatalog`.
- [ ] **Step 5: Commit** `feat(app): konten FAQ Bantuan dan status kanal (FR-60, FR-02, FR-27)`.

### Task 2: Laporan diagnostik tanpa rahasia (FR-63)

**Files:**
- Create: `Packages/Sources/ANFeatures/Help/DiagnosticsReport.swift`, `Packages/Tests/ANFeaturesTests/DiagnosticsReportTests.swift`
- Modify: `Packages/Sources/ANFeatures/AppServices.swift` (`func diagnosticsInput() async -> DiagnosticsInput`)

**Interfaces:**
- Produces:
  - `struct DiagnosticsInput: Sendable`, dengan field `appVersion: String`, `build: String`, `osVersion: String`, `locale: String`, `channels: [ChannelKind: ChannelAvailability]`, `serviceConfigured: Bool`, dan `cards: [CardSummary]`.
  - `struct CardSummary: Sendable { status: CardStatus; channels: [ChannelKind]; notAfter: Date? }` (tanpa id).
  - `enum DiagnosticsReport { static func text(_ input: DiagnosticsInput) -> String }`.
  - `AppServices.diagnosticsInput()`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `laporanMemuatBidangYangDiizinkan`: versi/build/OS/bahasa, baris kanal `nfcHCE`/`ble` dengan status, `layanan: ya`, jumlah kartu, dan status/kanal/tanggal per kartu.
  - `laporanTanpaRahasia`: services in-memory berisi kartu dengan `cred_id` 0x5E…, record dengan `serverCardID`, token status, dan id perangkat. Teks dari `services.diagnosticsInput()` tidak memuat hex `cred_id`, `serverCardID`, `deviceID()`, hex token, nama kartu, maupun base URL.
  - `laporanTanpaKartu`: tanpa kartu → `kartu: 0`.
- [ ] **Step 2: Jalankan** `swift test --package-path Packages --filter DiagnosticsReport`. Expected: FAIL.
- [ ] **Step 3: Implementasikan.**
  - `diagnosticsInput()` membaca `Bundle.main` (`CFBundleShortVersionString`, `CFBundleVersion`; "?" bila tidak ada), `ProcessInfo.operatingSystemVersionString`, `Locale.current.identifier`, `availability()`, `apiBaseURL != nil`, dan `cards.all()`, lalu dipetakan ke `CardSummary`.
  - Store yang gagal menghasilkan kartu kosong.
  - Teks laporan berbentuk baris `kunci: nilai` berbahasa netral (label dalam ID, tidak dilokalisasi, *keputusan builder* agar dukungan selalu membaca format yang sama).
- [ ] **Step 4: Jalankan host.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(app): laporan diagnostik tanpa rahasia (FR-63)`.

### Task 3: `HelpView` dan pintu masuk di tab Kunci

**Files:**
- Create: `Packages/Sources/ANFeatures/Help/HelpView.swift`
- Modify:
  - `Packages/Sources/ANFeatures/KeysView.swift`: toolbar `questionmark.circle`, sheet, demo `help`.
  - `App/AppEnvironment.swift`: `demoScreen` menerima `help`.

**Interfaces:**
- Consumes: `HelpTopic`, `HelpContent.status(for:)`, `DiagnosticsReport.text`, `AppServices.diagnosticsInput()`, `AppServices.availability`.

- [ ] **Step 1: Implementasikan** `HelpView(services:)`:
  - `List` dengan bagian kanal (dua baris: `channel.tap` dan `channel.ble` + status).
  - FAQ: `DisclosureGroup` per `HelpTopic`.
  - Perangkat: teks `help.devices.list` + catatan.
  - Diagnostik: `ShareLink(item: laporan)`, yang dimuat di `.task`.
  - Dukungan: teks.
  - Toolbar: tombol Selesai.
- [ ] **Step 2: Sambungkan toolbar Kunci** dengan `Label(localized("keys.help"), systemImage: "questionmark.circle")` di semua build. Di iOS penempatannya `.topBarLeading`; Lab DEBUG tetap ada.
- [ ] **Step 3: Build app Debug dan Release.** Expected: BUILD SUCCEEDED.
- [ ] **Step 4: Ambil screenshot simulator** dengan `-ANDemo -ANDemoScreen help` dalam ID, EN, dan AX5 (`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`). Expected: semua bagian terbaca, tanpa teks terpotong.
- [ ] **Step 5: Jalankan host dan simulator, lalu commit** `feat(app): layar Bantuan dari tab Kunci (FR-60, FR-02, FR-27, FR-63)`.

### Task 4: Dokumen

**Files:**
- Modify: `docs/SDD.md` (§5.9 Bantuan, revisi), `docs/QA_SUITE.md` (hasil TC-UX-08, TC-PRIV-06; TC-UX-11 daftar perangkat FR-02 + layar terkunci FR-27; §14)

- [ ] **Step 1: Perbarui dokumen** dan jalankan `check_docs` (exit 0).
- [ ] **Step 2: Commit** `docs: layar Bantuan dan FAQ (SDD, QA TC-UX-08/11, TC-PRIV-06)`.
