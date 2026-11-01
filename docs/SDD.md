# SDD — Anastrophe: Software Design Document

| Item | Nilai |
|---|---|
| Versi dokumen | 2.0 (Draft untuk review) |
| Tanggal | 2026-11-01 |
| Status | Draft — 2 keputusan menunggu manusia: ADR-0014 (topologi backend), ADR-0017 (entitas hukum) |
| Dokumen terkait | [PRD](PRD.md) · [QA Suite](QA_SUITE.md) · [Research Evidence](research/RESEARCH_EVIDENCE.md) · [ADR](adr/README.md) · [Glosarium](../GLOSSARY.md) · [Design system iOS](design-system/anastrophe/pages/ios-app.md) |
| Lapisan keputusan | JEV (`jev_decide`) — ADR-0018 |

### Riwayat versi

| Versi | Tanggal | Ringkasan perubahan |
|---|---|---|
| 1.0 | 2026-11-01 | Draft awal: satu jalur NFC in-app, protokol challenge–response sederhana. |
| 2.0 | 2026-11-01 | Abstraksi tiga kanal (W/N/B); desain `CredentialSession` (personalisasi wired) dan BLE; **ANP/1 didesain ulang** (ECDH ephemeral, reader group diautentikasi lebih dulu, identitas terenkripsi, semua APDU < 255 B). Backend: kartu ↔ kredensial per kanal, perpanjangan sertifikat 7 hari, sengketa klaim, hapus akun. Reader referensi + gateway OSDP Transparent Mode. Keamanan, privasi, infrastruktur, observabilitas, katalog error. ADR dipindah ke `docs/adr/` dan diputuskan lewat JEV. |
| 2.1 | 2026-11-01 | ANP/1: format plaintext AUTH1/GET_CERT/RESULT, `cert_hash`, AAD respons, dan seq per pesan dipatok (§7.4, §7.6); penyamaan kerja verifikasi pada jalur `6982`; test vector v1 (§7.11). |
| 2.2 | 2026-11-01 | Perpanjangan sertifikat (ADR-0023): pemicu hanya setelah autentikasi tap (§5.5), challenge + format bukti kepemilikan (§8.4.2), endpoint (§8.5), kode `CRED-*` (§15). |
| 2.3 | 2026-11-01 | Audit log berantai hash per gedung (ADR-0024): kolom `chain`/`site_id`/`seq`, append-only, rumus hash (§8.1). |
| 2.4 | 2026-11-01 | Audit: tag hash `ANP1-AUDIT-v1`, data = teks `jsonb`, CHECK chain kanonik, batas deteksi dan head per jam (§8.1, §11), pseudonim sejak ditulis (§8.4.6, ADR-0025). |
| 2.5 | 2026-11-01 | Hapus kartu (ADR-0026): `DELETE /cards/{id}` dengan bukti kepemilikan kunci (§8.5), kode `CARD-*` (§15). |
| 2.6 | 2026-11-01 | Hapus kartu: kartu SUSPENDED bisa dihapus dan 410 `CARD-GONE` (ADR-0027), kartu tanpa kunci dihapus lokal (ADR-0028), `:challenge` memuat `card_instance_id` dan tidak lagi menegakkan kill switch (§8.4.2, §8.5, §15). |

> Konvensi REA: klaim platform memakai ID bukti (E/O/I/U) dari ledger riset. Keputusan desain ada di ADR (`docs/adr/`). Istilah mengikuti `GLOSSARY.md`.

---

## 1. Tujuan & cakupan

Dokumen ini menjabarkan desain teknis untuk memenuhi PRD v2.1: aplikasi iOS Anastrophe, backend, portal admin, reader referensi & Edge Gateway, serta integrasi Apple Wallet Access (R2).

**Di luar cakupan:** desain elektronik rinci reader (hanya spesifikasi fungsional); Android; pembayaran.

## 2. Batasan platform yang membentuk desain

| # | Batasan | Bukti | Konsekuensi desain |
|---|---|---|---|
| C1 | Emulasi kartu in-app hanya **ISO 7816-4 (APDU)** di atas ISO 14443-4, untuk AID yang terdaftar di entitlement. | O-A01, O-A02, O-A09 | Protokol berbasis AID sendiri (ANP/1, §7). |
| C2 | **UID iPhone diacak per tap.** | O-A23 | UID tidak pernah dipakai sebagai identitas/otentikasi (ADR-0001). |
| C3 | N-HCE: hanya EEA, emulasi ≤ 60 dtk, UI modal sistem. | O-A01, O-A03, O-A04 | State machine dengan timeout & retry (§6.1). |
| C4 | Presentment assertion N-HCE: 15 dtk + cooldown 15 dtk, hanya foreground. | O-A05 | Assertion hanya saat intent aktif. |
| C5 | N-SE: satu sesi aktif per app; sesi diinvalidasi saat background; mode wired timeout 15 dtk; maks 2 assertion/80 dtk; applet dari ABR; otorisasi oleh UI sistem. | O-A17–O-A21 | Adapter SE (§6.2) dengan pemulihan sesi. |
| C6 | Entitlement N mensyaratkan wilayah eligible **dan** pengembang *established* di wilayah tersebut. | O-A08, E03 | Gating server (§5.4); ADR-0017. |
| C7 | Core NFC dapat **membaca** tag ISO 7816/15693/FeliCa/MIFARE. | O-A14 | Enrolment memakai kartu fisik sebagai bukti kepemilikan (§8.4). |
| C8 | Kanal W: reader ECP v2.3 + TCI, sertifikasi IOT Apple, SLA 99,99%, DR ≤ 30 menit, s2s JWT/mTLS. | O-W07, O-W13–O-W16 | Layanan integrasi Apple terpisah (§6.4); arsitektur siap multi-region (ADR-0014). |
| C9 | BLE background wajib filter service UUID, lebih lambat, tidak pulih otomatis setelah Bluetooth reset. | O-B04 | R1 hanya Tap di foreground (ADR-0012). |
| C10 | UI in-app tidak boleh mirip Apple Wallet/Apple Pay. | O-A10 | Design system sendiri. |
| C11 | Simulator tidak mendukung `CardSession`/`CredentialSession`. | O-A16 | Uji HIL dengan iPhone + reader nyata. |
| C12 | App wajib menyediakan penghapusan akun in-app. | O-P01 | Alur hapus akun (§8.4.6). |
| C13 | Minimum iOS 26.0 (iPhone 11+/SE 2+). | O-D01, ADR-0006 | Satu jalur kode untuk semua wilayah N-SE. |

## 3. Arsitektur sistem

### 3.1 Diagram konteks

```mermaid
flowchart LR
  USER(["Pengguna iPhone"])
  ADMIN(["Admin gedung"])
  APP["Anastrophe iOS App"]
  PORTAL["Portal Admin Web"]
  CLOUD["Anastrophe Cloud"]
  READER["Reader / Edge Gateway di gedung"]
  ACS["ACS / panel operator"]
  APPLE["Apple Access Platform (R2) + APNs + ABR"]
  USER --> APP
  ADMIN --> PORTAL
  APP <-->|"HTTPS"| CLOUD
  PORTAL <-->|"HTTPS"| CLOUD
  APP <-->|"NFC ANP/1 atau BLE ANP/1"| READER
  READER -->|"OSDP / Wiegand"| ACS
  READER <-->|"MQTT mTLS sinkron"| CLOUD
  CLOUD <-->|"API konektor"| ACS
  CLOUD <-->|"s2s JWT/mTLS"| APPLE
```

### 3.2 Diagram kontainer

```mermaid
flowchart TB
  subgraph Phone["iPhone"]
    APP["App SwiftUI"]
    SEP[("Secure Enclave<br/>kunci N-HCE dan B")]
    SE[("Secure Element<br/>applet N-SE / pass W")]
    APP --- SEP
    APP -.-|"CredentialSession / PassKit"| SE
  end
  subgraph Cloud["Anastrophe Cloud"]
    GW["API Gateway"]
    IDS["Identity"]
    ENR["Enrollment"]
    CRED["Credential + Site CA"]
    MEM["Membership"]
    POL["Policy & Config"]
    SYNC["Site Sync & Revocation"]
    FLEET["Reader Fleet"]
    SEP_SVC["SE Personalization (N-SE)"]
    AAP["Apple Access Integration (R2)"]
    NOTIF["Notification (APNs)"]
    AUD["Audit (hash-chained)"]
    DB[("PostgreSQL")]
    HSM[("HSM / KMS")]
    BUS[["Event bus"]]
    GW --> IDS
    GW --> ENR
    GW --> CRED
    GW --> MEM
    GW --> POL
    ENR --> DB
    CRED --> DB
    MEM --> DB
    CRED --> HSM
    ENR --> BUS
    CRED --> BUS
    MEM --> BUS
    BUS --> SYNC
    BUS --> NOTIF
    BUS --> AUD
    BUS --> AAP
    SYNC --> FLEET
    SEP_SVC --> CRED
  end
  subgraph Building["Gedung"]
    RREF["Reader referensi<br/>NFC + BLE + SE"]
    EGW["Edge Gateway<br/>OSDP Transparent Mode"]
    RLEG["Reader OSDP transparan"]
    PANEL["Panel ACS"]
    RREF -->|"OSDP / Wiegand"| PANEL
    RLEG -->|"OSDP transparan"| EGW
    EGW -->|"OSDP / Wiegand"| PANEL
  end
  APP -->|"HTTPS + pinning + App Attest"| GW
  APP <-->|"ANP/1"| RREF
  APP <-->|"ANP/1 NFC"| RLEG
  SYNC <-->|"MQTT mTLS"| RREF
  SYNC <-->|"MQTT mTLS"| EGW
  PORTAL["Portal Admin"] --> GW
```

### 3.3 Komponen

| Komponen | Tanggung jawab | Teknologi referensi |
|---|---|---|
| App iOS | UI, enrolment, provisioning per kanal, presentasi, lifecycle lokal | Swift 6, SwiftUI, Core NFC, SecureElementCredential, PassKit, Core Bluetooth, CryptoKit, LocalAuthentication, DeviceCheck (App Attest), WidgetKit, App Intents, BackgroundTasks |
| Identity | Akun, Sign in with Apple, OTP, sesi, device binding | OIDC; JWT ES256; access token 15 menit; refresh token terikat perangkat |
| Enrollment | Pencocokan kartu (HMAC), undangan, kecocokan pemegang (ADR-0004), security code, batas 8 kartu | — |
| Credential + Site CA | Penerbitan & perpanjangan sertifikat, lifecycle kredensial, kunci di HSM | HSM/KMS cloud |
| Membership | Pemegang utama/anggota, ganti code, hapus anggota | — |
| Policy & Config | Kebijakan gedung, gating wilayah/kanal (`/config`) | — |
| Site Sync & Revocation | Bundel sinkron bertanda tangan, denylist, push ≤ 60 dtk | MQTT over mTLS |
| Reader Fleet | Registrasi reader/gateway, firmware, rotasi kunci reader group | — |
| SE Personalization | Personalisasi applet N-SE lewat mode wired (relai APDU) | Spesifikasi ABR (U) |
| Apple Access Integration (R2) | Endpoint Credential Manager/Provider, lifecycle W, notifikasi Apple | s2s JWT/mTLS, TLS ≥ 1.2 |
| Notification | APNs (alert & silent) | APNs token auth |
| Audit | Log append-only dengan rantai hash | — |
| Portal Admin | Operasi gedung, RBAC, SSO + MFA | Web SPA; design system MASTER |
| Reader referensi | NFC (ISO 14443-4 PCD) + BLE peripheral + SE (kunci reader group) + MCU; output OSDP v2.2/Wiegand | ADR-0016 |
| Edge Gateway | Menjalankan ANP/1 untuk reader OSDP Transparent Mode; cache offline | Linux + TPM; I-12 |

Backend: Go 1.24+ (ADR-0020, provisional), PostgreSQL 16, Redis (rate-limit), HSM/KMS cloud. Region dan residensi data mengikuti regulasi (UU PDP untuk data WNI); topologi R1 di ADR-0014.

## 4. Model kanal

### 4.1 Abstraksi

```swift
enum ChannelKind: String, Codable { case wallet /* W */, nfcSE /* N-SE */, nfcHCE /* N-HCE */, ble /* B */ }

protocol CredentialChannel: Sendable {
    var kind: ChannelKind { get }
    func availability(config: RemoteConfig) async -> ChannelAvailability
    func provision(_ request: ProvisioningRequest) async throws -> ProvisionedCredential
    func present(_ credential: CredentialRef) -> AsyncThrowingStream<PresentmentEvent, Error>   // W: tidak dipakai (Wallet sistem)
    func remove(_ credential: CredentialRef) async throws
}

enum ChannelAvailability { case available, unsupportedDevice, notEligible, regionBlocked, entitlementMissing, bluetoothOff, bluetoothUnauthorized, programNotEnabled }
enum PresentmentEvent { case coolingDown(seconds: Int), waitingForReader, readerFound(name: String?), exchanging, granted, denied(reason: DenyReason), timedOut, cancelled, unavailable(ChannelAvailability), readerOutOfRange }
// coolingDown: assertion HCE ditolak atau jeda 3 dtk per reader B (TC-PRSN-05, FR-83)
// denied(.expired/.suspended) juga dipakai saat kredensial lokal ditolak (ponsel menjawab 6985)
// unavailable: kanal tak bisa dipakai saat presentasi, mis. Bluetooth mati/izin ditolak (FR-82)
// readerOutOfRange: tidak ada reader B di atas ambang RSSI selama pemindaian → "Dekatkan iPhone" (TC-PRSB-05)
```

### 4.2 Pemilihan kanal per kartu (FR-05)

Urutan prioritas **W > N-SE > N-HCE > B**. Sebuah kanal hanya dipakai bila (1) diizinkan kebijakan gedung, (2) server mengizinkan wilayah/entitlement (`/config`), dan (3) `availability` lokal = `.available`. Satu kartu dapat memiliki **lebih dari satu kredensial**. Contoh: N-SE + B di Singapura (B sebagai cadangan bila reader hanya BLE). Setiap kanal punya kredensial terpisah (`cred_id` berbeda) agar pencabutan dan audit per kanal jelas. Batas 8 dihitung per **kartu**, bukan per kredensial.

## 5. Desain aplikasi iOS

### 5.1 Struktur modul (Swift Package lokal)

```
Anastrophe/
├── App/                     # @main, routing, DI container, scene delegate (CredentialSessionWindowSceneDelegate)
├── Packages/
│   ├── ANCore/              # Model domain (istilah GLOSSARY.md), error, Result
│   ├── ANDesignSystem/      # Token warna/tipografi/spasi dari design-system/pages/ios-app.md
│   ├── ANCrypto/            # Secure Enclave key mgmt, ECDH ephemeral, HKDF, AES-GCM
│   ├── ANProtocol/          # Codec ANP/1 (TLV/CBOR), state machine sisi ponsel, framing BLE
│   ├── ANNFCEnroll/         # NFCTagReaderSession → CardFingerprint
│   ├── ANChannelNFC/        # HCEAdapter (CardSession) + SEAdapter (CredentialSession)
│   ├── ANChannelBLE/        # Central Core Bluetooth, pemilihan RSSI, framing
│   ├── ANWallet/            # PassKit: provisioning pass SE, status pass (R2)
│   ├── ANNetworking/        # API client, pinning, App Attest assertion, retry/idempotency
│   ├── ANStorage/           # Keychain (rahasia), SwiftData (metadata; dikecualikan dari backup)
│   └── ANFeatures/          # SwiftUI: Onboarding, Keys, CardDetail, AddCard, Members, Settings, Help, Diagnostics
├── Widgets/                 # Lock Screen widget + Control Center control
└── Intents/                 # App Shortcuts ("Buka kartu Lobi")
```

Arsitektur UI: SwiftUI + `@Observable` view model, aliran data satu arah, dan Swift Concurrency (actor untuk sesi NFC/BLE). Semua I/O NFC, BLE, jaringan, dan Keychain di balik protokol agar dapat di-mock (QA §2).

### 5.2 Entitlements & Info.plist

| Kunci | Nilai | Kanal | Bukti |
|---|---|---|---|
| `com.apple.developer.nfc.readersession.formats` | `TAG` | Enrolment | E07 |
| `com.apple.developer.nfc.readersession.iso7816.select-identifiers` (Info.plist) | AID kartu legacy dari registri gedung pilot | Enrolment | E07 |
| `NFCReaderUsageDescription` | "Anastrophe membaca kartu akses Anda untuk memverifikasi kepemilikan." | Enrolment | E07 |
| `com.apple.developer.nfc.hce` | `YES` | N-HCE | O-A02 |
| `com.apple.developer.nfc.hce.iso7816.select-identifier-prefixes` | `["F0414E415354524F01"]` | N-HCE | O-A02 |
| `com.apple.developer.nfc.hce.default-contactless-app` | tidak diminta di R1 | N-HCE | O-A02 |
| `com.apple.developer.secure-element-credential` | `YES` | N-SE | E03 |
| `com.apple.developer.secure-element-credential.default-contactless-app` | tidak diminta di R1 | N-SE | E03 |
| `NSBluetoothAlwaysUsageDescription` | "Anastrophe memakai Bluetooth untuk membuka pintu yang memakai pembaca Bluetooth." | B | E26 |
| `NSFaceIDUsageDescription` | "Anastrophe memakai Face ID agar hanya Anda yang bisa memakai kartu akses Anda." (ID/EN lewat `InfoPlist.xcstrings`) | N, B | — |
| `UIBackgroundModes` → `bluetooth-central` | **Tidak** di R1 (ADR-0012) | B (P2) | O-B04 |
| `com.apple.developer.devicecheck.appattest-environment` | `production` | Semua | — |
| Entitlement provisioning pass Wallet (Access) | Diberikan Apple saat onboarding program | W (R2) | O-W18, U07 |
| `BGTaskSchedulerPermittedIdentifiers` | `app.anastrophe.cert-renewal` | N, B | — |

Entitlement emulasi (HCE/SE) dipisah di `App/Anastrophe-NFCEmulation.entitlements` dan hanya dipakai bila build setting `AN_NFC_EMULATION = YES` (setelah D1 disetujui). Flag yang sama menjadi kondisi kompilasi app; tanpa itu kanal N tidak diaktifkan dan gating mengembalikan `entitlementMissing` tanpa menyentuh API `CardSession`/`CredentialSession` (TC-ELG-03).

Target minimum: **iOS 26.0** (ADR-0006). Tidak meminta *default contactless app* di R1: menggantikan Wallet sebagai default akan mengganggu Apple Pay pengguna (PRD FR-24).

### 5.3 Penyimpanan lokal

| Data | Lokasi | Proteksi |
|---|---|---|
| Kunci privat kredensial (N-HCE, B) | Secure Enclave (`SecureEnclave.P256.Signing.PrivateKey`). `dataRepresentation` (blob terikat perangkat) disimpan di Keychain. | `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` + `[.privateKeyUsage, .userPresence]` (ADR-0009); tidak ikut backup |
| Kunci kredensial N-SE | Di dalam applet Secure Element | Dikelola applet; otorisasi oleh sistem (O-A20) |
| Sertifikat kredensial, kunci publik reader group (aktif + berikutnya), counter | Keychain | `…ThisDeviceOnly` |
| Token sesi & refresh | Keychain | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| Metadata kartu (nama, gedung, zona, status, kanal) | SwiftData | File protection `.complete`; `isExcludedFromBackup = true` |
| Riwayat tap lokal (30 hari) | SwiftData | Sama |

**Deteksi restore:** saat launch, app memastikan setiap kredensial lokal punya kunci yang dapat dimuat. Bila metadata ada tetapi kunci tidak ada (restore ke perangkat lain atau passcode dimatikan), kartu ditandai "Perlu dipindahkan" (FR-40, FR-44). Hanya kartu berstatus Aktif atau Perlu diperbarui yang ditandai; status pemblokir dari server (Ditangguhkan, Menunggu persetujuan, Dicabut) tetap tampil karena memindahkan kartu tidak menyelesaikannya. Kanal yang diperiksa hanya N-HCE dan B (kunci N-SE ada di applet, W di Wallet).

### 5.4 Gating kelayakan (FR-01, FR-04)

```swift
func resolveAvailability(_ kind: ChannelKind, config: RemoteConfig) async -> ChannelAvailability {
    guard config.enabledChannels.contains(kind) else { return .regionBlocked }          // server: wilayah, entitas, kebijakan (C6)
    switch kind {
    case .nfcHCE:
        guard NFCReaderSession.readingAvailable, CardSession.isSupported else { return .unsupportedDevice }
        guard await CardSession.isEligible else { return .notEligible }                 // wajib sebelum init() (O-A02)
    case .nfcSE:
        guard (try? await CredentialSession.isEligible) == true else { return .notEligible }   // get async throws (O-A24)
    case .ble:
        switch CBManager.authorization {
        case .denied, .restricted: return .bluetoothUnauthorized
        default: break
        }
    case .wallet:
        guard config.walletProgramEnabled else { return .programNotEnabled }            // R2 (U07)
    }
    return .available
}
```

`CardSession()` **tidak boleh** dibuat sebelum lolos gating, karena tanpa entitlement terjadi `fatalError` (O-A02).

### 5.5 Tugas background & push

- **Perpanjangan sertifikat** (FR-45, ADR-0023): hanya setelah pengguna mengautentikasi untuk tap. App memakai ulang `LAContext` yang sama untuk tanda tangan bukti kepemilikan, jadi tidak ada prompt kedua (O-A25).
  - Sisa masa berlaku < 50%: diperpanjang setelah aliran tap selesai, tanpa menahan tap.
  - Sudah kedaluwarsa: diperpanjang lebih dulu (paling lama 5 dtk), lalu tap dilanjutkan; bila gagal, tap gagal tertutup.
  - `BGAppRefreshTask`, pembukaan app, dan silent push `cert_renewal_due` hanya memeriksa masa berlaku dan memperbarui status; ketiganya tidak pernah menandatangani, karena kunci `.userPresence` butuh UI autentikasi (I-15).
- **Status kartu**: silent push (`content-available`) untuk suspend/revoke/approve. App memperbarui status lokal; penegakan tetap di reader.

### 5.6 Deep link & undangan

Undangan memakai Universal Link `https://<domain-produksi>/i/<token>` (domain TBD). Token sekali pakai, TTL 7 hari, di-hash di server. App Clip untuk undangan bersifat P2 (FR-12).

### 5.7 Akses cepat (FR-24)

Widget Lock Screen dan kontrol Control Center membuka app langsung ke lembar presentasi kartu terpilih (App Intent `PresentCardIntent`). Presentasi tetap membutuhkan autentikasi; tidak ada presentasi dari ekstensi (Core NFC tidak tersedia di app extension, E07).

## 6. Presentasi per kanal

### 6.1 N-HCE (`CardSession`)

```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> Authenticating: pengguna memilih kartu
  Authenticating --> Idle: autentikasi gagal atau batal
  Authenticating --> AcquiringIntent: autentikasi sukses
  AcquiringIntent --> SessionStarting: NFCPresentmentIntentAssertion.acquire
  AcquiringIntent --> CooldownWait: ditolak, cooldown 15 dtk
  CooldownWait --> AcquiringIntent
  SessionStarting --> WaitingReader: sessionStarted
  WaitingReader --> Emulating: readerDetected lalu startEmulation
  Emulating --> Emulating: received APDU lalu respond
  Emulating --> Granted: RESULT granted
  Emulating --> Denied: RESULT denied atau SW error
  WaitingReader --> TimedOut: 60 dtk
  Emulating --> TimedOut: maxSessionDurationReached
  Emulating --> WaitingReader: readerDeselected sebelum selesai
  Granted --> Idle: stopEmulation success lalu invalidate
  Denied --> Idle: stopEmulation failure lalu invalidate
  TimedOut --> Idle: invalidate
```

Aturan:
- Autentikasi lewat `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`; `LAContext` yang sama diteruskan ke operasi tanda tangan Secure Enclave (`authenticationContext`).
- Assertion dilepas segera setelah sesi selesai; tidak diambil ulang sebelum cooldown (O-A05).
- Setiap `respond(response:)` harus < 100 ms; bila `transmissionError`, retry sekali (E04).
- `alertMessage` memakai bahasa awam (E05). Status akhir `.success`/`.failure` (O-A22).

### 6.2 N-SE (`CredentialSession`)

**Lifecycle kredensial SE:**

```mermaid
sequenceDiagram
  participant App
  participant CS as CredentialSession
  participant SE as Applet ANP-1 di SE
  participant API as Anastrophe API
  participant PERS as SE Personalization
  App->>CS: isEligible lalu startSession
  CS-->>App: sesi state management
  App->>CS: listCredentials
  alt applet belum terpasang
    App->>CS: provisionCredential configurationUUID dan name
    CS-->>App: Credential terpasang dari bundle ABR
  end
  App->>API: POST /v1/enrollments/id/se-personalization
  API->>PERS: buka sesi personalisasi
  App->>CS: enterWiredMode using credential
  loop sampai selesai, jeda maks 15 dtk antar transceive
    PERS-->>App: command APDU lewat TLS
    App->>CS: transceive APDU
    CS->>SE: APDU
    SE-->>CS: respons
    CS-->>App: respons
    App->>PERS: respons lewat TLS
  end
  Note over SE,PERS: applet membuat kunci kredensial di SE lalu server menerbitkan sertifikat lewat kanal aman personalisasi
  App->>CS: endWiredMode
```

**Presentasi:** `acquirePresentmentAssertion()` → `relinquish()` → `performTransaction(using:over:options:)`. Sistem menampilkan otorisasi (Face ID/Touch ID/passcode) lalu masuk mode card emulation, dan applet menjalankan ANP/1 dengan reader. Setelah selesai: `endCardEmulation()`.

Aturan: maks 2 assertion per 80 dtk (O-A21). Bila app masuk background, sesi diinvalidasi (O-A18), jadi UI kembali ke status siap dan sesi dibuat ulang saat app aktif lagi. Event `CredentialSessionWindowSceneDelegate` (reader terdeteksi, double-press tombol samping) dipakai untuk membuka lembar presentasi (O-A21). Mekanisme kanal aman personalisasi mengikuti integration guide ABR (U04).

### 6.3 B (BLE)

**Peran:** iPhone = *central*, reader = *peripheral*.

| Elemen GATT | UUID | Properti | Isi |
|---|---|---|---|
| Service `ANP` | `8F7AED59-144E-47BD-BEFC-E80CD73BB7C0` | — | Diiklankan reader; *service data* untuk UUID ini memuat `group_id` 8 B (bukan data pengguna) |
| `ANP-Control` | `FA06A2CF-289D-47B7-B3C9-842636994663` | Write with response | Frame ponsel → reader |
| `ANP-Response` | `8E68331B-4026-4FBB-A670-0EE8E56698D8` | Indicate | Frame reader → ponsel |

**Alur Tap (R1, foreground; FR-80):**
1. Pengguna membuka app/widget dan memilih kartu → autentikasi (`LAContext`).
2. Pemindaian dengan filter service UUID dimulai **bersamaan dengan autentikasi** (saat pengguna memilih kartu, foreground) dan berlangsung **maksimal** 5 dtk: berhenti segera setelah reader pertama memenuhi ambang ditambah jeda ±300 ms untuk membandingkan RSSI (*early exit*, ADR-0019). Pemindaian dibatalkan bila autentikasi gagal atau app ke background; connect hanya setelah autentikasi berhasil. Hanya reader dengan **RSSI tertinggi di atas ambang** (dikonfigurasi per reader, mis. −55 dBm) yang dipilih (FR-83).
3. Connect → negosiasi MTU → pertukaran ANP/1 (§7) dibungkus framing BLE (§7.9) → RESULT → disconnect.
4. Maksimal 1 transaksi per 3 dtk per reader. Tap kedua yang terlalu cepat **ditunda** hingga jeda habis (UI menampilkan hitung mundur `coolingDown`), bukan ditolak.
5. Connect + persiapan GATT dibatasi 3 dtk (koneksi dibatalkan bila lewat), lalu pertukaran dibatasi 5 dtk, agar reader yang menjauh atau diam tidak membuat UI menggantung. Putusnya link atau Bluetooth yang dimatikan mengakhiri sesi dengan status batal.

Link BLE dianggap tidak tepercaya; seluruh keamanan berasal dari ANP/1. Mode background/hands-free tidak ada di R1 (ADR-0012).

### 6.4 W (Apple Wallet Access, R2)

**Peran (O-W03):** Anastrophe = **Credential Manager** + **Credential Provider** (Aliro), model *single-party* (ADR-0008); operator gedung = **Participating Provider** (menandatangani perjanjian lewat Anastrophe).

```mermaid
sequenceDiagram
  participant U as Pengguna
  participant App as Anastrophe App
  participant AAP as Apple Access Platform
  participant CM as Anastrophe Credential Manager
  participant CP as Anastrophe Credential Provider Aliro
  participant W as Apple Wallet
  U->>App: Add to Apple Wallet
  App->>CM: minta provisioning info untuk kartu
  CM-->>App: provisioning info
  App->>AAP: mulai In-App Provisioning lewat PassKit
  AAP->>CM: minta pass data
  CM-->>AAP: pass data template vertikal dan TCI gedung
  AAP->>CP: minta credential data
  CP-->>AAP: kredensial Aliro
  AAP->>W: kirim pass dan kredensial ke Secure Element
  AAP->>CM: notifikasi sukses atau gagal
  Note over W: Apple Watch berpasangan mendapat kredensial terpisah
```

| Operasi Anastrophe | Operasi Apple Access Platform (O-W09) |
|---|---|
| Suspend (admin/pengguna via portal) | Suspend oleh Credential Manager — hanya CM yang dapat resume |
| Lost Mode di Find My | Notifikasi suspend dari Apple → status `SUSPENDED (user)` |
| Revoke / hapus kartu | Remove oleh Credential Manager (pass jadi nonaktif) |
| Ganti zona/nama gedung | Pass update |
| iPhone baru | Easy Provisioning oleh pengguna → notifikasi ke CM |

Reader untuk kanal W: reader vendor bersertifikat Aliro + ECP v2.3 + TCI per gedung (O-W07). Zona berisiko tinggi diberi TRA (FR-23). Batas perangkat per pass = 1 iPhone (+ Watch otomatis) (FR-15). Nama endpoint dan kontrak API Apple bersifat indikatif dan difinalkan dari dokumentasi ABR setelah onboarding (U07).

## 7. Protokol ANP/1 (kanal N dan B)

### 7.1 Tujuan keamanan

1. **Otentikasi kredensial** dengan kunci non-ekspor (Secure Enclave/SE). Tidak ada rahasia statis.
2. **Privasi:** ponsel tidak mengungkap identitas apa pun sebelum reader membuktikan ia anggota *reader group* yang dikenal ponsel. Ini mencegah skimming oleh reader asing.
3. **Anti-replay & forward secrecy:** ECDH ephemeral per transaksi.
4. **Satu protokol** untuk NFC (APDU) dan BLE (frame). Setiap APDU < 255 B, sehingga tidak butuh extended length (U08).

Prinsip ini setara Aliro (O-L04, O-L05). ANP/1 tidak memakai AID Aliro (I-10, ADR-0003).

### 7.2 Suite kriptografi

ECDH P-256 (ephemeral, kedua sisi) · ECDSA P-256/SHA-256 · HKDF-SHA256 · AES-128-GCM · sertifikat ringkas CBOR (COSE_Sign1).

### 7.3 Kunci & sertifikat

| Kunci | Pemilik/lokasi | Fungsi | Rotasi |
|---|---|---|---|
| Site CA | HSM backend (per gedung) | Menandatangani sertifikat kredensial & sertifikat kunci reader group | 2 tahun |
| Reader group key | SE di reader referensi / TPM gateway (per gedung, bisa > 1 grup) | Membuktikan reader sah (tanda tangan transcript) | 1 tahun; darurat ≤ 24 jam |
| Credential key | Secure Enclave (N-HCE, B) / applet SE (N-SE) | Menandatangani transcript | Saat transfer/enrolment ulang |
| Session key | Diturunkan per transaksi | Enkripsi AES-GCM | Per transaksi |

`CredentialCert` (CBOR, ±150 B): `cred_id` (16 B acak), `site_id` (8 B), `pubkey` (65 B), `zones` (bitmap), `channel`, `not_before`, `not_after` (default +7 hari, ADR-0010), tanda tangan Site CA (64 B). Encoding: COSE_Sign1 (RFC 9052, ES256, tag 18) dengan payload map CBOR berkunci integer `{1: cred_id, 2: site_id, 3: pubkey, 4: zones, 5: channel (1 = N-HCE, 2 = B, 3 = N-SE), 6: not_before, 7: not_after}` (detik epoch). Ukuran total ±190 B (≤ 200 B), sehingga respons GET_CERT tetap < 255 B. Implementasi lab: `scripts/anp1/lab_ca.py`.

Saat provisioning, ponsel menerima **kunci publik reader group** (aktif + berikutnya) untuk gedung kartu tersebut.

### 7.4 Perintah

| Perintah | CLA INS P1 P2 | Data reader → ponsel | Respons ponsel → reader |
|---|---|---|---|
| SELECT | `00 A4 04 00` | AID `F0414E415354524F01` | FCI `6F{84 AID, A5{80 versi, 81 kapabilitas}}`. **Tanpa** data identitas. |
| AUTH0 | `80 10 00 00` | TLV `C1 group_id(8)`, `C2 r_eph_pub(65)`, `C3 txn_id(16)` (±95 B) | TLV `D1 p_eph_pub(65)` (+ `9000`) |
| AUTH1 | `80 12 00 00` | TLV `C4 sig_R(64)` | AES-GCM(K_pr){`E1 cred_id`, `E2 counter`, `E3 cert_hash(8)`, `E4 sig_P(64)`} + tag (±120 B) |
| GET_CERT | `80 14 00 00` | — (hanya bila cert tidak ada di cache reader) | AES-GCM(K_pr){`CredentialCert`} (±180 B) |
| RESULT | `80 16 00 00` | AES-GCM(K_rp){status, alasan} | `9000` |

**Status word:** `9000` OK · `6982` reader tidak terautentikasi, *termasuk* bila ponsel tidak punya kredensial untuk `group_id` tersebut (respons identik, sehingga tidak membocorkan gedung mana yang dikenal ponsel) · `6985` kredensial lokal ditangguhkan/kedaluwarsa (setelah reader terautentikasi) · `6700` panjang salah · `6A80` data salah · `6D00` INS tidak didukung · `6F00` kesalahan internal.

**Plaintext terenkripsi:**

| Pesan | Kunci & seq | Isi plaintext |
|---|---|---|
| Respons AUTH1 | K_pr, seq 0 | TLV `E1 cred_id(16)` ‖ `E2 counter(4, big-endian)` ‖ `E3 cert_hash(8)` ‖ `E4 sig_P(64)`; `cert_hash` = 8 byte pertama SHA-256(`CredentialCert`) |
| Respons GET_CERT | K_pr, seq 1 | Byte `CredentialCert` apa adanya |
| Data RESULT | K_rp, seq 0 | TLV `F1 status(1: 00 granted, 01 denied)` ‖ `F2 alasan(1)` |

RESULT yang gagal dibuka (tag GCM salah atau TLV rusak) dibalas `6A80`, dan ponsel tidak menganggap transaksi selesai.

**Kode alasan `F2`** (bila `F1` = `01`): `01` kedaluwarsa · `02` ditangguhkan · `03` dicabut · `04` di luar jadwal · `05` zona tidak diizinkan · nilai lain = tidak diketahui. Ponsel memetakannya ke `DenyReason` (§4.1).

### 7.5 Urutan transaksi

```mermaid
sequenceDiagram
  participant R as Reader
  participant P as iPhone Anastrophe
  R->>P: SELECT AID F0414E415354524F01
  P-->>R: FCI versi dan kapabilitas tanpa identitas
  R->>P: AUTH0 group_id, r_eph_pub, txn_id
  P-->>R: p_eph_pub
  R->>P: AUTH1 sig_R atas transcript
  Note over P: verifikasi sig_R dengan kunci publik reader group lalu turunkan kunci sesi
  P-->>R: terenkripsi cred_id, counter, cert_hash, sig_P
  Note over R: dekripsi, cek sertifikat dan sig_P, denylist, zona, jadwal, masa berlaku
  opt sertifikat belum ada di cache reader
    R->>P: GET_CERT
    P-->>R: CredentialCert terenkripsi
  end
  R->>P: RESULT terenkripsi granted atau denied
  P-->>R: 9000
  R->>R: kirim nomor kartu ACS ke panel lewat OSDP atau Wiegand
```

### 7.6 Transcript & derivasi kunci

- `T = "ANP1" ‖ version ‖ group_id ‖ r_eph_pub ‖ p_eph_pub ‖ txn_id`
- `sig_R = ECDSA_sign(reader_group_priv, "ANP1-R" ‖ T)`
- `Z = ECDH(p_eph_priv, r_eph_pub)`; `(K_pr, K_rp, IV_base) = HKDF-SHA256(Z, salt = txn_id, info = "ANP1-KEYS" ‖ group_id, L = 16 + 16 + 12)`
- `sig_P = ECDSA_sign(cred_priv, "ANP1-P" ‖ T ‖ cred_id ‖ counter)`
- Nonce AES-GCM = `IV_base XOR seq`. `seq` adalah bilangan 64-bit big-endian yang di-XOR ke 8 byte terakhir `IV_base`, dihitung per arah mulai 0 (tabel §7.4).
- AAD = header (`CLA INS P1 P2`) APDU perintah yang membawa atau meminta pesan itu. Contoh: respons AUTH1 memakai AAD `80 12 00 00`. Di BLE, header ini disusun dari `type` frame (§7.9).
- Agar timing jalur `6982` tidak membocorkan gedung yang dikenal ponsel (TC-PROTO-05), ponsel selalu menjalankan jumlah verifikasi ECDSA yang sama: setiap kunci group yang dikenal diverifikasi tanpa *short-circuit*, lalu dipadankan dengan verifikasi terhadap kunci decoy (hasilnya selalu dibuang) hingga 2 verifikasi (kunci aktif + berikutnya).
- `counter` monoton per kredensial dipakai untuk **deteksi anomali** di backend/reader. Anti-replay utama berasal dari ECDH ephemeral + `txn_id`.

### 7.7 Ukuran & anggaran waktu

Semua pesan < 255 B: AUTH0 ±95 B, AUTH1 ±120 B, GET_CERT ±180 B.

| Langkah | Anggaran |
|---|---|
| SELECT | ≤ 30 ms |
| AUTH0 (ponsel membuat ephemeral key) | ≤ 60 ms |
| AUTH1 (verifikasi sig_R + ECDH + tanda tangan Secure Enclave/SE + enkripsi) | ≤ 200 ms |
| GET_CERT (jarang) | ≤ 60 ms |
| RESULT | ≤ 30 ms |
| **Total p95** | **≤ 500 ms** (NFR-P01; diukur di HIL, U06) |

### 7.8 Batas waktu anti-relay

Reader mengukur waktu dari AUTH1 dikirim hingga respons diterima. Respons di atas ambang terkalibrasi (default awal 250 ms, dikalibrasi lewat TC-SEC-01) → tolak + catat. Ini **bukan** *distance bounding*. Ini hanya menaikkan biaya relay; perlindungan utama adalah intent eksplisit + autentikasi pengguna (NFR-S07).

### 7.9 Framing BLE

Frame: `type(1) ‖ seq(1) ‖ flags(1: bit0 = last) ‖ len(2) ‖ payload`. `type` memetakan perintah §7.4 (SELECT tidak dipakai di BLE; FCI dikirim sebagai frame `HELLO`). Fragmentasi mengikuti MTU yang dinegosiasikan.

| `type` | Arah | Payload |
|---|---|---|
| `01` HELLO | ponsel → reader, segera setelah berlangganan `ANP-Response` | FCI (§7.4) tanpa status word |
| `10` AUTH0 · `12` AUTH1 · `14` GET_CERT · `16` RESULT | reader → ponsel | *Data field* APDU perintah yang setara (tanpa header) |
| sama dengan perintah | ponsel → reader | Body respons ‖ status word (2 B), sama seperti respons APDU |

Ponsel menyusun ulang header `80 INS 00 00` dari `type` (INS = `type`), sehingga AAD AES-GCM dan batas ukuran sama persis dengan kanal NFC. `seq` dimulai dari 0 per pesan dan harus berurutan. Ukuran frame maksimum = `maximumWriteValueLength(for: .withoutResponse)` (ATT MTU − 3), sehingga tidak bergantung pada *long write* (Prepare/Execute Write) di reader; tulis tetap memakai *write with response*.

### 7.10 Versi

FCI/HELLO memuat daftar versi yang didukung. Reader memilih versi tertinggi yang sama; tanpa kecocokan → `6D00`. Perubahan yang tidak kompatibel menaikkan versi mayor dan AID (`…02`).

### 7.11 Test vector

`ANProtocol` dan firmware reader wajib lulus test vector bersama: kunci uji, transcript, dan ciphertext yang diharapkan (QA TC-PROTO-01). Vector v1 ada di `Packages/Tests/ANCryptoTests/Resources/anp1-v1.json`. Vector ini dibuat oleh `scripts/anp1/gen_vectors.py` dengan pustaka Python `cryptography`, yang independen dari kode Swift; ECDSA RFC 6979 membuatnya dapat direproduksi. Sisi app diuji oleh `TestVectorTests`. Desain kriptografi ditinjau pihak eksternal sebelum pilot (NFR-S09).

## 8. Backend

### 8.1 Model data (PostgreSQL, ringkas)

```sql
organizations(id uuid pk, name text, region text, created_at timestamptz)
sites(id uuid pk, org_id fk, name text, country text, timezone text, policy jsonb, site_ca_key_ref text)  -- key_ref → HSM
zones(id uuid pk, site_id fk, name text, bit smallint, tra_required bool)
reader_groups(id bytea pk /*group_id 8B*/, site_id fk, pubkey bytea, next_pubkey bytea, rotated_at timestamptz)
readers(id uuid pk, site_id fk, group_id fk, kind text /*reference|gateway|vendor_aliro*/, firmware text, last_sync_at timestamptz, rssi_threshold smallint)
users(id uuid pk, apple_sub text unique, contact_hmac bytea, locale text, deleted_at timestamptz)
devices(id uuid pk, user_id fk, app_attest_key_id text, apns_token text, model text, os_version text, status text)
physical_cards(id uuid pk, site_id fk, card_id_hmac bytea, holder_contact_hmac bytea, zones_bitmap bigint, acs_card_number text, status text, unique(site_id, card_id_hmac))
card_ownerships(id uuid pk, physical_card_id fk unique, primary_user_id fk, security_code_hash text, failed_attempts int, locked_until timestamptz, max_members smallint)
memberships(id uuid pk, ownership_id fk, user_id fk, role text check (role in ('PRIMARY','MEMBER')), removed_at timestamptz)
card_instances(id uuid pk, membership_id fk, device_id fk, status text, created_at timestamptz)        -- "Kartu (digital)", maks 8 aktif per device
credentials(id uuid pk, card_instance_id fk, channel text, cred_id bytea unique, pubkey bytea, cert bytea, not_after timestamptz, last_counter bigint, status text, revoked_at timestamptz, revoke_reason text)
wallet_passes(id uuid pk, card_instance_id fk, apple_pass_ref text, device_kind text /*iphone|watch*/, status text)   -- R2
invitations(id uuid pk, site_id fk, physical_card_id fk null, contact_hmac bytea, token_hash bytea, expires_at timestamptz, used_at timestamptz)
claim_disputes(id uuid pk, physical_card_id fk, reporter_user_id fk, status text, decision text, decided_by fk, decided_at timestamptz)
denylist_entries(site_id fk, cred_id bytea, revoked_at timestamptz, expires_at timestamptz, primary key(site_id, cred_id))
admin_users(id uuid pk, org_id fk, idp_subject text, role text, mfa_enrolled bool)
audit_events(id bigserial pk, chain text /* site:<uuid> | platform (ADR-0024) */, site_id fk null, seq bigint, at timestamptz, actor text, action text, subject text, data jsonb, prev_hash bytea, hash bytea, unique(chain, seq)) /* append-only via trigger; CHECK chain kanonik = site_id; hash = SHA-256("ANP1-AUDIT-v1" ‖ prev_hash ‖ seq ‖ field berawalan panjang, data = teks jsonb::text); aktor/subjek hanya pseudonim (ADR-0025) */
```

**Invarian:**
- Maks 8 `card_instances` berstatus aktif (`PENDING_APPROVAL`, `PROVISIONING`, `ACTIVE`, `SUSPENDED`) per `device_id`, ditegakkan dalam transaksi (`SELECT … FOR UPDATE` pada device) (FR-15).
- Satu PRIMARY per kepemilikan.
- `credentials.not_after ≤ issued_at + policy.cert_validity_days`.
- `denylist_entries.expires_at = not_after` sertifikat terakhir, sehingga denylist tidak tumbuh tanpa batas.
- `sites.policy` (JSON) memuat `zones` (nama zona), `zones_bitmap` (bilangan 64-bit) dan `cert_validity_days` (1–30, default 7 sesuai ADR-0010). Tanpa `zones_bitmap`, sertifikat diterbitkan dengan bitmap 0 (*fail-closed*: tidak membuka zona mana pun).

### 8.2 State kredensial

```mermaid
stateDiagram-v2
  [*] --> PENDING_APPROVAL: holder tidak cocok atau kebijakan gedung
  [*] --> PROVISIONING: holder cocok atau undangan atau anggota
  PENDING_APPROVAL --> PROVISIONING: admin menyetujui
  PENDING_APPROVAL --> REJECTED: admin menolak
  PROVISIONING --> ACTIVE: sertifikat diterbitkan
  ACTIVE --> ACTIVE: perpanjangan sertifikat
  ACTIVE --> EXPIRED: kedaluwarsa
  EXPIRED --> ACTIVE: diperpanjang
  ACTIVE --> SUSPENDED: pengguna, admin, atau Lost Mode
  SUSPENDED --> ACTIVE: resume
  ACTIVE --> REVOKED: hapus kartu, transfer, admin, hapus akun
  SUSPENDED --> REVOKED: revoke
  ACTIVE --> UNREACHABLE: perangkat tidak melapor 30 hari
  UNREACHABLE --> REVOKED: TTL
  REVOKED --> [*]
  REJECTED --> [*]
```

Setiap transisi menerbitkan event `credential.<state>`. Event dipakai Site Sync (denylist/push), Notification (APNs), Audit, dan Apple Access Integration untuk kanal W.

### 8.3 Event domain

`enrollment.started|completed|failed`, `ownership.claimed|disputed|reassigned`, `membership.joined|removed`, `security_code.changed|locked`, `credential.provisioned|renewed|suspended|resumed|revoked|expired|unreachable`, `device.transferred`, `account.deleted`, `reader.synced|offline|tampered`, `wallet.pass_provisioned|pass_suspended|pass_removed` (R2).

### 8.4 Alur utama

#### 8.4.1 Enrolment via kartu fisik (FR-11, FR-14, FR-16, FR-18)

```mermaid
sequenceDiagram
  participant U as Pengguna
  participant A as App
  participant API as Anastrophe API
  participant E as Enrollment
  participant C as Credential dan Site CA
  U->>A: Tambah kartu lalu tempel kartu fisik
  A->>A: NFCTagReaderSession baca identitas kartu
  A->>API: POST /v1/enrollments site_id, card_identity, App Attest
  Note over API: identitas hanya lewat TLS, server menghitung HMAC lalu membuang nilai mentah
  API->>E: cocokkan HMAC dengan registri
  alt kartu tidak terdaftar
    E-->>A: 404 CARD_NOT_REGISTERED
  else belum ada pemegang utama dan kontak cocok dengan registri
    E-->>A: role PRIMARY
    U->>A: buat security code
    A->>API: POST /v1/enrollments/id/security-code
  else belum ada pemegang utama dan kontak tidak cocok
    E-->>A: PENDING_APPROVAL
  else sudah ada pemegang utama
    E-->>A: MEMBER_CANDIDATE
    U->>A: masukkan security code pemilik
    A->>API: POST /v1/enrollments/id/verify-code dengan rate limit
  end
  A->>A: buat kunci per kanal di Secure Enclave atau SE
  A->>API: POST /v1/enrollments/id/credentials pubkey per kanal dan App Attest
  API->>C: terbitkan CredentialCert per kanal
  C-->>A: sertifikat dan kunci publik reader group
```

#### 8.4.2 Perpanjangan sertifikat (FR-45)

`{cred}` = `cred_id` dalam hex huruf kecil.

1. App meminta nonce lewat `POST /v1/credentials/{cred}:challenge`. Nonce 32 B, berlaku 120 dtk, sekali pakai, dan terikat ke satu kredensial. Nonce yang sama dipakai untuk perpanjangan dan hapus kartu (ADR-0026). Challenge diizinkan untuk kredensial dan kartu ACTIVE atau SUSPENDED (ADR-0027); respons memuat `card_instance_id`; kredensial atau kartu yang sudah dicabut dijawab 410 `CARD-GONE`.
2. App mengirim `POST /v1/credentials/{cred}:renew` (`Idempotency-Key` wajib) berisi nonce dan tanda tangan kunci kredensial (ECDSA P-256, raw r‖s) atas `"ANP1-RENEW"` ‖ `cred_id` ‖ `nonce` sebagai bukti kepemilikan. App Attest assertion menyusul (belum dikirim di tracer). Prefix memisahkan domain pesan dari transcript ANP/1.
3. Dalam satu transaksi, server memeriksa berurutan: kredensial ada (404 `CRED-NOT-FOUND`); kredensial dan card instance ACTIVE serta kanalnya masih diizinkan kill switch FR-04 (409 `CRED-NOT-RENEWABLE`, termasuk SUSPENDED/REVOKED; kill switch hanya ditegakkan di `:renew`, agar kartu di kanal mati tetap bisa dihapus); nonce valid (400 `CRED-CHALLENGE-INVALID`); tanda tangan valid (400 `CRED-PROOF-INVALID`).
4. Server menerbitkan sertifikat baru untuk kunci, `cred_id`, dan kanal yang sama, dengan zona dan masa berlaku dari kebijakan gedung saat ini. Nonce ditandai terpakai hanya bila perpanjangan (atau hapus kartu) sukses. Respons memakai kontrak provisioning (termasuk `not_before`).

Kapan app memicu alur ini diatur ADR-0023 (§5.5).

**Catatan keamanan tracer.** `:challenge` belum terautentikasi. Siapa pun yang mengetahui `cred_id` (ada di sertifikat yang dibaca reader) dapat membuat baris nonce dan membedakan status kredensial lewat 201/404/409. `DELETE /cards/{id}` juga belum terautentikasi: tanpa bukti apa pun, jawaban 410/409/400 membedakan status kartu dan apakah sebuah kredensial milik kartu itu. Sebelum produksi wajib ada autentikasi sesi dan rate limit di edge. Batas per kredensial tidak dipakai, karena penyerang bisa memakainya untuk memblokir perpanjangan pemilik sah. App Attest belum diimplementasikan karena butuh tim pengembang Apple dan perangkat fisik.

#### 8.4.3 Propagasi pencabutan (G4, NFR-R04)

Event `credential.revoked` → Site Sync menambah denylist + push MQTT ke reader/gateway online (target ≤ 60 dtk). Reader offline mendapatkannya pada sinkron berikutnya (default 15 menit). Reader yang terputus total tetap menolak saat sertifikat kedaluwarsa (≤ 7 hari).

#### 8.4.4 Transfer perangkat (FR-41)

iPhone baru: SIWA + OTP + App Attest → `POST /v1/devices/transfer` → server membuat `card_instances` baru (tanpa security code ulang, karena identitas & peran sama) → provisioning kredensial baru → kredensial di perangkat lama dicabut (REVOKED, alasan `transferred`). Untuk kanal W, pengguna memakai Easy Provisioning dan server menerima notifikasi Apple.

#### 8.4.5 Sengketa klaim (FR-18, FR-59)

Pemegang sah melapor → `claim_disputes` (OPEN) → admin memverifikasi identitas → keputusan `REASSIGN` (PRIMARY dipindah, kredensial pihak lain dicabut, security code wajib dibuat ulang) atau `REJECT`. Semua langkah tercatat di audit.

#### 8.4.6 Hapus akun (FR-06)

`DELETE /v1/me` (autentikasi baru + konfirmasi) → cabut semua kredensial dan pass W → jika pengguna PRIMARY dengan anggota aktif, kepemilikan dialihkan ke status "menunggu pemilik" dan admin dinotifikasi → data pribadi dihapus ≤ 30 hari → audit memenuhi NFR-PR03 tanpa menulis ulang baris: `audit_events` hanya memuat pseudonim sejak ditulis (HMAC per gedung untuk identitas pengguna), dan hapus akun memusnahkan pemetaannya (ADR-0025).

### 8.5 API (REST JSON `/v1`)

Semua POST mutasi menerima header `Idempotency-Key`. Error memakai RFC 9457 (`type` = kode katalog §15). Endpoint sensitif mewajibkan App Attest assertion.

| Metode & path | Fungsi | Req |
|---|---|---|
| `POST /auth/apple` · `POST /auth/otp:send` · `POST /auth/otp:verify` | Login & verifikasi kontak | FR-03 |
| `GET /config` | Wilayah, kanal aktif, kebijakan, versi minimum | FR-01, FR-04, FR-05 |
| `POST /enrollments` | Mulai enrolment (kartu fisik/undangan) | FR-11, FR-12 |
| `POST /enrollments/{id}/security-code` · `/verify-code` | Buat/verifikasi code | FR-14, FR-32 |
| `POST /enrollments/{id}/credentials` | Kirim pubkey per kanal → sertifikat | FR-16 |
| `POST /enrollments/{id}/se-personalization` | Sesi personalisasi applet (N-SE) | FR-16 |
| `GET /cards` · `GET /cards/{id}` | Daftar & detail kartu | FR-30, FR-38 |
| `DELETE /cards/{id}` | Hapus kartu dengan bukti kepemilikan kunci (`Idempotency-Key` wajib): body `credential_id`, `nonce` (dari `:challenge`), `signature` atas `"ANP1-REVOKE"` ‖ `cred_id` ‖ `nonce` ‖ ID kartu huruf kecil. Kartu ACTIVE atau SUSPENDED beserta kredensialnya menjadi REVOKED, audit `credential.revoked`, 204; kartu yang sudah dicabut/tidak dikenal → 410 `CARD-GONE` (ADR-0026/0027) | FR-31 |
| `POST /credentials/{cred}:challenge` · `POST /credentials/{cred}:renew` | Nonce perpanjangan; perpanjang sertifikat (§8.4.2) | FR-45 |
| `GET /ownerships/{id}/members` · `DELETE /ownerships/{id}/members/{uid}` | Kelola anggota | FR-33 |
| `PUT /ownerships/{id}/security-code` | Ganti code | FR-34 |
| `POST /claims` | Laporkan sengketa | FR-18 |
| `POST /devices/transfer` | Pindah perangkat | FR-41 |
| `POST /me/credentials:suspend` · `:resume` | Lost mode via portal/app | FR-42 |
| `DELETE /me` | Hapus akun | FR-06 |
| `POST /wallet/provisioning-info` | Data awal In-App Provisioning (R2) | FR-70 |
| `POST /admin/sites/{id}/credentials/{cid}:approve\|suspend\|resume\|revoke` | Aksi admin | FR-51 |
| `POST /admin/sites/{id}/cards:import` | Impor registri | FR-52 |
| `POST /admin/sites/{id}/invitations` | Undangan | FR-53 |
| `GET /admin/sites/{id}/audit` | Audit | FR-54 |
| `PUT /admin/sites/{id}/policy` | Kebijakan gedung | FR-55 |
| `GET /admin/claims` · `POST /admin/claims/{id}:decide` | Sengketa | FR-59 |
| `GET /admin/sites/{id}/readers` · `POST …/reader-groups/{gid}:rotate` | Armada reader | FR-57 |
| `GET /sites/{id}/sync?since=` (reader/gateway, mTLS) | Bundel delta bertanda tangan | NFR-R04 |
| Endpoint Apple Access Platform (Credential Manager/Provider/notifikasi) | Indikatif; mengikuti kontrak ABR | FR-71, U07 |

## 9. Reader referensi & Edge Gateway

### 9.1 Varian (ADR-0016)

| Varian | Dipakai untuk | Isi |
|---|---|---|
| **Reader referensi** | Pintu pilot (NFC + BLE) | ISO 14443-4 PCD, BLE peripheral, SE untuk kunci reader group, MCU, output OSDP v2.2 (secure channel) atau Wiegand ke panel yang ada |
| **Edge Gateway + reader transparan** | Retrofit gedung dengan reader OSDP Transparent Mode (NFC saja) | Gateway menjalankan ANP/1 (I-12, O-R01); kunci reader group di TPM |
| **Reader vendor Aliro + ECP** | Kanal W (R2) | Bersertifikat Aliro + IOT Apple (O-W07) |

### 9.2 Keputusan akses & integrasi panel

Setelah ANP/1 lolos, reader/gateway memeriksa denylist, masa berlaku sertifikat, zona, dan jadwal. Bila diberikan, reader mengirim **`acs_card_number`** milik kredensial ke panel lewat OSDP/Wiegand. Dengan begitu aturan ACS yang sudah ada tetap berlaku tanpa perubahan panel. Nomor ini dipetakan backend lewat konektor ACS.

### 9.3 Data offline & sinkron

Bundel sinkron ditandatangani Site CA dan berisi: kunci publik Site CA, delta denylist, kebijakan (zona, jadwal, ambang RSSI & timing, TRA), cache sertifikat yang sering dipakai, dan pemetaan `cred_id → acs_card_number`. Kanal: MQTT over mTLS; default interval 15 menit + push saat revoke. Jam disinkronkan via NTP dengan toleransi ±5 menit untuk masa berlaku sertifikat. Kunci privat reader group **tidak pernah** keluar dari SE/TPM.

### 9.4 Operasi

Update firmware bertanda tangan (A/B partition), alarm tamper, heartbeat 60 dtk, rotasi kunci reader group (kunci berikutnya sudah tersebar ke ponsel sebelum aktivasi).

## 10. Keamanan

### 10.1 Threat model (STRIDE)

| Ancaman | Vektor | Kontrol |
|---|---|---|
| Spoofing kredensial | Salin kunci dari ponsel | Kunci non-ekspor di Secure Enclave/SE (NFR-S01) |
| Replay | Rekam & putar ulang APDU | ECDH ephemeral + `txn_id` (§7.6) |
| Relay | Perpanjang jangkauan NFC/BLE | Intent + autentikasi pengguna; batas waktu reader (§7.8); TRA (W) |
| Skimming / pelacakan | Reader asing membaca identitas | Identitas terenkripsi, dibuka hanya setelah `sig_R` valid; respons `6982` seragam (§7.4) |
| Kompromi reader | Kunci reader group dicuri | Kunci di SE/TPM; rotasi darurat ≤ 24 jam. Dampaknya privasi, bukan pemalsuan kredensial |
| Brute-force security code | Anggota palsu | Server-side + rate-limit (ADR-0005) |
| Enrolment hijack | Meminjam kartu fisik korban | Kecocokan pemegang + sengketa (ADR-0004) |
| App termodifikasi/jailbreak | Bypass UI | App Attest; deteksi jailbreak → provisioning ditolak |
| Pengambilalihan akun | Pencurian sesi | SIWA + OTP, refresh token terikat perangkat, re-auth untuk aksi sensitif |
| Penyalahgunaan admin | Admin mencabut/menyetujui sembarangan | RBAC, MFA, audit hash-chained (head per rantai dicatat per jam ke log terpusat; pemotongan ekor tidak terdeteksi tanpa anchoring), peran DB runtime dipisah dari pemilik tabel (rencana), alert aksi massal |
| Kebocoran server | Dump DB | HMAC identitas kartu & kontak, Argon2id, Site CA di HSM |
| Penyalahgunaan intent assertion | Kebijakan Apple | Hanya saat intent aktif (C4, C5) |

### 10.2 Manajemen kunci

| Kunci | Lokasi | Rotasi | Respons kompromi |
|---|---|---|---|
| Site CA | HSM | 2 tahun | Terbitkan CA baru; re-issue sertifikat (≤ 7 hari via perpanjangan) |
| Reader group | SE/TPM reader/gateway | 1 tahun | Aktifkan kunci "next"; pindahkan reader; tarik kunci lama |
| HMAC registri (per gedung) | KMS | Saat diminta | Re-HMAC registri saat impor ulang |
| TLS/mTLS layanan | KMS + otomatisasi | Diperbarui otomatis ≥ 30 hari sebelum kedaluwarsa (O-W16) | Revoke + reissue |
| Kredensial pengguna | Secure Enclave/SE | Saat transfer/enrolment ulang | Revoke + denylist |

### 10.3 Secure SDLC & insiden

SAST, pemindaian dependensi & secret, review kode wajib, pentest eksternal sebelum pilot & GA, review kriptografi ANP/1, bug bounty pasca-GA. Untuk N-SE dan W: kebijakan pengungkapan kerentanan tertulis, dan notifikasi ke Apple "tanpa penundaan" untuk kerentanan yang dieksploitasi (E03). Respons P1 ≤ 15 menit.

## 11. Privasi & kepatuhan

| Data | Tujuan | Lokasi | Retensi |
|---|---|---|---|
| Apple ID subject, kontak (HMAC + nilai terverifikasi terenkripsi) | Akun, pencocokan pemegang | DB | Selama akun aktif; dihapus ≤ 30 hari setelah hapus akun |
| Identitas kartu fisik | Pencocokan registri | Hanya HMAC per gedung | Selama kartu terdaftar |
| Kredensial (pubkey, sertifikat, status) | Akses | DB | Selama aktif + 1 tahun (audit) |
| Log tap | Keamanan gedung | ACS/reader (bukan app) | Kebijakan operator |
| Audit | Akuntabilitas | DB (append-only) | 1 tahun default (≤ 5 tahun bila diwajibkan); dipseudonimkan saat hapus akun |
| Log aplikasi | Operasi | Log terpusat | 30 hari |
| Metrik | Operasi | TSDB | 18 bulan |

Tidak ada GPS, tidak ada tracking lintas app (ATT tidak dipakai). Privacy Manifest dan Nutrition Label wajib akurat. Patuh UU PDP & GDPR; perjanjian pemrosesan data (DPA) dengan setiap operator.

## 12. Infrastruktur & deployment

- **Lingkungan:** Dev, QA, Load, Staging, Production (O-W13).
- **Topologi R1 (ADR-0014, diterima):** region primer + region sekunder *hot standby* dengan failover otomatis sejak R1 (RTO ≤ 30 menit), sehingga R2 tidak butuh re-arsitektur (O-W14).
- **CI/CD:** build & uji otomatis per PR; distribusi TestFlight; infrastruktur sebagai kode; secret di secret manager (tidak di repo).
- **Konfigurasi & feature flag:** `/config` per wilayah/gedung; kill switch per kanal.

## 13. Observabilitas

- **App:** MetricKit + crash reporting tanpa PII; event analitik opt-in (PRD §10).
- **Backend:** OpenTelemetry (trace, metrik, log). SLO: API app p95 ≤ 300 ms; endpoint Apple p90 < 2,2 dtk (O-W15); propagasi revoke ≤ 60 dtk.
- **Reader/gateway:** heartbeat, `last_sync_at`, alarm tamper; alert bila > 2× interval sinkron.
- **Alert:** P1 ≤ 15 menit, on-call terjadwal.

## 14. Kinerja & kapasitas

| Aspek | Target/perkiraan |
|---|---|
| Transaksi NFC (N) | ≤ 500 ms p95 (§7.7) |
| Transaksi BLE (B) | ≤ 1,5 dtk p95 dari intent (NFR-P04) |
| Jalur tap | Tidak menyentuh backend (offline-first) |
| Beban backend R1 | ±10 rb pengguna, ±25 rb kredensial; puncak enrolment ±20 rps; perpanjangan ±1 rps rata-rata |
| Uji beban | 1.000 rps endpoint config/renew (QA TC-PERF-05) |

## 15. Katalog error & mode kegagalan

| Kode | Kondisi | Pesan untuk pengguna (ID) | Aksi |
|---|---|---|---|
| `ENR-NOT-REGISTERED` | Kartu tidak ada di registri | "Kartu ini belum terdaftar di gedung Anda." | Tawarkan undangan |
| `ENR-UNREADABLE` | Kartu tidak terbaca (mis. 125 kHz) | "Kartu tidak dapat dibaca iPhone." | Tawarkan undangan |
| `ENR-SITE-UNSUPPORTED` | Gedung belum memakai Anastrophe | "Gedung ini belum mendukung Anastrophe." | "Usulkan gedung saya" (FR-64) |
| `ENR-PENDING-APPROVAL` | Kontak tidak cocok registri | "Menunggu persetujuan pengelola gedung." | Notifikasi saat disetujui |
| `ENR-LIMIT` | Sudah 8 kartu | "Maksimal 8 kartu per iPhone." | Hapus kartu lain |
| `ENR-NOT-FOUND` | Enrolment/perangkat/gedung tidak dikenal server (404) | "Pendaftaran kartu tidak ditemukan. Mulai lagi." | Ulangi Tambah kartu |
| `ENR-INVALID-KEY` | Kunci publik kanal bukan titik P-256 yang valid (400) | "Kartu tidak dapat disiapkan. Coba lagi." | Buat ulang kunci, ulangi |
| `ENR-INVALID-CHANNEL` | Kanal tidak didukung untuk provisioning (400) | "Cara akses ini belum didukung." | Pilih kanal lain |
| `REQ-IDEMPOTENCY-KEY` | POST mutasi tanpa header `Idempotency-Key` (400) | — (bug klien) | Perbaiki klien |
| `REQ-IDEMPOTENCY-CONFLICT` | `Idempotency-Key` dipakai ulang dengan isi berbeda (422) | — (bug klien) | Pakai key baru per permintaan |
| `REQ-INVALID`, `NOT-FOUND`, `INTERNAL` | Body tidak valid (400), rute tak dikenal (404), kesalahan server (500; detail tidak pernah dikirim ke klien) | "Terjadi kesalahan. Coba lagi." | Coba lagi / laporkan |
| `CODE-INVALID` / `CODE-LOCKED` | Security code salah / terkunci | "Kode salah. Sisa percobaan: n." / "Coba lagi dalam 30 menit." | — |
| `CH-NOT-ELIGIBLE` | Perangkat/wilayah tidak eligible | "Fitur ini belum tersedia di perangkat/wilayah Anda." | Tampilkan kanal alternatif |
| `CH-BT-OFF` / `CH-BT-DENIED` | Bluetooth mati / izin ditolak | "Nyalakan Bluetooth…" / "Izinkan Bluetooth di Pengaturan." | Tautan Pengaturan |
| `PRS-TIMEOUT` | 60 dtk tanpa reader | "Waktu habis. Coba lagi." | Retry |
| `PRS-DENIED-ZONE` | Zona tidak diizinkan | "Kartu ini tidak berlaku di pintu ini." | — |
| `PRS-SUSPENDED` | Kredensial ditangguhkan | "Kartu sedang ditangguhkan." | Hubungi pengelola |
| `CRED-EXPIRED` | Sertifikat kedaluwarsa | "Sambungkan iPhone ke internet, lalu gunakan kartu lagi." | Diperpanjang saat kartu dipakai berikutnya dengan koneksi internet (ADR-0023) |
| `CRED-NOT-FOUND` | `cred_id` tidak dikenal saat perpanjangan | "Kartu tidak ditemukan. Tambahkan ulang kartu." | Enrolment ulang |
| `CRED-NOT-RENEWABLE` | Kredensial atau kartu ditangguhkan/dicabut | "Kartu sedang ditangguhkan. Hubungi pengelola gedung." | Hubungi admin |
| `CRED-CHALLENGE-INVALID` | Nonce tidak dikenal, terpakai, kedaluwarsa, atau milik kredensial lain | — (diulang otomatis pada tap berikutnya) | Minta nonce baru |
| `CRED-PROOF-INVALID` | Tanda tangan bukti kepemilikan tidak valid | "Kartu perlu didaftarkan ulang." | Enrolment ulang |
| `CARD-GONE` (410) | Kartu atau kredensial sudah dicabut/dihapus, atau kartu tidak dikenal | — (app menghapus kartu lokal; ADR-0027) | Tidak ada |
| `CARD-NOT-REMOVABLE` | Kartu belum aktif (mis. masih diprovisikan) saat hapus kartu | "Kartu belum bisa dihapus. Coba lagi nanti." | Coba lagi |
| `DEV-KEY-MISSING` | Restore/passcode dimatikan | "Kartu perlu dipindahkan ke iPhone ini." | Alur transfer |
| `NET-OFFLINE` | Aksi butuh online | "Butuh koneksi internet untuk langkah ini." | Retry otomatis |

## 16. Architecture Decision Records

Detail lengkap, termasuk probabilitas dan cek requirement JEV, ada di [`docs/adr/`](adr/README.md).

| ADR | Keputusan | Status (confidence JEV) |
|---|---|---|
| ADR-0001 | Tidak meng-clone kartu fisik; kredensial baru | Diterima (bukti) |
| ADR-0002 | R1 = kanal N + B; W di R2 | Diterima (0,89) |
| ADR-0003 | Protokol ANP/1 | Diterima (0,93) |
| ADR-0004 | PRIMARY wajib cocok registri; sengketa | Diterima (1,0) |
| ADR-0005 | Security code server-side + rate-limit | Diterima (bukti) |
| ADR-0006 | Minimum iOS 26.0 | Diterima (0,87) |
| ADR-0007 | Kredensial terikat perangkat | Diterima (bukti) |
| ADR-0008 | Ajukan Apple Wallet Access Program di M0 | Diterima (1,0) |
| ADR-0009 | Kunci `.userPresence` | Diterima (0,93) |
| ADR-0010 | Sertifikat 7 hari | Provisional (0,78) |
| ADR-0011 | Pilot ganda ID + SG/MY | Diterima (0,84) |
| ADR-0012 | BLE hands-free ditunda | Diterima (1,0) |
| ADR-0013 | Anggota kanal W via security code | Diterima (0,89) |
| ADR-0014 | Topologi backend R1 | **Eskalasi** (0,48) |
| ADR-0015 | Batas anggota default 4 | Provisional (0,65) |
| ADR-0016 | Reader referensi NFC + BLE | Provisional (0,66) |
| ADR-0017 | Entitas hukum untuk entitlement | **Eskalasi** (escape `investigate`) |
| ADR-0018 | JEV sebagai lapisan keputusan | Diterima (proses) |

## 17. Pemakaian REA (opsional, dengan otorisasi)

Skill REA terpasang di `.claude/skills/reverse-engineer-anything/`. Pemakaian yang sah dan berguna:
1. **Firmware/SDK reader vendor mitra** (dengan izin tertulis): `inspect_firmware_regions` / `open_binary` untuk memverifikasi dukungan AID kustom, OSDP Transparent Mode, dan timing (U03, U06).
2. **Build Anastrophe sendiri** (`.ipa`): `open_binary` + `open_bundle_resources` untuk mengaudit entitlement, Info.plist, Privacy Manifest, dan memastikan tidak ada rahasia ter-embed (TC-SEC-07).
3. **Capture lalu lintas API kita sendiri** (HAR/mitmproxy) dengan `inspect_web_network_capture` untuk regresi privasi, misalnya memastikan identitas kartu mentah tidak pernah tersimpan.
4. **Bukan** untuk membongkar Samsung Wallet guna menyalin kode/aset atau melewati proteksi (DISCLAIMER REA).

## 18. Traceability PRD → SDD

| PRD | SDD |
|---|---|
| FR-01–FR-05 | §4, §5.4, §8.5 |
| FR-06 | §8.4.6 |
| FR-07, NFR-PR01–PR04 | §11 |
| FR-10–FR-19 | §8.1, §8.4.1, §8.4.5 |
| FR-20–FR-22, FR-26–FR-29 | §6.1, §6.2, §7 |
| FR-23, FR-70–FR-73 | §6.4 |
| FR-24 | §5.7 |
| FR-25 | §7, §9.3 |
| FR-30–FR-39 | §8.1, §8.5 |
| FR-40–FR-46 | §5.3, §5.5, §8.4.2–§8.4.4 |
| FR-50–FR-59 | §8.5, §9.4, §10.1 |
| FR-60–FR-64 | §15 (pesan), §5.6 |
| FR-80–FR-83 | §6.3, §7.9 |
| NFR-P01–P05 | §7.7, §13, §14 |
| NFR-R01–R04 | §8.4.3, §9.3, §12 |
| NFR-S01–S10 | §5.3, §7, §10 |
| NFR-O01–O02, NFR-CP01–CP02 | §12, §13, §5.2, §9.1 |
| NFR-A01 | Design system iOS; §5.1 (`ANDesignSystem`) |
| NFR-C01–C04 | §2, §6.4, §8.4.6, §11 |

## 19. Pertanyaan teknis terbuka

| ID | Pertanyaan | Rujukan |
|---|---|---|
| T1 | Mekanisme kanal aman personalisasi applet N-SE dan atestasi kunci applet | ABR (U04) |
| T2 | Kontrak API final Apple Access Platform untuk Credential Manager/Provider | ABR (U07) |
| T3 | Ambang timing anti-relay dan RSSI optimal per model reader | HIL (U06) |
| T4 | Dukungan OSDP Transparent Mode untuk AID kustom pada reader terpasang di gedung pilot | Survei (U03) |
| T5 | Posisi antena NFC pada iPhone Duo | Uji perangkat (U10) |
| T6 | Topologi backend R1 | ADR-0014 |
