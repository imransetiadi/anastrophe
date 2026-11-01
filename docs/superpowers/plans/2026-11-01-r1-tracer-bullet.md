# R1 Tracer Bullet (App iOS) — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App iOS yang bisa memilih kartu, mengautentikasi pengguna, lalu menyelesaikan transaksi ANP/1 lengkap lewat kanal B (BLE) dan N-HCE terhadap reader uji. Ini kriteria keluar M1 dari sisi app: "Tap N dan B berhasil di lab; test vector protokol lulus" (PRD §13).

**Architecture:** Swift package lokal `Packages/` (11 modul `AN*`, SDD §5.1) yang dikonsumsi app shell `Anastrophe.xcodeproj`. Semua I/O (CoreNFC, Core Bluetooth, Keychain/Secure Enclave, jaringan) berada di balik protokol dan diuji dengan fake. State machine ANP/1 (`ANP1Responder`) dipakai bersama kanal N dan B. Kredensial lab diterbitkan oleh skrip CA lokal (DEBUG saja), sehingga M1 tidak menunggu backend (ADR-0014 masih terbuka).

**Tech Stack:** Swift 6.2 (language mode 6), SwiftUI + `@Observable`, Swift Testing, CryptoKit, CoreNFC (`CardSession`), SecureElementCredential, Core Bluetooth, SwiftData, Xcode 27.2 / SDK iOS 27.2. Python 3 + `cryptography` 49 (test vector independen) + `cbor2` (CA lab).

**Spec:** [`docs/SDD.md`](../../SDD.md) (terutama §4–§7), [`docs/PRD.md`](../../PRD.md) (FR/NFR), [`docs/QA_SUITE.md`](../../QA_SUITE.md) (ID TC), ADR di [`docs/adr/`](../../adr/README.md).

## Kondisi awal (sudah ada di branch `feat/r1-scaffold`, belum di-commit)

| Bagian | Isi | Verifikasi |
|---|---|---|
| `Packages/Package.swift` | 11 modul `AN*` + 6 target test; iOS 26 / macOS 26 (macOS hanya untuk `swift test`) | `swift build --package-path Packages` → `Build complete!` |
| `ANCore` | `ChannelKind`, `ChannelAvailability`, `PresentmentEvent`, `RemoteConfig`, `ChannelSelector`, `CardLimit` (8), `ANError`, `CardFingerprint` (deskripsi disensor) | `swift test --package-path Packages` → 41 test lulus |
| `ANProtocol` | `ANP1` (AID, FCI, transcript, `StatusWord`), `CommandAPDU` (< 255 B), `TLV`, `ANP1Responder` (SELECT/AUTH0/AUTH1, `6982` identik), `BLEFrame` + `BLEFrameAssembler` | idem |
| `ANCrypto` | `ANP1KeySchedule` (HKDF), `ANP1SessionKeys` (nonce, seal/open AES-GCM), `ANP1Signatures` | idem |
| `ANChannelNFC` | `NFCGate` + `withEligibleSession`, `PresentmentLimits`, `SEAssertionBudget`, `LiveNFCCapabilities` | idem |
| `ANChannelBLE` · `ANStorage` · `ANNetworking` · `ANWallet` · `ANNFCEnroll` · `ANDesignSystem` · `ANFeatures` | `BLEGate`; `SecretStore` + `CredentialKeyPolicy`; `APIClient.fetchConfig`; `WalletGate`; protokol `CardOwnershipReader`; token warna; `KeysView` + string ID/EN | idem |
| App shell | `App/AnastropheApp.swift`, `Anastrophe.xcodeproj` (synchronized group, package lokal) | lihat perintah build di bawah |

Perintah standar (dipakai semua task):

```bash
# Unit test di host (cepat)
swift test --package-path Packages
# Unit test di simulator iOS (wajib sebelum task dinyatakan selesai; ikut mengompilasi kode live iOS)
(cd Packages && xcodebuild -scheme AnastropheKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath ../build/DerivedDataPkg test)
# Build app
xcodebuild -project Anastrophe.xcodeproj -scheme Anastrophe -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build
```

Lulus berarti `✔ Test run with … passed`, `** TEST SUCCEEDED **`, dan `** BUILD SUCCEEDED **`.

## Di luar cakupan (rencana terpisah)

| Area | Alasan / ketergantungan |
|---|---|
| Backend `/v1` (SDD §8) | Menunggu ADR-0014 (topologi). Kontrak JSON di Task 8 berstatus draf. |
| Firmware reader referensi (SDD §9) | Subsistem tersendiri (ADR-0016). Memakai test vector Task 3 sebagai kontrak. |
| Enrolment produksi: kartu fisik, security code, persetujuan (FR-11–FR-19) | Butuh backend. |
| N-SE: personalisasi applet (FR-16, TC-ENR-18) | Butuh entitlement NFC & SE (D1), yang menunggu ADR-0017 (D7). |
| Kanal W (R2), widget/App Shortcut (FR-24), anggota, perpanjangan, pindah perangkat | Bukan bagian tracer bullet M1. |

## Global Constraints

- Minimum **iOS 26.0** (ADR-0006); Swift language mode 6; modul berprefix `AN`.
- I/O NFC/BLE/jaringan/Keychain di balik protokol agar bisa di-mock (SDD §5.1, QA §2).
- ANP/1: AID `F0414E415354524F01`; **setiap APDU < 255 B** (perintah dan respons, tanpa extended length); ponsel tidak mengungkap identitas apa pun sebelum `sig_R` valid; respons group tak dikenal dan tanda tangan salah identik (`6982`); jangan pakai AID Aliro (ADR-0003).
- Suite: ECDH P-256 ephemeral · ECDSA P-256/SHA-256 · HKDF-SHA256 · AES-128-GCM (SDD §7.2).
- `CardSession()` tidak dibuat sebelum `NFCReaderSession.readingAvailable`, `CardSession.isSupported`, dan `await CardSession.isEligible` bernilai true; untuk SE, `CredentialSession.isEligible`. Tanpa entitlement, `CardSession()` memicu `fatalError` (O-A02).
- Presentment assertion hanya di foreground saat pengguna aktif memilih kartu; 15 dtk + cooldown 15 dtk (HCE), maks 2 per 80 dtk (SE); emulasi HCE ≤ 60 dtk (FR-21, FR-22).
- Kunci kredensial: Secure Enclave, `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` + `[.privateKeyUsage, .userPresence]`, tidak ikut backup (ADR-0009).
- Identitas kartu fisik mentah dan kontak pengguna tidak disimpan atau di-log.
- UI tidak meniru Apple Wallet; teks presentasi tanpa "NFC"/"HCE"/"APDU" (FR-26, TC-PRSN-17); semua string UI tersedia dalam **ID dan EN**.
- Batas **8 kartu per perangkat** (FR-15).
- BLE R1: foreground saja (ADR-0012); pindai 5 dtk; reader dengan RSSI tertinggi di atas ambang (default −55 dBm); maks 1 transaksi per 3 dtk per reader (SDD §6.3, FR-83).
- Masa berlaku sertifikat default 7 hari (ADR-0010).
- Secret tidak pernah masuk repo, termasuk kunci CA lab (folder `scripts/anp1/.lab/` di-ignore).
- Git: kerja di branch (bukan `main`); **commit hanya bila pengguna meminta**. Langkah "Commit" di bawah dijalankan setelah izin itu ada.
- Setiap perubahan `docs/` → `python3 scripts/docs/check_docs.py .` wajib 0 masalah. Klaim faktual baru → `jev_verify`. Sebelum menyatakan task selesai → `jev_gate` (ADR-0018).

## Review Focus

1. **Kebocoran timing group tak dikenal.** Group tak dikenal menjawab lebih cepat daripada tanda tangan salah karena ECDSA tidak dijalankan, sehingga reader asing bisa menebak gedung milik pengguna (TC-PROTO-05 menuntut timing setara). Harapannya kedua jalur menjalankan tepat satu verifikasi ECDSA. Test: Task 2, `groupTakDikenalTetapMenjalankanSatuVerifikasi`.
2. **App ke background di tengah presentasi HCE.** Harapannya sesi diinvalidasi, assertion dilepas, dan UI kembali siap tanpa menggantung (FR-22, O-A18). Test: Task 6, `backgroundMembatalkanSesi`.
3. **Kunci Secure Enclave hilang** (passcode dimatikan, atau restore ke perangkat lain). Harapannya kartu ditandai "Perlu dipindahkan", presentasi tidak dicoba, dan app tidak crash (SDD §5.3, FR-44). Test: Task 5, `kunciHilangMenandaiPerluDipindahkan`.
4. **Bluetooth dimatikan di tengah transaksi.** Harapannya sesi berakhir dengan `.cancelled`, link diputus, dan UI menampilkan panduan Bluetooth; tidak menunggu tanpa batas. Test: Task 7, `bluetoothMatiDiTengahTransaksi`.
5. **Counter mundur setelah app dimatikan.** Counter yang terulang atau mundur akan ditandai anomali oleh reader/backend (TC-PROTO-11). Harapannya counter selalu naik lintas instance store, termasuk bila transaksi gagal setelah counter diambil. Test: Task 4, `counterNaikLintasInstance`.

---

### Task 1: Konfigurasi build perangkat & entitlement dasar

**Files:**
- Create: `Config/Base.xcconfig`, `Config/Local.xcconfig.example`, `App/Anastrophe.entitlements`, `App/Anastrophe-NFCEmulation.entitlements`, `App/PrivacyInfo.xcprivacy`
- Modify: `Anastrophe.xcodeproj/project.pbxproj` (target memakai `Config/Base.xcconfig`; `CODE_SIGN_ENTITLEMENTS = App/Anastrophe.entitlements`), `.gitignore` (+ `Config/Local.xcconfig`, `scripts/anp1/.lab/`)

**Interfaces:**
- Produces: build setting `AN_NFC_EMULATION` (`NO` default). `Local.xcconfig` (di-ignore) berisi `DEVELOPMENT_TEAM`. `Base.xcconfig` diakhiri `#include? "Local.xcconfig"`.

- [ ] **Step 1:** Isi `App/Anastrophe.entitlements` hanya dengan kunci yang tidak butuh persetujuan khusus: `com.apple.developer.nfc.readersession.formats = [TAG]` dan `com.apple.developer.devicecheck.appattest-environment = development` (`production` di Release lewat xcconfig).
- [ ] **Step 2:** Isi `App/Anastrophe-NFCEmulation.entitlements` = dasar + `com.apple.developer.nfc.hce = YES`, `com.apple.developer.nfc.hce.iso7816.select-identifier-prefixes = [F0414E415354524F01]`, `com.apple.developer.secure-element-credential = YES` (SDD §5.2). Dipakai hanya bila `AN_NFC_EMULATION = YES`, yaitu setelah entitlement D1 disetujui. Tanpa entitlement itu, provisioning profile gagal dibuat.
- [ ] **Step 3:** Tambah ke Info.plist (lewat `INFOPLIST_KEY_*` atau xcconfig): `BGTaskSchedulerPermittedIdentifiers = [app.anastrophe.cert-renewal]`. Jangan tambahkan `UIBackgroundModes` (ADR-0012). `PrivacyInfo.xcprivacy`: tanpa tracking, tanpa domain tracking; deklarasikan API `UserDefaults` (CA92.1) bila dipakai.
- [ ] **Step 4:** Verifikasi simulator: perintah build app → `** BUILD SUCCEEDED **`.
- [ ] **Step 5:** Verifikasi perangkat (tipe H, iPhone pengguna): salin `Local.xcconfig.example` → `Local.xcconfig`, isi `DEVELOPMENT_TEAM`, lalu jalankan `xcodebuild … -destination 'generic/platform=iOS' -allowProvisioningUpdates build`. Hasilnya harus `** BUILD SUCCEEDED **`, app terpasang, dan layar "Kunci" tampil. Catatan: tim *Personal* (gratis) tidak bisa memakai kapabilitas NFC. Bila itu yang terjadi, hapus kunci NFC dari entitlements dasar untuk build lokal dan laporkan ke pengguna; Apple Developer Program berbayar adalah prasyarat (PRD D1/D7).
- [ ] **Step 6: Commit** — `git add Config App .gitignore Anastrophe.xcodeproj && git commit -m "build: konfigurasi perangkat & entitlement dasar"`

### Task 2: ANP/1 lengkap + sesi kriptografi ponsel

**Files:**
- Modify: `Packages/Sources/ANProtocol/ANP1Responder.swift`, `Packages/Sources/ANProtocol/ANP1.swift` (tag E1–E4, F1–F2), `Packages/Package.swift` (`ANCrypto` bergantung pada `ANProtocol`; target baru `ANTestSupport` di `Tests/ANTestSupport`)
- Create: `Packages/Sources/ANCrypto/ANP1PhoneSession.swift`, `Packages/Sources/ANCrypto/CredentialMaterial.swift`, `Packages/Tests/ANTestSupport/SoftwareReader.swift`, `Packages/Tests/ANCryptoTests/PhoneSessionTests.swift`
- Test: `Packages/Tests/ANProtocolTests/ResponderTests.swift` (sesuaikan fake ke protokol baru)

**Interfaces:**
- Produces (ANProtocol). Responder dan provider sengaja **tidak** `Sendable`: satu instance per transaksi, dimiliki satu actor.
```swift
public struct ANP1Handshake: Equatable { groupID, readerEphemeral, phoneEphemeral, transactionID: Data; var transcript: Data }
public enum ANP1Result: Equatable, Sendable { case granted; case denied(reason: UInt8) }
public protocol ANP1CredentialProvider: AnyObject {
    func ephemeralPublicKey() -> Data                                     // 65 B, baru per AUTH0
    func verifyReader(_ h: ANP1Handshake, signature: Data) -> Bool
    func sealIdentity(_ h: ANP1Handshake, header: Data) throws -> Data    // AUTH1, seq 0
    func sealCertificate(header: Data) throws -> Data                     // GET_CERT, seq 1
    func openResult(_ sealed: Data, header: Data) throws -> ANP1Result    // RESULT, seq 0 arah reader→ponsel
}
// ANP1Responder: + `public private(set) var outcome: ANP1Result?`
```
- Produces (ANCrypto):
```swift
public protocol CredentialSigner: Sendable { func sign(_ message: Data) throws -> Data }   // ECDSA raw 64 B
public protocol CounterStore: Sendable { func next(for credentialID: Data) throws -> UInt32 }
public struct CredentialMaterial: Sendable {
    credentialID: Data /*16*/; certificate: Data /*CBOR ≤ 200 B*/; notAfter: Date; suspended: Bool
    groupKeys: [Data: [P256.Signing.PublicKey]]   // group_id (8 B) → [aktif, berikutnya]
}
public struct ANP1ReaderVerifier: Sendable { let verify: @Sendable (Data, Data, [P256.Signing.PublicKey]) -> Bool; static let live }
public final class ANP1PhoneSession: ANP1CredentialProvider {
    init(material:, signer:, counters:, now: Date = .now, ephemeral: P256.KeyAgreement.PrivateKey = .init(), verifier: ANP1ReaderVerifier = .live)
}
```
- Produces (ANTestSupport): `SoftwareReader(groupKey: P256.Signing.PrivateKey, groupID: Data)` dengan `func run(against responder: inout ANP1Responder, credentialKey: P256.Signing.PublicKey, sendGetCert: Bool, result: ANP1Result) throws -> ANP1Result?`. Fungsi ini menjalankan SELECT → AUTH0 → AUTH1 → (GET_CERT) → RESULT, mendekripsi AUTH1, lalu memverifikasi `sig_P`.

Keputusan format (catat ke SDD §7.4/§7.6 di Task 3):
- Plaintext AUTH1 = TLV `E1 cred_id(16) ‖ E2 counter(4, big-endian) ‖ E3 cert_hash(8) ‖ E4 sig_P(64)`. `cert_hash = SHA-256(certificate)[0..<8]`.
- Plaintext GET_CERT = byte `CredentialCert` mentah. Plaintext RESULT = TLV `F1 status(1: 00 granted, 01 denied) ‖ F2 reason(1)`.
- AAD = header (`CLA INS P1 P2`) APDU perintah yang membawa atau meminta pesan itu.
- Counter diambil (`CounterStore.next`) **sebelum** `sig_P` dibuat.
- Sertifikat kedaluwarsa (`now > notAfter`) atau `suspended` → `ANP1Failure.credentialSuspended` (`6985`), dan ini hanya bisa terjadi setelah `sig_R` valid.
- Group tak dikenal → verifikasi tetap dijalankan sekali terhadap kunci dummy tetap, lalu `false`.
- RESULT gagal dibuka (tag GCM salah) → `6A80` dan `outcome` tetap `nil`.

- [ ] **Step 1: Tulis test gagal** di `PhoneSessionTests.swift` (memakai `SoftwareReader` + signer software):
```swift
@Test func transaksiLengkapGranted()            // TC-PROTO-03: run(..., sendGetCert: false, result: .granted) == .granted; responder.outcome == .granted
@Test func jalurGetCert()                       // TC-PROTO-08: sendGetCert: true → cert terdekripsi == material.certificate; semua respons < 255 B
@Test func replayAuth1DariTransaksiLamaDitolak() // TC-PROTO-06: sig_R transaksi 1 dipakai di transaksi 2 → respons == Data([0x69,0x82])
@Test func resultDimodifikasiDitolak()          // TC-PROTO-07: flip 1 bit ciphertext RESULT → respons == Data([0x6A,0x80]); outcome == nil
@Test func sertifikatKedaluwarsa6985SetelahSigRValid()  // sig_R valid → 6985; sig_R salah → 6982 (tidak bocor)
@Test func groupTakDikenalTetapMenjalankanSatuVerifikasi() // Review Focus 1: verifier spy dipanggil tepat 1× dengan daftar kunci tak kosong; hasil false
@Test func counterDiambilSekaliPerAuth1()        // CounterStore fake: next dipanggil 1×; E2 == nilai itu
@Test func fuzzApduTidakCrash()                  // TC-PROTO-13: 10.000 input acak (seed tetap) → setiap respons berakhir SW valid, < 255 B, tanpa crash
```
- [ ] **Step 2:** `swift test --package-path Packages --filter PhoneSessionTests` → GAGAL (tipe belum ada).
- [ ] **Step 3:** Ubah `ANP1Responder` ke protokol baru: GET_CERT/RESULT hanya di state `.authenticated`; RESULT mengisi `outcome` lalu kembali ke `.idle`. Implementasikan `ANP1PhoneSession` dengan `ANP1KeySchedule.derive` dan `ANP1SessionKeys.seal/open` yang sudah ada.
- [ ] **Step 4:** Test host dan simulator → lulus (termasuk test lama `ResponderTests`).
- [ ] **Step 5: Commit** — `feat(protocol): ANP/1 lengkap dengan sesi kriptografi ponsel`

### Task 3: Test vector bersama ANP/1 (TC-PROTO-01) + dokumentasi format

**Files:**
- Create: `scripts/anp1/gen_vectors.py`, `scripts/anp1/requirements.txt` (`cryptography==49.*`, `cbor2`), `Packages/Tests/ANCryptoTests/Resources/anp1-v1.json`, `Packages/Tests/ANCryptoTests/TestVectorTests.swift`
- Modify: `Packages/Package.swift` (`ANCryptoTests` → `resources: [.copy("Resources")]`), `docs/SDD.md` §7.4/§7.6/§7.11 (keputusan format Task 2), `docs/QA_SUITE.md` (rujukan file vector di TC-PROTO-01)

**Interfaces:**
- Produces: `anp1-v1.json`, kontrak untuk firmware reader. Field berisi hex: `group_priv`, `group_id`, `reader_eph_priv`, `phone_eph_priv`, `cred_priv`, `txn_id`, `cred_id`, `counter`, `certificate`, `sig_r`, `sig_p`. Field `expected` berisi: `transcript`, `k_pr`, `k_rp`, `iv_base`, `auth1_plaintext`, `auth1_ciphertext` (seal dengan K_pr, seq 0, AAD `80120000`), `result_plaintext_granted`, `result_ciphertext_granted` (K_rp, seq 0, AAD `80160000`).

- [ ] **Step 1:** Tulis `gen_vectors.py` **hanya** dengan pustaka `cryptography` (implementasi independen dari Swift). Skalar privat tetap (32 B) ditulis di skrip; ECDSA acak, jadi `sig_r`/`sig_p` dibuat sekali lalu disimpan. Jalankan `python3 scripts/anp1/gen_vectors.py > Packages/Tests/ANCryptoTests/Resources/anp1-v1.json`.
- [ ] **Step 2: Tulis test gagal:**
```swift
@Test func transcriptSamaDenganVector()      // ANP1.transcript(...) == expected.transcript
@Test func kunciSesiSamaDenganVector()       // derive(phone_eph_priv, reader_eph_pub, txn, group) → k_pr/k_rp/iv_base sama; sisi reader juga
@Test func ciphertextAuth1SamaDenganVector() // seal(auth1_plaintext) == auth1_ciphertext; open → plaintext
@Test func ciphertextResultSamaDenganVector()
@Test func tandaTanganVectorValid()          // verifyReader(sig_r) true; sig_p valid atas phoneMessage(T, cred_id, counter)
@Test func semuaPesanVectorDiBawah255()
```
- [ ] **Step 3:** Jalankan test → gagal hanya bila ada perbedaan format. Perbaiki sisi yang menyimpang dari SDD §7.6, bukan vector-nya. Lulus di host dan simulator.
- [ ] **Step 4:** Perbarui SDD §7.4/§7.6 (tag E1–E4/F1–F2, `cert_hash`, AAD respons, seq per pesan) dan §7.11 (path vector). Jalankan `python3 scripts/docs/check_docs.py .` → `problems: 0`.
- [ ] **Step 5: Commit** — `test(protocol): test vector bersama ANP/1 v1`

### Task 4: Kunci Secure Enclave, autentikasi pengguna, counter

**Files:**
- Create: `Packages/Sources/ANCrypto/UserAuthenticator.swift`, `Packages/Sources/ANStorage/CredentialKeyStore.swift`, `Packages/Sources/ANStorage/KeychainCounterStore.swift`, `Packages/Sources/ANStorage/CredentialRecordStore.swift`, `Packages/Tests/ANStorageTests/CredentialKeyStoreTests.swift`
- Modify: `Packages/Sources/ANStorage/SecretStore.swift` (aksesibilitas per item), `Packages/Package.swift` (`ANStorage` → `ANCrypto`)

**Interfaces:**
- Consumes: `CredentialSigner`, `CounterStore` (Task 2), `CredentialKeyPolicy` (scaffold).
- Produces:
```swift
// ANCrypto
public struct AuthorizedContext: @unchecked Sendable { public let laContext: LAContext }
public protocol UserAuthenticator: Sendable { func authenticate(reason: String) async throws -> AuthorizedContext }
public struct LAUserAuthenticator: UserAuthenticator   // evaluatePolicy(.deviceOwnerAuthentication); konteks yang sama dipakai untuk tanda tangan SE (SDD §6.1)
// ANStorage
public enum SecretAccessibility: Sendable { case afterFirstUnlockThisDeviceOnly, whenPasscodeSetThisDeviceOnly }
// SecretStore.set(_ data: Data, for key: String, accessibility: SecretAccessibility) throws
public protocol CredentialKeyStore: Sendable {
    func createKey(for credentialID: Data) throws -> Data            // kunci publik x963 65 B
    func signer(for credentialID: Data, context: AuthorizedContext) throws -> any CredentialSigner
    func hasKey(for credentialID: Data) -> Bool
    func deleteKey(for credentialID: Data) throws
}
public struct SecureEnclaveKeyStore: CredentialKeyStore   // SecureEnclave.P256.Signing.PrivateKey + CredentialKeyPolicy; dataRepresentation → SecretStore(.whenPasscodeSetThisDeviceOnly)
public struct SoftwareKeyStore: CredentialKeyStore        // test & preview
public struct KeychainCounterStore: CounterStore          // init(store: any SecretStore)
// Sertifikat + kunci publik reader group per kredensial (SDD §5.3: Keychain …ThisDeviceOnly)
public struct CredentialRecord: Codable, Equatable, Sendable {
    credentialID: Data; certificate: Data; notAfter: Date
    groupKeys: [String: [Data]]   // hex group_id → [x963 aktif, x963 berikutnya]; format sama dengan ProvisionedCredential (Task 8)
    func material(suspended: Bool) throws -> CredentialMaterial
}
public protocol CredentialRecordStore: Sendable {
    func save(_ record: CredentialRecord) throws
    func record(for credentialID: Data) throws -> CredentialRecord?
    func delete(_ credentialID: Data) throws
}
public struct KeychainCredentialRecordStore: CredentialRecordStore   // init(store: any SecretStore); .afterFirstUnlockThisDeviceOnly
```

- [ ] **Step 1: Tulis test gagal:**
```swift
@Test func counterNaikLintasInstance()   // Review Focus 5: store A next → 1,2; store B (SecretStore sama) next → 3
@Test func counterTidakTerulangSaatParalel() // 100 panggilan konkuren → 100 nilai unik
@Test func kunciPerangkatDisimpanDenganAksesibilitasPasscode() // SecretStore spy: blob kunci memakai .whenPasscodeSetThisDeviceOnly
@Test func recordMenjadiMaterial()       // save → record(for:) sama; material(suspended: false).groupKeys[groupID]?.count == 2
@Test(.enabled(if: ProcessInfo.processInfo.environment["AN_DEVICE_TESTS"] == "1"))
func kunciSecureEnclaveTidakDapatDiekspor() // TC-ENR-13 (tipe H): kunci SE dibuat; atribut sesuai ADR-0009
```
- [ ] **Step 2:** Test → GAGAL.
- [ ] **Step 3:** Implementasikan. `KeychainCounterStore.next` harus atomik (kunci internal) dan menyimpan nilai baru **sebelum** mengembalikannya.
- [ ] **Step 4:** Test host dan simulator → lulus (test SE dilewati di luar perangkat).
- [ ] **Step 5: Commit** — `feat(storage): kunci Secure Enclave, autentikasi, counter monoton`

### Task 5: Metadata kartu (SwiftData) + deteksi restore

**Files:**
- Create: `Packages/Sources/ANCore/Card.swift`, `Packages/Sources/ANStorage/CardStore.swift`, `Packages/Sources/ANStorage/SwiftDataCardStore.swift`, `Packages/Sources/ANStorage/RestoreCheck.swift`, `Packages/Tests/ANStorageTests/CardStoreTests.swift`

**Interfaces:**
- Consumes: `CardLimit` (scaffold), `CredentialKeyStore` (Task 4).
- Produces:
```swift
// ANCore — status FR-38 + "Perlu dipindahkan" (SDD §5.3)
public enum CardStatus: String, Codable, Sendable { case active, pendingApproval, suspended, needsRenewal, revoked, needsTransfer }
public struct Card: Identifiable, Codable, Equatable, Sendable {
    id: UUID; name: String; siteName: String; zones: [String]; status: CardStatus
    credentials: [ChannelKind: Data]   // kanal → cred_id
    notAfter: Date?
}
// ANStorage
public protocol CardStore: Sendable {
    func all() async throws -> [Card]
    func add(_ card: Card) async throws          // ANError.cardLimitReached bila sudah 8
    func update(_ card: Card) async throws
    func remove(id: UUID) async throws
}
public actor SwiftDataCardStore: CardStore { init(directory: URL) throws }   // file protection .complete + isExcludedFromBackup = true
public enum RestoreCheck { static func reconcile(_ cards: [Card], keys: any CredentialKeyStore) -> [Card] }
```
- [ ] **Step 1: Tulis test gagal:**
```swift
@Test func kartuKesembilanDitolak()            // TC-ENR-11 (sisi app): 8× add sukses, ke-9 throws ANError.cardLimitReached
@Test func storeDikecualikanDariBackup()       // resourceValues(.isExcludedFromBackupKey) == true pada direktori store
@Test func dataBertahanLintasInstance()        // add → instance baru → all() berisi kartu yang sama
@Test func kunciHilangMenandaiPerluDipindahkan() // Review Focus 3: SoftwareKeyStore tanpa kunci cred → status == .needsTransfer; kartu lain tak berubah
```
- [ ] **Step 2:** Test → GAGAL. **Step 3:** Implementasikan dengan `ModelContainer` di `directory`. Model SwiftData internal memetakan ke/dari `Card`. **Step 4:** Test host dan simulator → lulus.
- [ ] **Step 5: Commit** — `feat(storage): metadata kartu & deteksi restore`

### Task 6: Presentasi N-HCE (`CardSession`)

**Files:**
- Create: `Packages/Sources/ANChannelNFC/CardEmulation.swift` (protokol + fake-friendly tipe), `Packages/Sources/ANChannelNFC/HCEPresentmentCoordinator.swift`, `Packages/Sources/ANChannelNFC/LiveCardEmulation.swift` (`#if os(iOS)`), `Packages/Tests/ANChannelNFCTests/HCEPresentmentTests.swift`
- Modify: `docs/SDD.md` §5.4 (`CredentialSession.isEligible` adalah `get async throws` di SDK iOS 27.2; diamati langsung dari `SecureElementCredential.swiftinterface`). Tambahkan bukti ke `docs/research/RESEARCH_EVIDENCE.md` dan jalankan `jev_verify` atas klaim itu.

**Interfaces:**
- Consumes: `NFCGate`, `PresentmentLimits` (scaffold); `ANP1Responder`, `ANP1CredentialProvider` (Task 2); `UserAuthenticator`, `AuthorizedContext` (Task 4).
- Produces:
```swift
public enum CardEmulationEvent: Sendable { case sessionStarted, readerDetected, received(Data), readerDeselected, invalidated }
public enum CardEmulationError: Error, Sendable { case transmission, other }
public protocol CardEmulationSession: AnyObject {
    var events: AsyncStream<CardEmulationEvent> { get }
    var alertMessage: String { get set }
    func startEmulation() async throws
    func respond(_ response: Data) async throws(CardEmulationError)   // menjawab APDU terakhir
    func stopEmulation(success: Bool) async
    func invalidate()
}
public protocol PresentmentIntentProvider: Sendable { func acquire() async throws -> AnyObject }  // live: NFCPresentmentIntentAssertion.acquire(); dilepas dengan melepas referensi (deinit)
public actor HCEPresentmentCoordinator {
    init(gate: NFCGate, config: RemoteConfig, authenticator: any UserAuthenticator, intents: any PresentmentIntentProvider,
         makeSession: @escaping @Sendable () async throws -> any CardEmulationSession,
         makeProvider: @escaping @Sendable (AuthorizedContext) throws -> any ANP1CredentialProvider,
         clock: any Clock<Duration> = ContinuousClock())
    func present() -> AsyncStream<PresentmentEvent>
    func cancel()     // dipanggil saat scenePhase != .active
}
```
Aturan state (SDD §6.1): autentikasi dulu, lalu assertion; bila assertion ditolak, tunggu 15 dtk lalu coba sekali lagi. `readerDetected` → `startEmulation` → APDU dijawab oleh `ANP1Responder`. `outcome` granted/denied → `stopEmulation(success:)` → `invalidate` → lepas assertion. Batas 60 dtk tanpa transaksi selesai → `.timedOut`. Bila `transmission` error, kirim ulang sekali; bila gagal lagi, kembali ke `.waitingForReader` (sesi tetap hidup hingga batas 60 dtk). `alertMessage` = string lokal `present.hold_near_reader` ("Dekatkan bagian atas iPhone ke pembaca kartu").

- [ ] **Step 1: Tulis test gagal** (fake session, fake intents, `TestClock`, `SoftwareReader` mengirim APDU lewat fake session):
```swift
@Test func grantMenghentikanEmulasiSukses()      // TC-PRSN-01 (logika): events berakhir .granted; stopEmulation(success: true); invalidate; intent dilepas
@Test func autentikasiBatalTanpaAssertion()      // TC-PRSN-03: events == [.cancelled]; intents.acquireCount == 0; makeSession tak dipanggil
@Test func timeout60Detik()                      // TC-PRSN-04: tanpa reader, maju 60 dtk → .timedOut; invalidate
@Test func cooldown15Detik()                     // TC-PRSN-05: acquire ditolak → tidak dipanggil lagi sebelum 15 dtk; dipanggil tepat 1× setelahnya
@Test func readerDeselectedKembaliMenunggu()     // TC-PRSN-15: event terakhir sebelum reader baru == .waitingForReader
@Test func transmissionErrorRetrySekali()        // TC-PRSN-16: respond gagal 2× → tepat 2 percobaan; lalu .waitingForReader
@Test func backgroundMembatalkanSesi()           // Review Focus 2: cancel() saat emulasi → .cancelled; invalidate; intent dilepas
@Test func gatingGagalTidakMembuatSesi()         // TC-ELG-02/03: notEligible → makeSession tak dipanggil; events == [.cancelled]
```
- [ ] **Step 2:** Test → GAGAL. **Step 3:** Implementasikan coordinator, lalu adapter live (`CardSession` + `eventStream`, `NFCPresentmentIntentAssertion`). **Step 4:** Test host dan simulator → lulus; build app.
- [ ] **Step 5:** Perbarui SDD §5.4, tambahkan ID bukti, `jev_verify`, lalu `check_docs.py` → 0 masalah.
- [ ] **Step 6: Commit** — `feat(nfc): presentasi N-HCE dengan batas sesi & cooldown`

### Task 7: Presentasi kanal B (BLE Tap)

**Files:**
- Create: `Packages/Sources/ANChannelBLE/BLEUUIDs.swift`, `Packages/Sources/ANChannelBLE/BLECentral.swift` (protokol), `Packages/Sources/ANChannelBLE/BLETapCoordinator.swift`, `Packages/Sources/ANChannelBLE/LiveBLECentral.swift` (`CBCentralManager`), `Packages/Tests/ANChannelBLETests/BLETapTests.swift`
- Modify: `docs/SDD.md` §6.3 (UUID service/karakteristik yang dibuat), §7.9 (pemetaan frame ↔ APDU)

**Interfaces:**
- Consumes: `BLEFrame`, `BLEFrameAssembler`, `ANP1Responder` (scaffold/Task 2); `UserAuthenticator` (Task 4).
- Produces:
```swift
public enum BLEUUIDs { static let service, control, response: CBUUID }   // UUIDv4 dari `uuidgen`, dicatat di SDD §6.3
public struct BLEReaderAdvertisement: Equatable, Sendable { id: UUID; groupID: Data; rssi: Int }
public protocol BLELink: Sendable {
    var mtu: Int { get }
    var commands: AsyncThrowingStream<Data, Error> { get }   // indikasi `ANP-Response` (frame reader → ponsel)
    func write(_ frame: Data) async throws                   // `ANP-Control` (frame ponsel → reader)
    func disconnect() async
}
public protocol BLECentral: Sendable {
    func scan(for duration: Duration) async throws -> [BLEReaderAdvertisement]
    func connect(_ id: UUID) async throws -> any BLELink
}
public enum BLEReaderSelector { static func choose(_ ads: [BLEReaderAdvertisement], threshold: Int = -55) -> BLEReaderAdvertisement? }
public struct ReaderRateLimiter: Sendable { mutating func allow(_ readerID: UUID, at: ContinuousClock.Instant) -> Bool }   // 1 per 3 dtk
public actor BLETapCoordinator {
    init(central: any BLECentral, authenticator: any UserAuthenticator,
         makeProvider: @escaping @Sendable (AuthorizedContext) throws -> any ANP1CredentialProvider,
         isForeground: @escaping @Sendable () -> Bool, clock: any Clock<Duration> = ContinuousClock())
    func tap() -> AsyncStream<PresentmentEvent>
}
```
Pemetaan frame: setelah connect, ponsel menulis `HELLO` berisi FCI. Responder di-SELECT secara internal. Frame perintah dari reader (`type` = INS) diubah menjadi `CommandAPDU(cla: 0x80, ins: type, data: payload)`, sehingga AAD = header `80 INS 00 00`, sama seperti NFC. Frame respons memakai `type` yang sama dengan payload = body ‖ SW (2 B). Fragmentasi memakai `mtu` link.

- [ ] **Step 1: Tulis test gagal** (fake central/link + `SoftwareReader` versi frame):
```swift
@Test func pilihRSSITertinggiDiAtasAmbang()  // TC-PRSB-04: [-50, -60] → reader -50 yang di-connect
@Test func diBawahAmbangTidakAdaTransaksi()   // TC-PRSB-05: [-70] → connect tak dipanggil; events == [.waitingForReader, .timedOut]
@Test func rateLimitTigaDetik()               // TC-PRSB-06: tap kedua < 3 dtk ke reader sama → connect tetap 1×
@Test func mtuKecilTetapGrant()               // TC-PRSB-08: mtu 23 → .granted
@Test func tidakJalanDiBackground()           // TC-PRSB-07: isForeground false → scan tak dipanggil; events == [.cancelled]
@Test func bluetoothMatiDiTengahTransaksi()   // Review Focus 4: commands melempar error → event terakhir .cancelled; disconnect dipanggil; stream selesai
```
- [ ] **Step 2:** Test → GAGAL. **Step 3:** Implementasikan coordinator dan adapter live (`CBCentralManager`, filter service UUID, `maximumWriteValueLength(for: .withResponse)` untuk MTU). **Step 4:** Test host dan simulator → lulus; build app.
- [ ] **Step 5:** Perbarui SDD §6.3/§7.9; `check_docs.py` → 0 masalah.
- [ ] **Step 6: Commit** — `feat(ble): presentasi Tap BLE dengan pemilihan RSSI & rate-limit`

### Task 8: Kontrak provisioning & error API (draf)

**Files:**
- Modify: `Packages/Sources/ANNetworking/APIClient.swift`
- Create: `Packages/Sources/ANNetworking/ProvisionedCredential.swift`, `Packages/Sources/ANNetworking/ProblemDetails.swift`, `Packages/Tests/ANNetworkingTests/APIClientTests.swift` (+ target test di `Package.swift`)

**Interfaces:**
- Produces:
```swift
public struct ProblemDetails: Decodable, Error, Equatable, Sendable { type: String; title: String?; status: Int }   // RFC 9457; `type` = kode katalog SDD §15
public struct ProvisionedCredential: Codable, Equatable, Sendable {
    credentialID: Data; channel: ChannelKind; certificate: Data; notAfter: Date
    siteName: String; zones: [String]
    groupKeys: [String: [Data]]   // hex group_id → [x963 aktif, x963 berikutnya]
}   // JSON: Data = base64, Date = ISO 8601
// APIClient
func submitCredentialKey(enrollmentID: String, channel: ChannelKind, publicKey: Data, idempotencyKey: UUID) async throws -> ProvisionedCredential   // POST /v1/enrollments/{id}/credentials (FR-16)
```
- [ ] **Step 1: Tulis test gagal:**
```swift
@Test func problemJsonDipetakan()        // 409 application/problem+json type "ENR-LIMIT" → throws ANError.cardLimitReached (TC-ENR-11 sisi server)
@Test func postMembawaIdempotencyKey()   // header Idempotency-Key == uuidString
@Test func provisionedCredentialDecode() // fixture JSON → base64/ISO 8601 terdekode benar
```
- [ ] **Step 2:** GAGAL. **Step 3:** Implementasikan dengan `HTTPTransport` yang sudah ada. Beri komentar bahwa kontrak masih draf hingga rencana backend (ADR-0014). **Step 4:** Lulus.
- [ ] **Step 5: Commit** — `feat(networking): kontrak provisioning & RFC 9457 (draf)`

### Task 9: Provisioning lab (DEBUG saja)

**Files:**
- Create: `scripts/anp1/lab_ca.py`, `scripts/anp1/test_lab_ca.py`, `Packages/Sources/ANFeatures/Lab/LabProvisioning.swift` (`#if DEBUG`), `Packages/Tests/ANFeaturesTests/LabProvisioningTests.swift` (+ target test)

**Interfaces:**
- Consumes: `ProvisionedCredential` (Task 8), `CredentialKeyStore` + `CredentialRecordStore` + `CredentialRecord.material(suspended:)` (Task 4), `CardStore` + `Card` (Task 5).
- Produces: `lab_ca.py init --site-id <hex8>` (membuat Site CA + reader group key di `scripts/anp1/.lab/`, yang di-ignore) dan `lab_ca.py issue --pubkey <hex65> --channel ble|nfcHCE` (mencetak JSON `ProvisionedCredential`; `CredentialCert` CBOR COSE_Sign1 sesuai SDD §7.3, `not_after` +7 hari). Di app (`#if DEBUG`):
```swift
enum LabProvisioning {
    static func begin(keys: any CredentialKeyStore) throws -> (credentialID: Data, publicKey: Data)
    static func complete(json: Data, records: any CredentialRecordStore, cards: any CardStore) async throws -> Card
}
```

- [ ] **Step 1: Tulis test gagal:** `python3 -m unittest scripts/anp1/test_lab_ca.py` (sertifikat ≤ 200 B, COSE_Sign1 terverifikasi dengan kunci publik CA) dan Swift:
```swift
@Test func imporJSONLabMenghasilkanKartuAktif()   // fixture → Card.status == .active; credentials[.ble] == cred_id
@Test func imporDitolakBilaSudahDelapanKartu()     // ANError.cardLimitReached; tidak ada record yatim yang tersisa (FR-19)
```
- [ ] **Step 2:** GAGAL. **Step 3:** Implementasikan. Kode lab hanya ada di `#if DEBUG` dan tidak terlihat di build Release; cek dengan `nm`/strings pada build Release bahwa simbol `LabProvisioning` tidak ada. **Step 4:** Lulus.
- [ ] **Step 5: Commit** — `feat(lab): provisioning kredensial lab untuk uji M1`

### Task 10: UI tracer bullet + composition root

**Files:**
- Create: `Packages/Sources/ANFeatures/Keys/KeysViewModel.swift`, `Packages/Sources/ANFeatures/Keys/CardDetailView.swift`, `Packages/Sources/ANFeatures/Present/PresentationSheet.swift`, `Packages/Sources/ANFeatures/Present/PresentationViewModel.swift`, `Packages/Sources/ANFeatures/Lab/LabView.swift` (`#if DEBUG`), `App/AppEnvironment.swift`, `Packages/Tests/ANFeaturesTests/StringCatalogTests.swift`, `Packages/Tests/ANFeaturesTests/PresentationViewModelTests.swift`
- Modify: `Packages/Sources/ANFeatures/KeysView.swift`, `Packages/Sources/ANFeatures/Resources/Localizable.xcstrings`, `App/AnastropheApp.swift`

**Interfaces:**
- Consumes: semua task sebelumnya; `ChannelSelector.preferred` (scaffold); `HCEPresentmentCoordinator.present/cancel` (Task 6); `BLETapCoordinator.tap` (Task 7).
- Produces: `@Observable final class PresentationViewModel { init(events: AsyncStream<PresentmentEvent>); var phase: Phase }` dengan `enum Phase { case waiting, exchanging, granted, denied(DenyReason), timedOut, cancelled }`. `AppEnvironment.live` / `.preview` merangkai store, gate, dan coordinator. `scenePhase != .active` → `cancel()` (Review Focus 2).

- [ ] **Step 1: Tulis test gagal:**
```swift
@Test func setiapStringPunyaIdDanEn()            // semua key di Localizable.xcstrings punya lokalisasi "id" dan "en"
@Test func teksPresentasiTanpaJargon()           // TC-PRSN-17: nilai key "present.*" tidak memuat "NFC", "HCE", "APDU" (case-insensitive)
@Test func urutanEventMenjadiFase()              // [.waitingForReader, .exchanging, .granted] → phase akhir .granted
@Test func kartuPerluDipindahkanTidakBisaDipresentasikan() // status .needsTransfer → tombol "Gunakan kartu" nonaktif + teks alasan
```
- [ ] **Step 2:** GAGAL. **Step 3:** Implementasikan. Ikuti `docs/design-system/anastrophe/pages/ios-app.md`: satu aksi utama per layar, kartu sebagai baris datar, `ANColor`, Dynamic Type. **Step 4:** Test lulus; build app.
- [ ] **Step 5:** Verifikasi visual di simulator: jalankan app, buka Lab → tambah kartu → detail → "Gunakan kartu". Screenshot (`xcrun simctl io <udid> screenshot`) dalam mode terang/gelap dan pada ukuran teks AX5 (`xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`); tidak boleh ada teks terpotong (NFR-A01).
- [ ] **Step 6: Commit** — `feat(ui): alur pilih kartu & presentasi tracer bullet`

### Task 11: Verifikasi end-to-end lab (tipe H) & gerbang M1 sisi app

**Files:**
- Modify: `docs/QA_SUITE.md` (catat hasil TC-PROTO-01/03/08, TC-PRSB-01/04/05/06/08, TC-PRSN-01/03/04/05/15/16 dengan tanggal, perangkat, dan versi build)

- [ ] **Step 1:** Jalankan semua perintah standar → semua lulus. Jalankan juga `AN_DEVICE_TESTS=1` di iPhone fisik untuk TC-ENR-13.
- [ ] **Step 2 (H, BLE):** iPhone + reader uji yang menjalankan `anp1-v1` (firmware referensi, atau peripheral uji dari rencana reader). Kriteria lulus: grant ≤ 1,5 dtk p95 (NFR-P04) dari 20 tap.
- [ ] **Step 3 (H, N-HCE):** Hanya bila entitlement HCE dev sudah ada (`AN_NFC_EMULATION = YES`, wilayah eligible). Kriteria lulus: grant; total p95 ≤ 500 ms (NFR-P01). Bila entitlement belum ada, tandai **tertunda (D1/ADR-0017)** dan jangan dianggap lulus.
- [ ] **Step 4:** `check_docs.py` → 0 masalah; `jev_gate` dengan klaim "Tracer bullet R1 sisi app selesai" + bukti uji. Status < 0,80 atau escape → laporkan ke pengguna.
- [ ] **Step 5: Commit** — `docs(qa): hasil verifikasi tracer bullet R1`
