# Alur Tambah Kartu Produksi — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pengguna build Release bisa menambah kartu akses lewat kode gedung + tempel kartu, atau lewat tautan undangan, dengan kanal N-HCE/B dipilih otomatis.

**Architecture:**
- **Backend:** kolom kode gedung + endpoint lookup + CLI `site-code`; baris perangkat dibuat di transaksi enrolment.
- **App:** inti `LabProvisioning` dipindah menjadi `CardProvisioner` produksi. `AddCardModel`/`AddCardView` mengatur langkah dan pesan.
- **Pembaca kartu:** `NFCTagReaderSession` di balik protokol `CardOwnershipReader`, dengan pembaca palsu khusus DEBUG di simulator untuk e2e.

**Tech Stack:**
- App: Swift 6, SwiftUI `@Observable`, Swift Testing, Core NFC.
- Backend: Go 1.27, PostgreSQL 16 (pgx v5, `testpg`).

**Spec:** `docs/superpowers/specs/2026-11-02-alur-tambah-kartu-design.md` (ADR-0043, ADR-0044, ADR-0045).

## Global Constraints

- Minimum iOS 26.0 (ADR-0006). Swift 6 language mode. Semua string UI ada dalam ID dan EN di `Packages/Sources/ANFeatures/Resources/Localizable.xcstrings`.
- **Tanpa clone UID atau MIFARE Classic** (ADR-0001, aturan 1). Pembaca hanya mengambil `identifier`, tanpa sektor, NDEF, autentikasi, atau penulisan.
- **Identitas kartu mentah** tidak pernah disimpan atau di-log (aturan 6): tidak di state model yang bertahan, pesan galat, store, maupun DB.
- **Teks alur ini tanpa jargon:** tanpa "NFC", "HCE", "APDU". Test jargon diperluas ke kunci `add.`.
- **Kode gedung:** alfabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ`, 8 simbol, tampil `XXXX-XXXX`.
  - Normalisasi: huruf besar; `-` dan spasi dibuang; `O` → `0`; `I`, `L` → `1`.
- **`SITE-NOT-FOUND`:** 404 dengan body identik untuk kode tak dikenal, rusak, atau kosong; `Cache-Control: no-store`.
- **`device_id`:** UUID v4 huruf kecil di Keychain `afterFirstUnlockThisDeviceOnly`. Dibuat ulang bila penanda instalasi tidak ada. Tidak pernah ditampilkan atau di-log.
- **Kanal enrolment:** irisan `/v1/config` dengan `{nfcHCE, ble}`, urutan N-HCE lalu B. Untuk B, `bluetoothOff`/`bluetoothUnauthorized` dianggap bisa diprovisikan. Tanpa kanal → `ANError.channelUnavailable`, tanpa `POST /v1/enrollments`.
- **Tanpa skema URL kustom.** Undangan hanya `https://<host>/i/<token>` (`InvitationLink.token(from:)`).
- **Commit:** pesan berbahasa Indonesia dan diakhiri `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Commit hanya di `feat/r1-scaffold`, tanpa push.
- **Perintah verifikasi:**
  - Go: `cd backend && ANASTROPHE_REQUIRE_PG=1 go test ./...`.
  - Swift host: `cd Packages && swift test`.
  - Simulator: `cd Packages && xcodebuild -scheme AnastropheKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`.
  - Dokumen: `python3 scripts/docs/check_docs.py .` (exit 0).

## Review Focus

1. **Identitas kartu tidak bertahan.** Setelah alur berhasil maupun gagal, hex identitas tidak muncul di kartu tersimpan, record, deskripsi langkah model, atau pesan galat. Test: Task 6 `identitasKartuTidakTertinggal`.
2. **Enrolment ditolak tidak meninggalkan baris `devices`.** Berlaku untuk kartu tak terdaftar, gedung tak dikenal, undangan tidak sah, dan batas 8, dengan dan tanpa Idempotency-Key. Test: Task 2 `TestEnrolmentDitolakTanpaBarisPerangkat`.
3. **Lookup menjawab identik** untuk kode tak dikenal, rusak, kosong, atau bersimbol asing. Normalisasi app sama dengan server; vektor yang sama dipakai di Go dan Swift. Test: Task 1 `TestLookupKodeGedungIdentik`, Task 3 `normalisasiSamaDenganServer`.
4. **Ketuk ganda hanya menghasilkan satu enrolment.** Test: Task 6 `ketukGandaHanyaSatuEnrolment`.
5. **Instalasi baru membuat `device_id` baru**, sementara peluncuran berikutnya memakai yang sama. Test: Task 3 `instalasiBaruMembuatIDBaru`.

Vektor normalisasi bersama (Go dan Swift):

| Masukan | Hasil |
|---|---|
| `"7k2q-9xa4"` | `"7K2Q9XA4"` |
| `" 7K2Q 9XA4 "` | `"7K2Q9XA4"` |
| `"OIL0-1234"` | `"01101234"` |
| `"7K2Q9XA"` | tidak sah (7 simbol) |
| `"7K2Q9XA4Z"` | tidak sah (9 simbol) |
| `"7K2Q9XU4"` | tidak sah (`U`) |
| `""` | tidak sah |

---

### Task 1: Backend: kode gedung (migrasi, store, lookup, CLI, devseed)

**Files:**
- Create: `backend/internal/store/migrations/0013_site_join_code.sql`, `backend/internal/store/sitecode.go`, `backend/internal/store/sitecode_test.go`, `backend/internal/enroll/sites.go`, `backend/internal/enroll/sites_test.go`
- Modify: `backend/internal/enroll/credentials.go:50-56` (Register), `backend/cmd/anastrophe-registry/main.go` (subcommand `site-code`, usage), `backend/cmd/anastrophe-registry/main_test.go`, `backend/internal/store/seed.go` (`SeedOutput.JoinCode`), `backend/cmd/anastrophe-devseed/main.go`

**Interfaces:**
- Produces:
  - `store.NormalizeJoinCode(s string) (string, bool)`.
  - `(*Store).RotateSiteJoinCode(ctx, siteID, operator string, at time.Time) (code string, replaced bool, err error)`.
  - `(*Store).SiteByJoinCode(ctx, code string) (SiteRef, error)` dengan `type SiteRef struct{ ID, Name string }`, atau `ErrNotFound`.
  - `store.FormatJoinCode(code string) string`, yang menghasilkan `XXXX-XXXX`.
  - `GET /v1/sites/lookup?code=` → `{"site_id","name"}`.
  - `SeedOutput.JoinCode string` dengan tag json `join_code,omitempty`.

- [ ] **Step 1: Tulis test store yang gagal** di `sitecode_test.go`:
  - `TestNormalisasiKodeGedung`: tabel vektor bersama di atas.
  - `TestRotasiKodeGedung`:
    - kode 8 simbol alfabet;
    - rotasi kedua menghasilkan kode berbeda dan `replaced == true`;
    - kode lama memberi `ErrNotFound` di `SiteByJoinCode`;
    - audit `site.join_code_rotated` dengan aktor `operator:staf-01` dan data tanpa nilai kode (dicek dengan `allTablesText`-gaya: dump `audit_events` tidak memuat kode).
  - `TestRotasiKodeGedungValidasi`: operator kosong → `ErrInvalidOperator`; site bukan UUID atau tak dikenal → `ErrNotFound`.
  - `TestCariKodeGedung`: kode dinormalisasi (`strings.ToLower` + `-`) menemukan `SiteRef{ID, Name: "Menara Uji"}`.
- [ ] **Step 2: Jalankan** `cd backend && ANASTROPHE_REQUIRE_PG=1 go test ./internal/store/ -run 'KodeGedung'`. Expected: FAIL (fungsi belum ada).
- [ ] **Step 3: Implementasikan.**
  - Migrasi `0013`: `ALTER TABLE sites ADD COLUMN join_code text UNIQUE CHECK (join_code ~ '^[0-9A-HJKMNP-TV-Z]{8}$')`.
  - `sitecode.go`:
    - `crypto/rand` (rejection sampling atau `rand.Int` per simbol);
    - `UPDATE sites SET join_code = $2 WHERE id = $1 RETURNING (join_code lama IS NOT NULL)` lewat CTE `FOR UPDATE`;
    - bentrok `23505` pada `sites_join_code_key` dicoba ulang maksimal 5 kali;
    - audit di transaksi yang sama, `Subject: "site:" + id`.
- [ ] **Step 4: Jalankan ulang.** Expected: PASS.
- [ ] **Step 5: Tulis test HTTP yang gagal** di `enroll/sites_test.go`, memakai `newFixture`:
  - `TestLookupKodeGedung`: 200, body tepat `{"site_id","name"}`, `Cache-Control: no-store`.
  - `TestLookupKodeGedungIdentik`: `code` tak dikenal, `abc`, kosong, parameter tidak ada, `7K2Q9XU4`, dan 100 karakter. Semuanya 404 dengan body byte-identik dan `problemType == "SITE-NOT-FOUND"`.
- [ ] **Step 6: Jalankan** `go test ./internal/enroll/ -run Lookup`. Expected: FAIL (404 rute tak dikenal `NOT-FOUND`).
- [ ] **Step 7: Implementasikan** `func (h *Handler) lookupSite(w, r)` di `sites.go` dengan pola seperti `cardStatus`, lalu daftarkan `httpapi.Route(mux, http.MethodGet, "/v1/sites/lookup", h.lookupSite)`. Expected: PASS.
- [ ] **Step 8: Tulis test CLI yang gagal** di `main_test.go`:
  - `TestSiteCodeMencetakKode`: exit 0; stdout cocok `^kode: [0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}\n$`; `SiteByJoinCode` menemukan gedung.
  - `TestSiteCodeRotasiMemperingatkan`: run kedua mencetak peringatan rotasi ke stderr, dan kode pertama tidak lagi ditemukan.
  - `TestSiteCodeArgumenSalah`: tanpa `--site` atau `--operator` → exit 2.
- [ ] **Step 9: Implementasikan** subcommand `site-code` (`--site`, `--operator`) dan perbarui `usage` serta komentar paket. Lalu `SeedOutput.JoinCode`: devseed memanggil `RotateSiteJoinCode(ctx, out.SiteID, "devseed", now)` setelah `SeedLab` dan mengisi `JoinCode` dengan `FormatJoinCode`. Jalankan `go test ./cmd/... ./internal/...`. Expected: PASS.
- [ ] **Step 10: Commit.**
```bash
git add backend && git commit -m "feat(backend): kode gedung, lookup /v1/sites/lookup, CLI site-code (ADR-0044)"
```

### Task 2: Backend: perangkat dibuat di transaksi enrolment (ADR-0045)

**Files:**
- Modify: `backend/internal/store/registry.go` (`enrollCard`), `backend/internal/store/invitation.go` (`enrollInvitation`)
- Test: `backend/internal/enroll/device_test.go` (baru)

**Interfaces:**
- Consumes: fixture `newFixture`, `do`, `request`, `cardBody`, `problemType`.
- Produces: `func ensureDevice(ctx context.Context, tx pgx.Tx, deviceID string) error` (store, privat).

- [ ] **Step 1: Tulis test yang gagal:**
  - `TestEnrolmentKartuMembuatPerangkatBaru`: `device_id` UUID baru yang belum ada di `devices` → 201 `PROVISIONING`, dan tepat satu baris `devices` dengan id itu.
  - `TestEnrolmentUndanganMembuatPerangkatBaru`: undangan sah (`CreateInvitation`) + `device_id` baru → 201.
  - `TestEnrolmentDitolakTanpaBarisPerangkat`: untuk `ENR-NOT-REGISTERED`, `ENR-NOT-FOUND` (gedung tak dikenal), dan `ENR-INVITATION-INVALID`, masing-masing dengan dan tanpa Idempotency-Key. `device_id` selalu baru, dan `SELECT count(*) FROM devices WHERE id = $1` tetap 0.
  - `TestEnrolmentPerangkatBaruBersamaan`: dua enrolment paralel dari `device_id` baru yang sama untuk dua kartu berbeda keduanya berhasil, dengan satu baris perangkat.
- [ ] **Step 2: Jalankan** `go test ./internal/enroll/ -run 'PerangkatBaru|TanpaBarisPerangkat'`. Expected: FAIL (`ENR-NOT-FOUND` untuk perangkat baru).
- [ ] **Step 3: Implementasikan** `ensureDevice` (`INSERT INTO devices (id) VALUES ($1) ON CONFLICT (id) DO NOTHING`). Panggil setelah validasi UUID dan sebelum `lockDevice` di `enrollCard` dan `enrollInvitation`. `StartEnrollment` tidak diubah.
- [ ] **Step 4: Jalankan seluruh backend.** `ANASTROPHE_REQUIRE_PG=1 go test ./...`. Expected: PASS. Test lama tentang perangkat tak dikenal dibaca ulang; bila ada yang mengharapkan `ENR-NOT-FOUND` untuk perangkat baru, sesuaikan dan catat Ruling di ledger.
- [ ] **Step 5: Commit.**
```bash
git add backend && git commit -m "feat(backend): perangkat dibuat di transaksi enrolment (ADR-0045)"
```

### Task 3: App: kode gedung, lookup, identitas perangkat, base URL

**Files:**
- Create: `Packages/Sources/ANCore/SiteJoinCode.swift`, `Packages/Sources/ANStorage/DeviceIdentityStore.swift`, `Packages/Sources/ANFeatures/BackendConfiguration.swift`, `App/Info.plist`
- Modify:
  - `Packages/Sources/ANCore/ANError.swift`: `EnrollmentRejection.siteCodeUnknown`, `ANError.cardUnreadable`, `.cardReaderUnavailable`, `.serviceUnavailable`.
  - `Packages/Sources/ANNetworking/APIClient.swift`: `lookupSite`, `SiteSummary`.
  - `Packages/Sources/ANNetworking/ProblemDetails.swift`: `SITE-NOT-FOUND`.
  - `Config/Base.xcconfig`: `AN_API_BASE_URL =`.
  - `Config/Local.xcconfig.example`: contoh `https:/$()/…`.
  - `Anastrophe.xcodeproj/project.pbxproj`: `INFOPLIST_FILE = App/Info.plist` di dua konfigurasi target app.
- Test: `Packages/Tests/ANCoreTests/SiteJoinCodeTests.swift`, `Packages/Tests/ANNetworkingTests/SiteLookupTests.swift`, `Packages/Tests/ANStorageTests/DeviceIdentityStoreTests.swift`, `Packages/Tests/ANFeaturesTests/BackendConfigurationTests.swift`

**Interfaces:**
- Produces:
  - `public enum SiteJoinCode { static func normalized(_ input: String) -> String?; static func display(_ code: String) -> String }`.
  - `public struct SiteSummary: Equatable, Sendable, Decodable { siteID: String; name: String }` dengan kunci `site_id`/`name`.
  - `APIClient.lookupSite(code: String) async throws -> SiteSummary`, yang menormalisasi lebih dulu dan melempar `.enrollmentRejected(.siteCodeUnknown)` tanpa jaringan bila kode tidak sah.
  - `public protocol DeviceIdentityStore: Sendable { func deviceID() throws -> String }`.
  - `public struct KeychainDeviceIdentityStore: DeviceIdentityStore { init(store: any SecretStore, installMarker: URL) }`.
  - `public enum BackendConfiguration { static func apiBaseURL(infoValue: String?, arguments: [String]) -> URL? }`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `normalisasiSamaDenganServer`: vektor bersama.
  - `tampilanBerkelompokEmpat`: `display("7K2Q9XA4") == "7K2Q-9XA4"`.
  - `lookupMengirimKodeTernormalisasi`: path `/v1/sites/lookup`, query `code=7K2Q9XA4`, hasil `SiteSummary`.
  - `lookupTakDikenalMenjadiSiteCodeUnknown`: 404 `SITE-NOT-FOUND`.
  - `lookupKodeRusakTanpaJaringan`: `SequenceTransport([])` dan `paths.isEmpty`.
  - `idPerangkatDibuatSekaliDanStabil`: dua panggilan memberi nilai sama, UUID huruf kecil, aksesibilitas `afterFirstUnlockThisDeviceOnly` (spy `SecretStore`).
  - `instalasiBaruMembuatIDBaru`: hapus berkas penanda → id baru; penanda dibuat dengan `isExcludedFromBackup == true`.
  - `baseURLDariInfoPlist`.
  - `baseURLKosongBerartiTidakAda`: `nil` untuk `""`, `"bukan url"`, dan `"ftp://x"`.
  - `argumenDebugMenimpaInfoPlist`: `-ANAPIBaseURL http://127.0.0.1:8099`.
- [ ] **Step 2: Jalankan** `cd Packages && swift test --filter 'SiteJoinCode|SiteLookup|DeviceIdentity|BackendConfiguration'`. Expected: FAIL (tipe belum ada).
- [ ] **Step 3: Implementasikan** semua di atas, dengan aturan berikut:
  - `BackendConfiguration` menerima `http` hanya di DEBUG dan `https` di semua build.
  - `App/Info.plist` hanya memuat `ANAPIBaseURL` = `$(AN_API_BASE_URL)`.
  - Di DEBUG, `AppEnvironment` membaca Info.plist dan argumen lalu meneruskannya ke `AppServices.live(nfcEmulationEntitled:apiBaseURL:)`. Ini disambung di Task 6.
- [ ] **Step 4: Jalankan host lalu simulator.** Expected: PASS. Build app tetap sukses: `xcodebuild -project Anastrophe.xcodeproj -scheme Anastrophe -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`.
- [ ] **Step 5: Commit.**
```bash
git add Packages App Config Anastrophe.xcodeproj && git commit -m "feat(app): kode gedung, lookup gedung, identitas perangkat, base URL dari Info.plist"
```

### Task 4: App: `CardProvisioner` produksi dan pemilihan kanal

**Files:**
- Create: `Packages/Sources/ANFeatures/CardProvisioner.swift`, `Packages/Tests/ANFeaturesTests/CardProvisionerTests.swift`
- Modify: `Packages/Sources/ANFeatures/Lab/LabProvisioning.swift` (delegasi), `Packages/Sources/ANFeatures/EnrollmentMessages.swift` (galat baru)

**Interfaces:**
- Consumes: `APIClient`, `ProvisioningSecret`, `StatusToken`, `ChannelSelector.preferred`.
- Produces:
  - `public enum EnrollmentRequest: Sendable { case card(siteID: String, identity: CardIdentity); case invitation(token: String) }`.
  - `public enum EnrollmentOutcome: Equatable, Sendable { case added(Card); case pendingApproval }`.
  - `struct CardProvisioner` dengan field `api`, `keys`, `records`, `cards`, `statusTokens: (any StatusTokenStore)?`.
  - `func provision(_ request: EnrollmentRequest, deviceID: String, channel: ChannelChoice) async throws -> EnrollmentOutcome`.
  - `enum ChannelChoice: Sendable { case fixed(ChannelKind); case automatic([ChannelKind: ChannelAvailability]) }`.
  - `static func provisionableChannel(enabled: Set<ChannelKind>, availability: [ChannelKind: ChannelAvailability]) -> ChannelKind?`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `kanalOtomatisMemilihHCEDulu`: config `["ble","nfcHCE"]` dan keduanya `.available` → body provisioning `"channel":"nfcHCE"`.
  - `kanalOtomatisJatuhKeBLE`: `nfcHCE: .notEligible` → `ble`.
  - `bluetoothMatiTetapBisaDiprovisikan`: `ble: .bluetoothOff` → `ble`.
  - `tanpaKanalTidakMendaftar`: config `["nfcHCE"]` dan `nfcHCE: .unsupportedDevice` → `ANError.channelUnavailable(.notEligible)`, `paths == ["/v1/config"]`.
  - `menungguPersetujuanMenjadiHasil`: `.pendingApproval`, tanpa kunci (`storedKeyCount == 0`) dan tanpa kartu.
  - `undanganMembawaToken`: body `invitation`, tanpa `site_id`.
- [ ] **Step 2: Jalankan** `swift test --filter CardProvisioner`. Expected: FAIL.
- [ ] **Step 3: Implementasikan.**
  - Pindahkan isi `LabProvisioning.provisionViaBackend` dan `store(...)` ke `CardProvisioner`.
  - `LabProvisioning.provisionViaBackend` mempertahankan signature-nya, memanggil `.fixed(channel)`, dan melempar `ANError.enrollmentRejected(.pendingApproval)` untuk `.pendingApproval` agar test lab tetap berlaku.
  - `EnrollmentMessages.text(for:)` menambah `siteCodeUnknown`, `cardUnreadable`, `cardReaderUnavailable`, `serviceUnavailable`, dan `channelUnavailable`, dengan kunci `add.error.*` (ID/EN) di katalog.
- [ ] **Step 4: Jalankan host dan simulator.** Expected: PASS, termasuk seluruh `LabBackendProvisioningTests` dan `EnrollmentMessagesTests`.
- [ ] **Step 5: Commit.**
```bash
git add Packages && git commit -m "feat(app): CardProvisioner produksi dengan pemilihan kanal otomatis (FR-05)"
```

### Task 5: Pembaca kartu (Core NFC) dan pemetaan identitas

**Files:**
- Create: `Packages/Sources/ANNFCEnroll/CardIdentityMapper.swift`, `Packages/Sources/ANNFCEnroll/NFCTagCardOwnershipReader.swift`, `Packages/Sources/ANNFCEnroll/FixedCardOwnershipReader.swift`, `Packages/Tests/ANNFCEnrollTests/CardIdentityMapperTests.swift`
- Modify: `Packages/Package.swift` (test target `ANNFCEnrollTests` → `ANNFCEnroll`, `ANCore`)

**Interfaces:**
- Produces:
  - `public enum DetectedTag: Equatable, Sendable { case miFare(identifier: Data); case iso7816(identifier: Data, typeA: Bool); case iso15693(identifier: Data); case unsupported }`.
  - `public enum CardIdentityMapper { static func identity(for tag: DetectedTag) -> CardIdentity? }`.
  - `public struct FixedCardOwnershipReader: CardOwnershipReader { init(result: Result<CardIdentity, ANError>) }`.
  - `public final class NFCTagCardOwnershipReader: CardOwnershipReader` (hanya `#if os(iOS) && canImport(CoreNFC)`) dengan `init(prompt: String, multipleCardsMessage: String)`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `mifareTujuhByteMenjadiISO14443A`.
  - `iso7816TipeAMemakaiUID`.
  - `iso7816TipeBTidakDidukung` → nil.
  - `iso15693DelapanByte`.
  - `panjangTidakSahDitolak` (5 byte MIFARE, 7 byte 15693) → nil.
  - `unsupportedDitolak`.
  - `pembacaTetapMengembalikanHasil`: `FixedCardOwnershipReader` mengembalikan identitas atau melempar galat yang diberikan.
- [ ] **Step 2: Jalankan** `swift test --filter ANNFCEnrollTests`. Expected: FAIL.
- [ ] **Step 3: Implementasikan** pemetaan, pembaca tetap, dan pembaca live:
  - Pembaca live memakai `NFCTagReaderSession(pollingOption: [.iso14443, .iso15693])`, dimulai hanya bila `NFCReaderSession.readingAvailable`; bila tidak, lempar `.cardReaderUnavailable`.
  - Satu tag → `connect` → baca `identifier` → `invalidate()` → kembali lewat `CheckedContinuation`. Lebih dari satu tag → `alertMessage = multipleCardsMessage` lalu `restartPolling()`.
  - `readerSessionInvalidationErrorUserCanceled` → `CancellationError`. Batas waktu, galat lain, dan identitas nil → `.cardUnreadable`.
  - Tidak ada `print`/`Logger` yang memuat tag.
- [ ] **Step 4: Jalankan host dan simulator.** Expected: PASS. Build app sukses (pembaca live terkompilasi untuk iOS).
- [ ] **Step 5: Commit.**
```bash
git add Packages && git commit -m "feat(enroll): pembaca kartu Core NFC hanya untuk identifier dan pemetaan identitas (FR-11, ADR-0001)"
```

### Task 6: App: `AddCardModel`, `AddCardView`, tab Kunci, tautan undangan

**Files:**
- Create: `Packages/Sources/ANFeatures/AddCard/AddCardModel.swift`, `Packages/Sources/ANFeatures/AddCard/AddCardView.swift`, `Packages/Tests/ANFeaturesTests/AddCardModelTests.swift`
- Modify:
  - `Packages/Sources/ANFeatures/AppServices.swift`: `apiBaseURL: URL?`, `deviceIdentity`, `live(nfcEmulationEntitled:apiBaseURL:)`, `inMemory(...)` dengan base URL dan transport untuk test, `makeCardReader()`.
  - `Packages/Sources/ANFeatures/KeysView.swift`: tombol Tambah untuk semua build, sheet, `onOpenURL`, argumen lab.
  - `App/AppEnvironment.swift`.
  - `Packages/Sources/ANFeatures/Resources/Localizable.xcstrings`.
  - `Packages/Tests/ANFeaturesTests/StringCatalogTests.swift`: jargon juga untuk `add.`.

**Interfaces:**
- Consumes: `CardProvisioner`, `EnrollmentRequest`, `EnrollmentOutcome`, `SiteSummary`, `APIClient.lookupSite`, `DeviceIdentityStore`, `CardOwnershipReader`, `SiteJoinCode`, `InvitationLink`.
- Produces:
  - `@MainActor @Observable final class AddCardModel`, dengan state berikut:
    - `step: Step`, dengan `enum Step: Equatable { case chooseMethod, siteCode, confirmSite(SiteSummary), invitation, working, done(Card), pending(siteName: String?), failed(Failure) }`;
    - `struct Failure: Equatable { message: String; offersInvitation: Bool }`;
    - `codeInput: String`, `linkInput: String`, `fieldError: String?`, `isBusy: Bool`.
  - Metode `AddCardModel`:
    - `init(services: AppServices, reader: any CardOwnershipReader, transport: any HTTPTransport)`;
    - `chooseCard()`, `chooseInvitation()`;
    - `submitCode() async`, `confirmAndRead() async`, `submitInvitation() async`;
    - `startInvitation(token: String) async`, `back()`.
  - `enum AddCardEntry: Identifiable, Equatable { case start; case invitation(String); static func entry(for url: URL) -> AddCardEntry? }`.

- [ ] **Step 1: Tulis test model yang gagal** dengan `AppServices.inMemory(apiBaseURL:transport:)`, `SequenceTransport`, dan `FixedCardOwnershipReader`:
  - `kodeRusakTidakMemanggilJaringan`: `fieldError` terisi dan `paths.isEmpty`.
  - `kodeTakDikenalTetapDiLangkahKode`.
  - `kodeDikenalMenampilkanNamaGedung` → `.confirmSite`.
  - `kartuTerdaftarMenjadiAktif`:
    - langkah `.done`;
    - kartu tersimpan;
    - `paths == ["/v1/sites/lookup", "/v1/config", "/v1/enrollments", "/v1/enrollments/<id>/credentials"]`;
    - body enrolment memuat `device_id` dari store identitas.
  - `kartuTakTerdaftarMenawarkanUndangan`, `kartuTakTerbacaMenawarkanUndangan`, `pembacaTidakTersediaMenawarkanUndangan`.
  - `pembatalanKembaliKeKonfirmasi`: `CancellationError` → `.confirmSite` tanpa galat.
  - `menungguPersetujuanMenjelaskanLangkah` → `.pending(siteName: "Menara Uji")`.
  - `tautanUndanganMenambahKartu`, `tautanRusakDitolakDiField`.
  - `tanpaBaseURLLayananBelumTersedia`: tanpa jaringan.
  - `ketukGandaHanyaSatuEnrolment`: dua `confirmAndRead()` bersamaan → satu `/v1/enrollments`.
  - `identitasKartuTidakTertinggal`:
    - setelah berhasil dan setelah gagal, `"04a1b2c3d4e5f6"` tidak muncul di `String(describing: model.step)`;
    - JSON semua kartu, record, dan pesan galat juga bebas dari string itu.
  - `entriDariURLUndangan`: `https://contoh.test/i/<43>` → `.invitation`; `http` atau path lain → nil.
- [ ] **Step 2: Jalankan** `swift test --filter AddCardModel`. Expected: FAIL.
- [ ] **Step 3: Implementasikan.**
  - **Model:** identitas hanya variabel lokal di `confirmAndRead`. Guard `isBusy` di awal setiap aksi async.
  - **Pesan:** dari `EnrollmentMessages`. `URLError` → `add.error.offline`, lainnya → `add.error.generic`.
  - **`AddCardView`:** mengikuti `pages/ios-app.md`, dengan label terlihat di atas field kode, `ANPrimaryButtonStyle`, `ProgressView` saat `isBusy`, dan ikon `building.2`, `creditcard`, `link`.
  - **Tab Kunci:**
    - tombol `plus` berlabel `keys.add` di toolbar dan layar kosong untuk semua build, nonaktif saat `!canAddCard`;
    - Lab tetap DEBUG di toolbar terpisah;
    - `.onOpenURL { AddCardEntry.entry(for:) }`.
  - **Argumen DEBUG:** `-ANLabCardReader <tech:hex>` memakai `FixedCardOwnershipReader` (simulator saja), `-ANLabOpenURL <url>` memakai jalur `onOpenURL`, dan `-ANLabAddCode <kode>` membuka sheet, mengisi kode, lalu menjalankan `submitCode` dan `confirmAndRead` (e2e).
  - **`AppEnvironment`:** meneruskan `BackendConfiguration.apiBaseURL(infoValue:arguments:)`.
  - **Katalog:** semua kunci `add.*` dalam ID dan EN.
- [ ] **Step 4: Jalankan host dan simulator, lalu build app.** Expected: PASS, termasuk `setiapKunciYangDipakaiAdaDiKatalog` dan test jargon yang diperluas.
- [ ] **Step 5: Commit.**
```bash
git add Packages App && git commit -m "feat(app): alur Tambah Kartu di build Release: kode gedung, tempel kartu, undangan (FR-10–FR-13)"
```

### Task 7: Dokumen, e2e simulator, dan penutupan

**Files:**
- Modify:
  - `docs/SDD.md`: §5.6, §8.1, §8.4.1, §8.5, §15, rev 2.20.
  - `docs/QA_SUITE.md`: TC-ENR-20…23, §14.
  - `GLOSSARY.md`: kode gedung.
  - `README.md`: `site-code`, `AN_API_BASE_URL`, `-ANAPIBaseURL`.
  - `docs/agentmemory/backlog.md`: umur 15 menit untuk instance yang disetujui, FeliCa/AID, Associated Domains.

- [ ] **Step 1: Perbarui dokumen.**
  - **Kasus uji baru:**
    - TC-ENR-20: kode gedung, lookup, dan 404 identik (I).
    - TC-ENR-21: perangkat dibuat saat enrolment, tanpa baris saat ditolak (I).
    - TC-ENR-22: alur Tambah Kartu Release dengan kanal otomatis, pesan alasan, dan tawaran undangan (U/E).
    - TC-ENR-23: instal ulang → `device_id` baru (U).
  - **Traceability:** FR-05, FR-10, FR-11, FR-12, FR-13, dan FR-43 di §14.
  - **Status yang dicatat:** NFR-S03 tetap terbuka, dan pembacaan live adalah uji H yang belum dijalankan.
- [ ] **Step 2: Jalankan e2e di simulator** (PG sementara, devseed, API `127.0.0.1:8099`):
  - **Jalur kartu:** `-ANAPIBaseURL http://127.0.0.1:8099 -ANLabCardReader iso14443a:04a1b2c3d4e5f6 -ANLabAddCode <join_code>`. Expected: screenshot kartu aktif, `devices` bertambah satu baris dengan id baru, dan `card_instances` ACTIVE.
  - **Kartu tak terdaftar:** `-ANLabCardReader iso14443a:04ffffffffffff`. Expected: screenshot pesan + tawaran undangan, dan jumlah `devices` tidak bertambah.
  - **Undangan:** buat undangan via CLI, lalu `-ANLabOpenURL https://contoh.test/i/<token>`. Expected: kartu aktif.
  - **Lookup:** `curl` kode salah → 404 `SITE-NOT-FOUND`.
- [ ] **Step 3: Jalankan semua suite.** `check_docs` exit 0; Go, host, dan simulator semuanya lulus.
- [ ] **Step 4: Commit.**
```bash
git add docs GLOSSARY.md README.md && git commit -m "docs: alur Tambah Kartu, kode gedung, perangkat otomatis (SDD rev 2.20, QA TC-ENR-20..23)"
```
