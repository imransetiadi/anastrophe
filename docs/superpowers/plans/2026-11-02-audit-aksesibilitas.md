# Audit aksesibilitas app (NFR-A01, TC-UX-01–04/09) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** audit aksesibilitas yang bisa diulang dengan dua perintah:
- test host untuk kontras token dan lint anti-pola;
- target XCUITest yang mengaudit 16 keadaan layar demo di mode terang, gelap, dan AX5 (ID/EN).

Temuan audit diperbaiki, dan hasilnya dicatat untuk TC-UX-01–04 dan TC-UX-09.

**Architecture:**
- Token warna menjadi data (`ANColorToken`) yang diuji terhadap rumus WCAG dan tabel design system.
- Mode demo DEBUG mendapat enum `DemoScreen` untuk membuka setiap keadaan layar.
- Target `AnastropheUITests` memakai `performAccessibilityAudit` ditambah cek ukuran dan jarak target sentuh sendiri.
- Perbaikan yang berulang dijadikan gaya di `ANDesignSystem`.

**Tech Stack:** Swift 6, SwiftUI (iOS 26.0+), Swift Testing (test paket), XCTest/XCUITest (UI test), Xcode 27.2, simulator iOS 26.5 (iPhone 17e, iPhone 17 Pro).

**Spec:** `docs/superpowers/specs/2026-11-02-audit-aksesibilitas-design.md`

## Global Constraints

- Minimum iOS 26.0 (ADR-0006), Swift 6, tanpa paket pihak ketiga.
- String UI baru wajib ID dan EN di `Localizable.xcstrings`, tanpa istilah "NFC", "HCE", atau "APDU" (aturan 7).
- Mode demo hanya DEBUG. Build Release tidak berubah perilakunya. Layar presentasi tidak pernah dibuka otomatis dengan layanan live (aturan 4).
- Nilai token warna tidak diubah di unit ini. Token yang gagal kontras dieskalasi lewat ADR baru.
- Pengecualian audit hanya:
  - kontras elemen nonaktif (WCAG 1.4.3);
  - per elemen, dengan alasan tertulis.

  Tidak pernah per jenis audit.
- Target sentuh ≥ 44 × 44 pt (toleransi 0,5 pt); jarak antar elemen konten ≥ 8 pt.
- Dokumen dalam Bahasa Indonesia. `python3 scripts/docs/check_docs.py .` wajib 0 masalah sebelum commit, dan `python3 scripts/security/scan.py secrets` wajib exit 0.

## Review Focus

1. **Cek yang tidak bisa lulus kosong.** Cek target sentuh dan audit harus gagal bila penanda keadaan tidak muncul atau tidak ada satu pun elemen interaktif yang diperiksa (`test_cekTargetSentuhGagalTanpaElemen` di Task 4).
2. **Pengecualian tetap sempit.** Pengecualian kontras hanya berlaku untuk elemen yang benar-benar nonaktif (`isEnabled == false`), dan setiap pengecualian lain menyebut identifier atau label persis (Task 4, Step 6).
3. **Perbaikan memperbesar area ketuk, bukan hanya bingkai visual.** Cek ukuran memakai `frame` elemen aksesibilitas tombol itu sendiri, yang sama dengan area ketuk (Task 4).
4. **Dokumen dan kode tidak menyimpang.** Hex dan rasio di tabel §3 dibandingkan dengan kode (`tabelDesignSystemSamaDenganKode`, `rasioTabelSamaDenganHitungan` di Task 1).
5. **Demo tetap terkurung DEBUG.** `DemoScreen.live` tidak pernah memberi layar presentasi (`layarLiveTanpaPresentasi` di Task 3), dan build Release lulus tanpa simbol demo (Task 4, Step 9).

---

### Task 1: Token warna sebagai data dan test kontras (TC-UX-03)

**Files:**
- Modify: `Packages/Sources/ANDesignSystem/ColorTokens.swift`
- Modify: `Packages/Package.swift` (test target `ANDesignSystemTests`)
- Modify: `docs/design-system/anastrophe/pages/ios-app.md` (§3: baris `onAccent` sendiri)
- Create: `Packages/Tests/ANDesignSystemTests/ContrastTests.swift`

**Interfaces:**
- Produces:
  - `public struct ANColorToken: Sendable, Equatable` dengan `name: String`, `light: UInt32`, `dark: UInt32`, dan `color: Color`;
  - statis `background`, `foreground`, `card`, `mutedForeground`, `primary`, `secondary`, `accent`, `onAccent`, `success`, `warning`, `destructive`;
  - `static let all: [ANColorToken]` berisi 11 token itu.
  - `ANColor.<token>` tetap ada dan sama dengan `ANColorToken.<token>.color`.

- [ ] **Step 1: Tulis test yang gagal** di `ContrastTests.swift` (Swift Testing). Helper test `contrast(_ a: UInt32, _ b: UInt32) -> Double` memakai rumus WCAG 2.x:
  - kanal sRGB/255;
  - linear = c/12,92 bila c ≤ 0,04045, selain itu ((c+0,055)/1,055)^2,4;
  - L = 0,2126R + 0,7152G + 0,0722B;
  - rasio (L terang + 0,05)/(L gelap + 0,05).

  Test:
  - `rumusKontrasSesuaiWCAG`: `contrast(0x000000, 0xFFFFFF)` = 21 (±0,01); `contrast(0xFFFFFF, 0xFFFFFF)` = 1; `contrast(0x767676, 0xFFFFFF)` = 4,54 (±0,01).
  - `pasanganTeksLolosAA` (berargumen): pasangan berikut harus ≥ 4,5 di mode terang (`light`) dan gelap (`dark`):
    - `foreground`, `mutedForeground`, `secondary`, `success`, `warning`, `destructive`, dan `primary` di atas `background` dan di atas `card`;
    - `onAccent` di atas `accent`.
  - `#if os(macOS)` `tabelDesignSystemSamaDenganKode`: tabel §3 dibaca dari `docs/design-system/anastrophe/pages/ios-app.md` (root repo dari `#filePath`, empat tingkat ke atas). Untuk setiap baris dengan kolom pertama berawalan `` `nama` ``:
    - himpunan nama di tabel = himpunan `ANColorToken.all.map(\.name)`;
    - hex terang/gelap (`` `#RRGGBB` ``) = nilai kode.
  - `#if os(macOS)` `rasioTabelSamaDenganHitungan`: setiap anotasi rasio di kolom terakhir (`(a:1)` = sama untuk kedua mode, `(a:1 / b:1)` = terang / gelap) sama dengan hasil hitung yang dibulatkan satu desimal:
    - token `onAccent` dibandingkan dengan `accent`;
    - token lain dibandingkan dengan `background`.
- [ ] **Step 2: Jalankan dan lihat gagal.** Run: `swift test --package-path Packages --filter ANDesignSystemTests`. Expected: gagal kompilasi (`ANColorToken` belum ada) atau target test belum ada.
- [ ] **Step 3: Implementasi.**
  - `ANColorToken` dan `ANColor` dibangun darinya, dengan nilai hex persis seperti sekarang.
  - Test target di `Package.swift`: `.testTarget(name: "ANDesignSystemTests", dependencies: ["ANDesignSystem"])`.
  - Tabel §3: baris `accent` menjadi `` | `accent` (CTA) | `#A16207` | `#EAB308` | Tombol utama; teks di atasnya memakai `onAccent` | ``, lalu baris baru `` | `onAccent` | `#FFFFFF` | `#020617` | Teks di atas `accent` (4,9:1 / 10,5:1) | ``. Kalimat pembuka §3 menyebut test `ANDesignSystemTests` sebagai bukti.
- [ ] **Step 4: Jalankan dan lihat lulus.** Run yang sama. Expected: semua test lulus.
- [ ] **Step 5: Mutasi**, masing-masing harus menggagalkan test lalu dikembalikan:
  - `mutedForeground.light` = `0x94A3B8` → `pasanganTeksLolosAA` dan `tabelDesignSystemSamaDenganKode` gagal;
  - hex `secondary` gelap di dokumen diubah → `tabelDesignSystemSamaDenganKode` gagal;
  - rasio `success` di dokumen diubah → `rasioTabelSamaDenganHitungan` gagal.
- [ ] **Step 6: Commit** `feat(design): token warna sebagai data dengan test kontras WCAG dan tabel design system (TC-UX-03)`.

### Task 2: Lint anti-pola aksesibilitas (host)

**Files:**
- Create: `Packages/Tests/ANDesignSystemTests/AccessibilityLintTests.swift`

**Interfaces:**
- Consumes: target test `ANDesignSystemTests` dari Task 1.

- [ ] **Step 1: Tulis test** (`#if os(macOS)`) yang memindai semua `.swift` di `Packages/Sources` dan `App`:
  - `tanpaUkuranFontTetap`: tidak ada `.system(size:` maupun `fixedSize:`. `Font.custom(_:size:)` dan `relativeTo:` boleh, karena keduanya ikut Dynamic Type (design system §2; ruling sesudah builder check). Pencocok dipisah menjadi fungsi murni `fixedFontViolations(_ text: String) -> [String]` yang diuji dengan potongan literal (`fontTetapTerdeteksi`, `fontYangIkutDynamicTypeBoleh`).
  - `animasiHanyaDenganReduceMotion`: berkas yang memuat `withAnimation`, `.animation(`, `.transition(`, atau `.symbolEffect(` juga memuat `accessibilityReduceMotion`.
  - `lintMenemukanBerkas`: pemindaian menemukan ≥ 50 berkas Swift, agar lint tidak lulus karena path salah.
- [ ] **Step 2: Jalankan.** Run: `swift test --package-path Packages --filter AccessibilityLintTests`. Expected: lulus, karena kode saat ini bersih. Bukti RED diambil di Step 3.
- [ ] **Step 3: Mutasi (bukti RED).** Masing-masing harus gagal lalu dikembalikan:
  - `.font(.system(size: 17))` disisipkan di `HelpView.swift` → `tanpaUkuranFontTetap` gagal;
  - `withAnimation {}` disisipkan di `CardViews.swift` → `animasiHanyaDenganReduceMotion` gagal;
  - root repo dibuat salah satu tingkat → `lintMenemukanBerkas` gagal.
- [ ] **Step 4: Commit** `test(design): lint ukuran font tetap dan animasi tanpa Reduce Motion (NFR-A01)`.

### Task 3: Layar demo untuk audit dan identifier penanda

**Files:**
- Create: `Packages/Sources/ANFeatures/DemoScreen.swift`
- Modify:
  - `Packages/Sources/ANFeatures/AppServices.swift` (`demoScreen`, `demo(screen:)`)
  - `Packages/Sources/ANFeatures/KeysView.swift` (`openDemoScreen`, identifier)
  - `Packages/Sources/ANFeatures/AddCard/AddCardView.swift` (`AddCardRequest.demoScreen`, identifier)
  - `Packages/Sources/ANFeatures/Keys/CardViews.swift`, `Present/PresentationSheet.swift`, `Help/HelpView.swift` (identifier)
  - `App/AppEnvironment.swift`
- Test: `Packages/Tests/ANFeaturesTests/DemoScreenTests.swift`

**Interfaces:**
- Produces (semuanya `#if DEBUG`):
  - `public enum DemoScreen: String, CaseIterable, Sendable` dengan nilai mentah `lab`, `help`, `detail`, `presentation`, `bluetooth-denied`, `empty`, `detail-suspended`, `presentation-denied`, `add`, `add-code`, `add-confirm`, `add-invitation`, `add-done`, `add-pending`, dan `add-failed`;
  - `public static func live(_ raw: String?) -> DemoScreen?`: layar yang boleh dibuka dengan layanan live, yaitu hanya `.detail`, `.lab`, dan `.help` (tanpa presentasi, aturan 4); selain itu nil;
  - `var opensAddCard: Bool` (semua nilai berawalan `add`);
  - `var presentmentEvents: [PresentmentEvent]`;
  - `enum AddCardDemo { @MainActor static func apply(_ screen: DemoScreen, to model: AddCardModel) async }`.
- `AppServices.demoScreen` menjadi `DemoScreen?`. `AppServices.demo(screen: String?)` tetap menerima string dari argumen.
- Identifier yang dipakai Task 4 (`accessibilityIdentifier`):
  - `keys.list` (List daftar), `keys.empty.add` (tombol tambah di daftar kosong);
  - `detail.list`, `detail.history.see_all`, `history.list`;
  - `present.cancel`, `present.done`, `present.open_settings`;
  - `help.list`, `help.faq.first` (topik FAQ pertama);
  - `add.method.card`, `add.code.field`, `add.link.field`, `add.field_error`, `add.confirm.read`;
  - `add.result.done`, `add.result.pending`, `add.result.failed`.

- [ ] **Step 1: Tulis test yang gagal** di `DemoScreenTests.swift`:
  - `layarLiveTanpaPresentasi` (berargumen, masukan literal): `DemoScreen.live` memberi nil untuk `"presentation"`, `"bluetooth-denied"`, `"presentation-denied"`, `"add"`, `"empty"`, `"xyz"`, dan nil; memberi `.detail`, `.lab`, `.help` untuk `"detail"`, `"lab"`, `"help"`.
  - `nilaiTakDikenalDiabaikan`: `await AppServices.demo(screen: "xyz")` memberi `demoScreen == nil`.
  - `demoKosongTanpaKartu`: `demo(screen: "empty")` → `cards.all()` kosong; `demo(screen: nil)` → 4 kartu.
  - `demoTambahKartuLayananTersedia`: setiap layar `opensAddCard` → `apiBaseURL == URL(string: "https://demo.invalid")`; `demo(screen: nil)` dan `demo(screen: "help")` → `apiBaseURL == nil`.
  - `demoPresentasiDitolak`: `DemoScreen.presentationDenied.presentmentEvents == [.waitingForReader, .denied(reason: .zoneNotAllowed)]`; `.bluetoothDenied` → `[.waitingForReader, .unavailable(.bluetoothUnauthorized)]`; lainnya `[.waitingForReader]`.
  - `langkahDemoTambahKartu` (berargumen atas tujuh layar `add*`), dengan `AddCardModel(services: await AppServices.demo(screen: layar.rawValue), reader: FixedCardOwnershipReader(.failure(.cardReaderUnavailable)))` lalu `apply`:
    - `.add` → `.chooseMethod`;
    - `.addCode` → `.siteCode` dengan `fieldError == localized("add.code.invalid")`;
    - `.addConfirm` → `.confirmSite` dengan nama "Menara Anastrophe";
    - `.addInvitation` → `.invitation` dengan `fieldError == localized("add.link.invalid")`;
    - `.addDone` → `.done`;
    - `.addPending` → `.pending(siteName: "Menara Anastrophe")`;
    - `.addFailed` → `.failed` dengan `offersInvitation == true`.
- [ ] **Step 2: Jalankan dan lihat gagal.** Run: `swift test --package-path Packages --filter DemoScreenTests`. Expected: gagal kompilasi (`DemoScreen` belum ada).
- [ ] **Step 3: Implementasi.**
  - `demo(screen:)`:
    - mengurai `DemoScreen(rawValue:)` dan memakai `presentmentEvents`;
    - alamat `https://demo.invalid` untuk layar `opensAddCard`;
    - tanpa kartu contoh untuk `.empty`.
  - `openDemoScreen`:
    - `.detailSuspended` membuka kartu ditangguhkan pertama;
    - `.presentation`, `.bluetoothDenied`, dan `.presentationDenied` memakai kartu pertama yang bisa dipresentasikan;
    - layar `add*` membuka `AddCardRequest(entry: .start, demoScreen:)`.
  - `AddCardView.start()` memanggil `AddCardDemo.apply` di DEBUG.
  - `AppEnvironment` jalur live: `services.demoScreen = DemoScreen.live(screen)`.
  - Identifier dipasang sesuai daftar Interfaces.
- [ ] **Step 4: Jalankan dan lihat lulus.** Run: `swift test --package-path Packages`. Expected: semua test lulus.
- [ ] **Step 5: Mutasi**, masing-masing harus gagal lalu dikembalikan:
  - `.presentation` diizinkan di `live` → `layarLiveTanpaPresentasi` gagal;
  - alamat demo dipasang untuk semua layar → `demoTambahKartuLayananTersedia` gagal.
- [ ] **Step 6: Commit** `feat(demo): layar demo untuk audit aksesibilitas dan identifier penanda (ADR-0057)`.

### Task 4: Target UI test, audit 16 keadaan, dan perbaikan temuan (TC-UX-01, -02, -04)

**Files:**
- Modify: `Anastrophe.xcodeproj/project.pbxproj`. Tambahkan target `AnastropheUITests`:
  - `productType` `com.apple.product-type.bundle.ui-testing`, folder tersinkron `AnastropheUITests`;
  - `TEST_TARGET_NAME = Anastrophe`, `PRODUCT_BUNDLE_IDENTIFIER = app.anastrophe.uitests`, `GENERATE_INFOPLIST_FILE = YES`;
  - `SWIFT_VERSION = 6.0`, `TARGETED_DEVICE_FAMILY = 1`, `CODE_SIGN_STYLE = Automatic`;
  - dependensi ke app dan `TestTargetID`.

  ID objek baru mengikuti pola `A1000000000000000000<huruf><3 digit>` yang belum dipakai.
- Create: `Anastrophe.xcodeproj/xcshareddata/xcschemes/Anastrophe.xcscheme`:
  - build app, plus `AnastropheUITests` untuk testing;
  - test action Debug dengan `AnastropheUITests` (tidak paralel);
  - launch action app.
- Create:
  - `AnastropheUITests/AuditScreen.swift` (16 keadaan, argumen demo, penanda, langkah persiapan, jumlah halaman gulir);
  - `AnastropheUITests/AccessibilityAudit.swift` (helper luncur/audit/target sentuh);
  - `AnastropheUITests/AuditTerangGelapTests.swift`;
  - `AnastropheUITests/AuditAX5Tests.swift`.
- Modify sesuai temuan: view di `Packages/Sources/ANFeatures/**`, gaya baru di `Packages/Sources/ANDesignSystem/`, dan string di `Localizable.xcstrings` bila perlu.

**Interfaces:**
- Consumes: `DemoScreen` (nilai mentah) dan identifier dari Task 3; `ANColorToken` dari Task 1.
- Produces: perintah `xcodebuild test -project Anastrophe.xcodeproj -scheme Anastrophe -destination 'platform=iOS Simulator,name=iPhone 17e' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedDataA11y`.

- [ ] **Step 1: Target dan skema.** Tambahkan target dan skema. Run: `xcodebuild -project Anastrophe.xcodeproj -list`. Expected: target `AnastropheUITests` dan skema `Anastrophe` terdaftar. Lalu jalankan `xcodebuild build-for-testing` dengan destinasi iPhone 17e. Expected: `** TEST BUILD SUCCEEDED **`.
- [ ] **Step 2: Tulis test.** `AuditScreen` memetakan 16 keadaan spesifikasi ke argumen dan penanda:
  - `list` → tanpa `-ANDemoScreen`, penanda `keys.list`;
  - `empty` → `empty` / `keys.empty.add`;
  - `detail` → `detail` / `detail.list`;
  - `detailSuspended` → `detail-suspended` / `detail.list`;
  - `history` → `detail`, lalu ketuk `detail.history.see_all` / `history.list`;
  - `presentation` → `presentation` / `present.cancel`;
  - `bluetoothDenied` → `bluetooth-denied` / `present.open_settings`;
  - `presentationDenied` → `presentation-denied` / `present.done`;
  - `help` → `help`, lalu ketuk `help.faq.first` / `help.list`;
  - `add` → `add` / `add.method.card`;
  - `addCode` → `add-code` / `add.field_error`;
  - `addConfirm` → `add-confirm` / `add.confirm.read`;
  - `addInvitation` → `add-invitation` / `add.field_error`;
  - `addDone` → `add-done` / `add.result.done`;
  - `addPending` → `add-pending` / `add.result.pending`;
  - `addFailed` → `add-failed` / `add.result.failed`.

  Helper `AccessibilityAudit`:
  - **Luncur:** `-ANDemo`, `-ANDemoScreen <nilai>`, opsional `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` dan `-AppleLanguages (en) -AppleLocale en_US`. Penanda ditunggu ≤ 10 dtk; bila tidak muncul, test gagal.
  - **Audit:** `performAccessibilityAudit(for: .all)` dengan handler. Handler mengecualikan isu `.contrast` pada elemen `isEnabled == false` dan entri daftar `exemptions` (jenis audit + identifier/label persis + alasan). Isu lain gagal dengan `compactDescription`, `detailedDescription`, dan deskripsi elemen.
  - **Target sentuh:** untuk `buttons`, `links`, dan `textFields` yang `isHittable` dan bukan milik sistem (di luar bilah navigasi, toolbar, keyboard, dan grabber lembar):
    - lebar dan tinggi ≥ 43,5 pt;
    - pasangan yang tidak bertumpuk dan tidak bersarang, di luar sel, berjarak ≥ 8 pt;
    - gagal bila tidak ada satu pun elemen yang diperiksa.
  - **Gulir:** audit dan cek target sentuh diulang sesudah setiap `swipeUp`, sampai jumlah halaman layar itu habis atau konten tidak bergerak. Jumlah halaman: 0 untuk layar pendek, 2–3 untuk detail, riwayat, dan Bantuan; di AX5 setiap layar sampai 4.
  - **Bukti:** screenshot dilampirkan per audit (`XCTAttachment`, `lifetime = .keepAlways`).

  `AuditTerangGelapTests` punya satu metode per keadaan: audit terang, lalu `XCUIDevice.shared.appearance = .dark`, lalu audit lagi; `tearDown` mengembalikan ke terang. `AuditAX5Tests` punya satu metode per keadaan, dengan audit AX5 ID lalu AX5 EN. `test_cekTargetSentuhGagalTanpaElemen` memakai `XCTExpectFailure` atas layar tanpa elemen interaktif (`AuditScreen.add` sesudah semua elemen difilter keluar) untuk membuktikan cek tidak lulus kosong.
- [ ] **Step 3: Jalankan dan lihat gagal (RED).** Run perintah Produces dengan destinasi iPhone 17e saja; simpan keluaran ke workspace. Expected: test gagal dengan temuan audit nyata. Catat jumlah temuan per jenis dan per keadaan di ledger sebagai bukti "sebelum perbaikan".
- [ ] **Step 4: Triage dan keputusan JEV.** Setiap temuan menjadi salah satu dari dua: perbaikan kode, atau pengecualian per elemen beralasan (komponen sistem yang tidak bisa diubah). Tulis keputusan per kelas temuan di ledger (`Ruling:`).

  Dua pilihan di spesifikasi ("Keputusan sesudah bukti audit pertama") diputuskan lewat `jev_decide` dengan bukti RED:
  - cakupan token dan tint app;
  - kebijakan kontras "nyaris lulus".

  Log mentahnya disimpan di `docs/adr/jev-log/`, lalu dicatat sebagai ADR baru.
- [ ] **Step 5: Perbaiki.** Kelas yang diperkirakan:
  - **Bingkai di luar tombol** (`present.cancel`, `present.retry`, tombol sekunder Tambah Kartu, tautan Pengaturan): gaya `ANSecondaryButtonStyle` di `ANDesignSystem`, dengan bingkai `minHeight: 44` dan `contentShape` di dalam label, token `secondary`, dan opacity nonaktif seperti tombol utama.
  - **Tombol "Gunakan" di baris** dengan tinggi < 44 pt: ukuran kontrol atau gaya yang menjamin 44 pt.
  - **Field teks** < 44 pt: gaya field dengan tinggi minimal 44 pt.
  - **Latar baris `List`**: `listRowBackground(ANColor.card)` di daftar kartu, detail, riwayat, dan Bantuan (spesifikasi Tujuan 2).

  Kelas lain diputuskan dari bukti Step 3.
- [ ] **Step 6: Pengecualian.** Setiap entri `exemptions` memuat jenis audit, identifier/label persis, dan alasan. Daftar akhirnya disalin ke ledger untuk QA §11.1.
- [ ] **Step 7: Jalankan dan lihat lulus (GREEN).** Run perintah Produces (kedua perangkat). Expected: `** TEST SUCCEEDED **` dan semua metode lulus. Lalu jalankan `swift test --package-path Packages` dan suite paket di simulator. Expected: semua lulus.
- [ ] **Step 8: Mutasi**, masing-masing dijalankan pada keadaan terkait lalu dikembalikan:
  - bingkai `present.cancel` dikembalikan ke luar tombol → `presentation` gagal;
  - `Label` tombol Bantuan diganti `Image` tanpa label → `list` gagal;
  - pengecualian kontras diperluas ke semua jenis audit → `test_cekTargetSentuhGagalTanpaElemen` tetap lulus, dan reviewer memeriksa diff pengecualian (catat sebagai batas: mutasi pengecualian dijaga review, bukan test).
- [ ] **Step 9: Build Release** untuk simulator. Run: `xcodebuild -project Anastrophe.xcodeproj -scheme Anastrophe -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17e' -derivedDataPath build/DerivedDataA11y build`. Expected: `** BUILD SUCCEEDED **`, dan `strings` atas biner tidak memuat `demo.invalid` maupun `presentation-denied`.
- [ ] **Step 10: Screenshot bukti.** Ambil screenshot simulator dari lampiran hasil test (`xcresulttool`) untuk daftar, detail, presentasi, dan Tambah Kartu, dalam mode terang, gelap, dan AX5. Simpan di workspace, tidak di repo.
- [ ] **Step 11: Commit** `feat(a11y): target UI test audit aksesibilitas 16 keadaan dan perbaikan temuan (TC-UX-01, -02, -04)`.

### Task 5: Dokumen hasil

**Files:**
- Modify:
  - `docs/QA_SUITE.md` (§11.1: TC-UX-01, -02, -03, -04, -09);
  - `docs/SDD.md` (§5.10 baru tentang aksesibilitas dan audit, baris versi 2.35);
  - `README.md` (perintah UI test);
  - `docs/agentmemory/backlog.md` (tindak lanjut).

- [ ] **Step 1: QA §11.1**, isinya dari keluaran nyata Task 1–4:
  - **TC-UX-03:** pasangan dan rasio terendah per mode.
  - **TC-UX-01, -02, -04:** perangkat, jumlah keadaan, varian, jumlah temuan sebelum dan sesudah, daftar pengecualian, dan nama test.
  - **TC-UX-09:** penilaian per butir checklist §9, yaitu lulus, tertunda (perangkat), atau belum berlaku (OTP, Wallet).

  Pemeriksaan manual VoiceOver di iPhone fisik ditulis tertunda.
- [ ] **Step 2: SDD, README, backlog.**
  - SDD §5.10: pendekatan token-sebagai-data, audit XCUITest, dan aturan pengecualian; baris versi.
  - README: perintah UI test dan lamanya.
  - Backlog: VoiceOver manual di perangkat, CI UI test, TC-UX-05, dan minor yang tertunda.
- [ ] **Step 3: Verifikasi.** Run: `python3 scripts/docs/check_docs.py .`. Expected: `problems: 0`.
- [ ] **Step 4: Commit** `docs: hasil audit aksesibilitas (QA TC-UX-01–04, TC-UX-09)`.
