# Research Evidence Ledger — Anastrophe (NFC Access Card untuk iOS)

| Item | Nilai |
|---|---|
| Versi dokumen | 2.0 |
| Tanggal riset | 2026-11-01 (v1.0 dan v2.0) |
| Metode | REA (Reverse Engineer Anything) staged investigation workflow — `morluto/rea@6e9ee97`, skill `reverse-engineer-anything` v59 |
| Alat pengumpul data | Firecrawl (`firecrawl_search`, `firecrawl_scrape`; pengecekan live `maxAge: 0` untuk klaim kritis) |
| Target referensi | Samsung Wallet — *NFC Access Card* (https://www.samsung.com/hk_en/support/mobile-devices/nfc-access-card/) |
| Platform target produk | iOS (iPhone), nama produk **Anastrophe** |

### Riwayat versi

| Versi | Tanggal | Perubahan |
|---|---|---|
| 1.0 | 2026-11-01 | Ledger awal: Samsung FAQ, HCE `CardSession`, NFC & SE Platform, Apple Wallet employee badge (E01–E10). |
| 2.0 | 2026-11-01 | Menambahkan E11–E30: `CredentialSession` (SecureElementCredential), Apple Wallet Access Program Guide, Aliro 1.0, OSDP Transparent Mode, HID Mobile Access (BLE), Core Bluetooth background, daftar perangkat iOS 26/27, App Review 5.1.1(v), ketersediaan Apple Pay. Cek ulang live: Indonesia **masih** tidak eligible. Q9–Q14 baru; I-08–I-14; U07–U13. |
| 2.1 | 2026-11-01 | E31 + O-A24 (artefak SDK iOS 27.2); E32 + O-B05–O-B06: batas iklan peripheral CoreBluetooth untuk reader uji BLE (ADR-0022); E33 + O-A25–O-A27 + I-15: autentikasi untuk perpanjangan sertifikat; E34 + O-B07: ATS dan alamat IP (lab di iPhone fisik). |

---

## 1. Cara skill REA diterapkan

Skill REA dibuat untuk menjawab pertanyaan "fitur ini bekerja bagaimana?" dan memandu rekonstruksi fitur. Aturan intinya yang dipakai di sini:

1. **Ubah permintaan menjadi checklist pertanyaan** beserta bukti yang dibutuhkan tiap pertanyaan (§2).
2. **Mulai dari ringkasan/inventaris terkecil yang berguna**, lalu dalami per hipotesis. Urutannya: halaman resmi lebih dulu, lalu dokumentasi vendor, lalu riset komunitas.
3. **Pisahkan Observation / Inference / Unknown** dan rujuk setiap kesimpulan ke Evidence ID (§4–§6).
4. **Ledger temuan** yang menghubungkan kesimpulan, jenis bukti, batas pencarian, dan unknown tersisa (§7).
5. **Saat membangun**, pisahkan *perilaku yang teramati* dari *keputusan desain*. Di PRD/SDD setiap requirement menandai asalnya: `OBS` = meniru perilaku Samsung yang teramati, `DES` = keputusan desain untuk iOS.

### Batas cakupan REA pada riset ini

- **Tidak ada analisis biner.** Tidak ada artefak (APK Samsung Wallet, firmware reader) yang diberikan dan dianalisis. Semua bukti berasal dari halaman web publik yang dikumpulkan via Firecrawl. Server MCP REA tidak terdaftar di sesi ini; tool seperti `inspect_android_package` atau `open_binary` **tidak dijalankan**.
- **Batas hukum/etika (DISCLAIMER REA):** REA tidak boleh dipakai untuk menyalin perangkat lunak proprietary, melewati access control, atau menghindari proteksi teknis. Anastrophe **tidak** menyalin kode/aset Samsung; yang ditiru hanyalah *perilaku produk yang terdokumentasi publik*.
- Riset komunitas (mis. `kormax/*`) dipakai hanya sebagai bukti **berbobot sedang/rendah** tentang perilaku platform. Riset itu tidak dipakai sebagai sumber kode, dan tidak untuk melewati program resmi Apple.
- Analisis REA lanjutan yang sah (opsional): menganalisis **SDK/firmware reader milik vendor mitra** dengan izin tertulis, atau **build Anastrophe sendiri** — lihat SDD §17.

---

## 2. Checklist pertanyaan investigasi

| # | Pertanyaan | Bukti yang dibutuhkan | Status |
|---|---|---|---|
| Q1 | Apa saja fitur & alur NFC Access Card Samsung? | Halaman dukungan resmi Samsung | **Terjawab** (E01) |
| Q2 | Bagaimana kartu fisik "ditambahkan" (clone vs provisioning)? | Resmi + komunitas Samsung | **Sebagian** (E01, E02) — mekanisme internal (eSE applet, format data) tidak teramati |
| Q3 | Apakah iPhone bisa mengemulasikan kartu akses 13,56 MHz dari app pihak ketiga? | Dokumentasi Apple | **Terjawab** (E03–E05, E11, E12) |
| Q4 | Apakah iPhone bisa meng-clone UID / MIFARE Classic kartu fisik? | Apple docs + komunitas | **Terjawab** (E04, E07, E08, E23) — tidak bisa; UID iPhone diacak per tap |
| Q5 | Persyaratan bisnis/legal (entitlement, wilayah)? | Apple developer support | **Terjawab** (E03, E05, E13) |
| Q6 | Alternatif resmi di ekosistem Apple untuk kartu akses? | Apple support, ABR, vendor | **Terjawab** (E06, E09, E21, E22) — Apple Wallet Access Program |
| Q7 | Apakah Indonesia termasuk wilayah yang diizinkan? | Daftar wilayah Apple (cek live) | **Terjawab** (E03, E13) — **tidak**, per cek live 2026-11-01 |
| Q8 | Bagaimana reader gedung harus berperilaku agar mendukung kredensial iPhone? | Spesifikasi Apple/vendor | **Sebagian** (E21: ECP v2.3+, TCI, sertifikasi IOT; E19: Aliro) — model reader gedung target masih **Unknown** (U03) |
| Q9 | Apakah ada standar protokol akses mobile lintas vendor? | CSA, vendor, riset | **Terjawab** (E17–E20) — Aliro 1.0 (26 Feb 2026) |
| Q10 | Bagaimana API resmi kredensial Secure Element (NFC & SE Platform) bekerja? | Dokumentasi Apple | **Terjawab** (E11, E12) |
| Q11 | Bagaimana jalur iPhone untuk akses di wilayah non-eligible (mis. Indonesia)? | Vendor industri, Apple docs | **Sebagian** (E24, E26) — BLE terbukti dipakai industri; ketersediaan Wallet Access di ID **Unknown** (U07) |
| Q12 | Bisakah reader yang sudah terpasang dipakai tanpa ganti hardware? | SIA/OSDP | **Sebagian** (E25) — OSDP Transparent Mode kini terbuka; dukungan per model **Unknown** (U03) |
| Q13 | Versi iOS & perangkat minimum yang realistis? | Apple support, berita | **Terjawab** (E14, E15) |
| Q14 | Kewajiban App Store yang terkait (akun, privasi)? | App Review Guidelines | **Terjawab** (E16) |

---

## 3. Sumber bukti (Evidence)

| ID | Sumber | URL | Diambil | Jenis / bobot |
|---|---|---|---|---|
| E01 | Samsung HK — NFC Access Card FAQ (update 18 Mar 2026) | https://www.samsung.com/hk_en/support/mobile-devices/nfc-access-card/ | 2026-10-31 (cache) | Resmi vendor / tinggi |
| E02 | Samsung Members PH — "How to Clone Your Key Cards to Samsung Wallet on the Galaxy S26 Ultra" (moderator, 24 Jul 2026) | https://r1.community.samsung.com/t5/galaxy-s/how-to-clone-your-key-cards-to-samsung-wallet-on-the-galaxy-s26/td-p/38827979 | 2026-11-01 | Komunitas resmi / sedang |
| E03 | Apple — NFC & SE Platform for secure contactless transactions | https://developer.apple.com/support/nfc-se-platform/ | 2026-10-30 (cache) | Resmi Apple / tinggi |
| E04 | Apple — `CardSession` (Core NFC) | https://developer.apple.com/documentation/corenfc/cardsession | 2026-10-30 (cache) | Resmi Apple / tinggi |
| E05 | Apple — HCE-based contactless NFC transactions (EEA) | https://developer.apple.com/support/hce-transactions-in-apps/ | 2026-11-01 | Resmi Apple / tinggi |
| E06 | Apple Support — Add an employee badge to Apple Wallet (16 Des 2025) | https://support.apple.com/en-us/119901 | 2026-10-31 (cache) | Resmi Apple / tinggi |
| E07 | Apple — Core NFC framework overview | https://developer.apple.com/documentation/corenfc | 2026-11-01 | Resmi Apple / tinggi |
| E08 | Komunitas: Dangerous Things forum (iPhone 14443A emulation) & r/flipperzero (MIFARE 1K + iPhone) | https://forum.dangerousthings.com/t/iphone-13-56-emulation-uid-rewriting/16867 ; https://www.reddit.com/r/flipperzero/comments/132v11f/magic_card_and_iphone_support/ | 2026-11-01 | Komunitas / rendah |
| E09 | HID Global — Employee Badge in Apple Wallet | https://www.hidglobal.com/solutions/employee-badge-apple-wallet | 2026-11-01 (cuplikan) | Vendor / sedang |
| E10 | Komunitas: ketersediaan regional fitur Samsung (Reddit r/GalaxyFold TH; Samsung PH Facebook; Samsung Members) | hasil pencarian Firecrawl `01a19443-78de-…` | 2026-11-01 | Komunitas / rendah |
| E11 | Apple — `CredentialSession` (framework SecureElementCredential) | https://developer.apple.com/documentation/secureelementcredential/credentialsession | 2026-11-01 | Resmi Apple / tinggi |
| E12 | Apple — artikel "Accessing and using secure element credentials" | https://developer.apple.com/documentation/secureelementcredential/accessing-and-using-secure-element-credentials | 2026-11-01 | Resmi Apple / tinggi |
| E13 | Apple — NFC & SE Platform, **cek live** (`maxAge: 0`) daftar wilayah | https://developer.apple.com/support/nfc-se-platform/ | 2026-11-01 (live) | Resmi Apple / tinggi |
| E14 | Apple Support — iPhone models compatible with iOS 27 | https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-27-iphe3fa5df43/ios | 2026-11-01 (cuplikan) | Resmi Apple / tinggi |
| E15 | 9to5Mac — iOS 26 compatible iPhones (XS/XS Max/XR dihapus) | https://9to5mac.com/2025/09/15/ios-26-supports-these-recent-iphones-but-drops-three-models/ | 2026-11-01 (cuplikan) | Media / sedang |
| E16 | Apple — App Review Guideline 5.1.1(v): account deletion | https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion/ | 2026-11-01 (cuplikan) | Resmi Apple / tinggi |
| E17 | CSA — "Introducing Aliro 1.0" (26 Feb 2026) | https://csa-iot.org/newsroom/introducing-aliro-1-0-a-unified-standard-to-transform-the-access-control-ecosystem/ | 2026-11-01 (cuplikan) | Badan standar / tinggi |
| E18 | Cardinal Peak — "Implementing the Aliro Access Control Standard: An Engineering Guide" (22 Jul 2026) | https://www.cardinalpeak.com/blog/aliro-access-control-standard-engineering-guide | 2026-11-01 | Anggota CSA / sedang |
| E19 | Riset publik protokol Aliro (`kormax/aliro`) | https://github.com/kormax/aliro | 2026-11-01 | Riset komunitas / sedang |
| E20 | 9to5Mac — "Backed by Apple, Aliro 1.0 …" (26 Feb 2026) | https://9to5mac.com/2026/02/26/backed-by-apple-aliro-1-0-aims-to-do-for-enterprise-access-control-what-matter-did-for-the-smart-home/ | 2026-11-01 | Media / sedang |
| E21 | Apple — **Apple Wallet Access Program Guide** (ABR docs): Access Passes, Participant Roles, Integration Models, Provisioning, Access NFC Transactions, Life Cycle Management, Sharing, Requirements, Next Steps | https://register-docs.apple.com/apple-pay/access/program-guide/ | 2026-11-01 | Resmi Apple / tinggi |
| E22 | Apple — "Keys in Apple Wallet" | https://learn.wallet.apple/keys | 2026-11-01 | Resmi Apple / tinggi |
| E23 | Riset komunitas `kormax/apple-device-as-access-card` (perilaku UID iPhone) | https://github.com/kormax/apple-device-as-access-card | 2026-11-01 | Riset komunitas / sedang |
| E24 | HID — Mobile Access FAQ (PLT-02085 Rev C.8, Apr 2026) & listing App Store HID Mobile Access | https://doc.origo.hidglobal.com/faq/portal/HID_Mobile_Access_FAQ.pdf ; https://apps.apple.com/us/app/hid-mobile-access/id843238107 | 2026-11-01 (cuplikan) | Vendor / sedang |
| E25 | SIA — "Confirms Openness of Transparent Mode for OSDP Standard" (18 Mar 2026) | https://www.securityindustry.org/2026/03/18/security-industry-association-confirms-openness-of-transparent-mode-for-osdp-standard/ | 2026-11-01 | Asosiasi industri / tinggi |
| E26 | Apple — Core Bluetooth Background Processing for iOS Apps; Punch Through — iOS BLE scanning guide | https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html ; https://punchthrough.com/ios-ble-scanning-guide/ | 2026-11-01 (cuplikan) | Resmi Apple + vendor / tinggi–sedang |
| E27 | Apple Support — Countries and regions that support Apple Pay (27 Okt 2026); Apple Community thread status Indonesia | https://support.apple.com/en-us/102775 ; https://discussions.apple.com/thread/256348753 | 2026-11-01 (cuplikan) | Resmi Apple / tinggi |
| E28 | Apple — `CardSession.EmulationUIStatus` | https://developer.apple.com/documentation/corenfc/cardsession/emulationuistatus | 2026-11-01 | Resmi Apple / tinggi |
| E29 | Apple — PassKit `PKSecureElementPass`, `PKAddSecureElementPassViewController` | https://developer.apple.com/documentation/passkit/pksecureelementpass | 2026-11-01 (cuplikan) | Resmi Apple / tinggi |
| E30 | Android Developers — Host-based card emulation overview (UID acak pada HCE) | https://developer.android.com/develop/connectivity/nfc/hce | 2026-11-01 (cuplikan) | Resmi Google / sedang (lintas platform) |
| E31 | Apple — iOS SDK 27.2 (Xcode 27.2, build 27B52): `CoreNFC.swiftinterface` dan `SecureElementCredential.swiftinterface` | `iPhoneOS27.2.sdk/System/Library/Frameworks/{CoreNFC,SecureElementCredential}.framework` | 2026-11-01 | Resmi Apple (artefak SDK) / tinggi |
| E32 | Apple — Core Bluetooth: `CBPeripheralManager` (ketersediaan platform) dan `startAdvertising(_:)` | https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager | 2026-11-01 (metadata JSON dokumentasi) | Resmi Apple / tinggi |
| E33 | Apple — Security, LocalAuthentication, BackgroundTasks: `kSecUseAuthenticationContext`, `LAContext.interactionNotAllowed`, `LAError.Code.notInteractive`, `BGAppRefreshTask` | https://developer.apple.com/documentation/security/ksecuseauthenticationcontext | 2026-11-01 (metadata JSON dokumentasi) | Resmi Apple / tinggi |
| E34 | Apple — Information Property List: `NSAllowsLocalNetworking` (App Transport Security) | https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking | 2026-11-01 (metadata JSON dokumentasi) | Resmi Apple / tinggi |

---

## 4. Observations (fakta teramati langsung di sumber)

### 4.1 Samsung NFC Access Card (E01 kecuali disebut lain)

| ID | Observation |
|---|---|
| O-S01 | Fungsi *digital key* di Samsung Wallet yang menggantikan kartu fisik NFC untuk akses residensial, gedung komersial, kampus, lift, dan parkir. |
| O-S02 | Perangkat: Galaxy Z Flip3–6, Z Fold3–6, S21–S25 (termasuk FE/Edge/Ultra), A36; wajib Android 15 ke atas. |
| O-S03 | Mendukung "seri kartu RFID NFC tertentu"; **kartu terenkripsi tidak didukung**. Wallet menyaring kartu yang didukung saat proses penambahan. |
| O-S04 | Maksimum **8** NFC Access Card per perangkat. |
| O-S05 | Alur tambah: buka Wallet → Digital Keys → "Add NFC access card" → tempelkan kartu fisik ke belakang ponsel → **buat security code** → kartu tersimpan. |
| O-S06 | Bisa berdampingan dengan Smart Octopus (kartu transit). |
| O-S07 | Pemakaian: swipe-up dari Quick Access, atau halaman kartu terbuka otomatis saat ponsel ditempel ke reader. |
| O-S08 | NFC harus aktif dan diset ke "Embedded Security Element". |
| O-S09 | Bisa dipakai **tanpa data seluler/Wi-Fi** (offline). |
| O-S10 | **Tidak bisa** dipakai saat layar mati / ponsel terkunci / baterai habis (hanya Smart Octopus yang bisa). |
| O-S11 | Hapus kartu: buka detail kartu → Settings → Delete. |
| O-S12 | Anggota lain boleh menambahkan kartu fisik yang sama; mereka **diminta memasukkan security code** yang dibuat pemilik pertama. |
| O-S13 | Pemilik utama (*primary phone owner*) dapat menghapus anggota dan mengganti security code. |
| O-S14 | Kartu **tidak bisa dibagikan** ke pihak lain (tidak ada fitur share). |
| O-S15 | Kartu **terikat perangkat**; tidak ikut ke ponsel baru via login akun; pindah perangkat via Smart Switch. |
| O-S16 | Ponsel hilang: kunci jarak jauh via SmartThings Find; menghapus data ponsel menghapus semua Digital Keys. |
| O-S17 | (E02) Ponsel "membaca data frekuensi yang tidak terenkripsi", memverifikasi konfigurasi, menyimpannya; diisolasi di Samsung Knox; dipetakan ke registrasi akun; diklaim bisa dipakai **tanpa membuka aplikasi atau menyalakan layar**. |
| O-S18 | (E10) Fitur dirilis bertahap per negara (HK, MY, VN, TH, PH disebut di komunitas). |

### 4.2 iOS — emulasi dalam aplikasi (HCE & Secure Element)

| ID | Observation |
|---|---|
| O-A01 | (E04) `CardSession` = sesi emulasi kartu **ISO 7816-4** (APDU), iOS 17.4+. Mendukung HCE untuk pembayaran, car key, closed-loop transit, **corporate badge**, hotel key, loyalty, dan event ticket — hanya di **EEA**. |
| O-A02 | (E04) Wajib entitlement `com.apple.developer.nfc.hce` dan `com.apple.developer.nfc.hce.iso7816.select-identifier-prefixes` (daftar AID/RID yang didengarkan saat `SELECT`). Opsional `…default-contactless-app`. Tanpa entitlement, `init()` memicu `fatalError`. |
| O-A03 | (E04) Emulasi berlaku maksimum **60 detik** sejak `startEmulation()`; lalu `maxSessionDurationReached`. |
| O-A04 | (E04) `startEmulation()` menampilkan **UI modal sistem** di atas aplikasi. Setiap APDU harus direspons tepat waktu, atau reader timeout. |
| O-A05 | (E03, E05) Presentment Intent Assertion: hanya saat app foreground, kedaluwarsa setelah 15 detik / app ke background / objek dilepas; setelahnya harus menunggu 15 detik. |
| O-A06 | (E03) NFC & SE Platform (iOS 18.1+): applet di **Secure Element**, otorisasi transaksi oleh **Secure Enclave** (Face ID/Touch ID/passcode). Applet harus direview lab independen, lalu ditandatangani dan di-host Apple. Butuh perjanjian komersial + NDA dengan Apple + onboarding Apple Business Register. |
| O-A07 | (E03) Use case yang diizinkan antara lain **Corporate Badge access**, **Home Keys**, **Student ID**, **Hotel Keys**. Pemohon harus operator gedung/pemilik sistem, **atau punya perjanjian mengikat** dengan operator tersebut. |
| O-A08 | (E03, E13) Wilayah eligible antara lain AU, BR, CA, JP, NZ, UK, US (iOS 18.1+), CH (18.2+), **HK, MY, SG, TW** dan lainnya (iOS 18.4+), **VN**, IN, dan lainnya (iOS 26.0+). **Indonesia, Thailand, dan Filipina tidak tercantum** (cek live 2026-11-01). |
| O-A09 | (E03, E05) Aplikasi harus mendukung perintah **ISO 14443-4 dan ISO 7816-4**. |
| O-A10 | (E03, E05) Pedoman desain: jangan memakai logo/visual yang mirip Apple Pay/Apple Wallet; cek `isEligible` dan sembunyikan fitur bila tidak eligible. |
| O-A11 | (E03, E05) App Review mensyaratkan TestFlight, kredensial uji, video transaksi di terminal, dan video Presentment Intent Assertion. |
| O-A12 | (E05) Contoh AID di dokumentasi Apple: HID `A0000004400001010001`, MIFARE `A0000003964D344D24040181F8020001`. |
| O-A13 | (E05) Pengujian HCE di luar EEA dimungkinkan untuk pengembangan (iOS 18.2+, hingga 100 perangkat uji). |
| O-A14 | (E07) Core NFC `NFCTagReaderSession` dapat **membaca** tag ISO 7816, ISO 15693, FeliCa, MIFARE. |
| O-A15 | (E06) Employee badge di Apple Wallet membutuhkan **employer yang berpartisipasi** + aplikasi employer; Express Mode aktif otomatis (dipakai tanpa membuka app). |
| O-A16 | (E03) Simulator tidak mendukung; butuh iPhone dan hardware reader NFC untuk uji. |
| O-A17 | (E11) `CredentialSession` adalah `actor` (iOS 18.1+) dengan tiga state: **management** (list/provision/delete kredensial), **wired** (pertukaran APDU dengan applet), dan **card emulation**. Hanya satu sesi aktif per app. |
| O-A18 | (E11) Sistem **menginvalidasi sesi otomatis** tak lama setelah app masuk background. Pada mode wired, sesi diinvalidasi bila 15 detik tanpa `transceive(_:)`. |
| O-A19 | (E11, E12) `provisionCredential(configurationUUID:name:)` memasang **applet bundle yang disubmit via ABR** ke Secure Element. Pemeliharaan kredensial (pertukaran kunci & sertifikat) dilakukan di mode wired via `transceive(_:)`. |
| O-A20 | (E11, E12) `performTransaction(using:over:options:)` **meminta otorisasi pengguna** (Face ID/Touch ID/passcode) lalu mengaktifkan kredensial untuk card emulation. `startSession()` pertama kali memunculkan alert izin penggunaan Secure Element. |
| O-A21 | (E12) Metode yang melakukan transaksi mengambil presentment assertion internal secara otomatis. Batasnya **dua assertion dalam rentang 80 detik**. Event lewat `CredentialSessionWindowSceneDelegate` mencakup kedekatan dengan reader NFC dan gestur double-press tombol samping/Home. |
| O-A22 | (E28) `CardSession.EmulationUIStatus` hanya punya `.success` dan `.failure`. |
| O-A23 | (E23, E30) Perangkat Apple **mengacak UID pada setiap tap** (kecuali kasus khusus kartu transit China T-Union di Wallet). Dokumentasi Android juga menyatakan perangkat HCE "harus diasumsikan memiliki UID acak". |
| O-A24 | (E31) `CredentialSession.isEligible` dideklarasikan `static var isEligible: Bool { get async throws }`, sedangkan `CardSession.isEligible` adalah `{ get async }`. `CardSession` dan `CardSession.EventStream` tidak `Sendable`; `CardSession.APDU` dan `NFCPresentmentIntentAssertion` `Sendable`. `NFCPresentmentIntentAssertion` tidak punya metode pelepasan, jadi assertion dilepas saat objeknya dilepas (`deinit`). |
| O-A25 | (E33) `kSecUseAuthenticationContext`: bila diberi `LAContext` yang sudah diautentikasi, operasi keychain berhasil **tanpa meminta autentikasi lagi**. Tanpa kunci ini, konteks baru dibuat, dipakai sekali, lalu dibuang. |
| O-A26 | (E33) `LAError.Code.notInteractive`: menampilkan UI autentikasi yang dibutuhkan dilarang. Ini terjadi bila `LAContext.interactionNotAllowed` bernilai `true`. |
| O-A27 | (E33) `BGAppRefreshTask` adalah tugas singkat untuk memperbarui konten yang dijalankan **saat app di background**; butuh `UIBackgroundModes` `fetch`. |

### 4.3 Apple Wallet Access Program (E21 kecuali disebut lain)

| ID | Observation |
|---|---|
| O-W01 | Access pass = **pass data** (tampilan, metadata, pengaturan; template dari Apple per vertikal) + **access credential** yang disimpan di **Secure Element**. |
| O-W02 | Teknologi kredensial yang didukung: **MIFARE DESFire** (EV0/D40, EV1, EV2), **HID Seos**, **Aliro** (CSA, PKI). |
| O-W03 | Peran: **Credential Manager** (integrasi utama, provisioning & lifecycle), **Credential Provider** (menyerahkan kredensial; harus mendukung ≥1 teknologi di O-W02), **Participating Provider** (pemilik/pengelola properti; menandatangani Participating Provider Agreement lewat Credential Manager bila berbeda organisasi). |
| O-W04 | Model integrasi: **single-party** (Credential Manager = Credential Provider) atau **multi-party**. Credential Manager dapat meluncurkan banyak deployment dengan berbagai Participating Entities. |
| O-W05 | Provisioning: **In-App** (app iOS atau App Clip, tombol *Add to Apple Wallet*), **Web**, dan **Easy Provisioning** (re-provisioning dari Wallet, mis. perangkat baru). Bila ada Apple Watch berpasangan, pass tambahan dengan **kredensial berbeda** otomatis diprovision ke Watch. Credential Manager dapat **membatasi jumlah perangkat** per pass. |
| O-W06 | Fitur transaksi: **Auto-Presentment**, **Express Mode** (aktif default saat provisioning; tanpa Face ID/Touch ID/passcode), **Express dengan power reserve** (tetap dapat dipakai saat baterai rendah pada model yang didukung), dan **Terminal Requested Authentication (TRA)** untuk area berisiko tinggi. |
| O-W07 | Reader wajib: firmware dapat diperbarui, mendukung teknologi kredensial terpilih, **ECP v2.3+**, dan memuat nilai **TCI** dari Apple. Apple melakukan **sertifikasi IOT** reader. |
| O-W08 | Keputusan akses dilakukan reader/panel (offline atau online); di luar cakupan Apple. |
| O-W09 | Lifecycle: **pass update** (oleh Credential Manager), **suspend/resume** (oleh Credential Manager via API; oleh pengguna via Find My **Lost Mode**), **remove** (pengguna atau Credential Manager; yang dihapus Credential Manager tetap tampil sebagai pass nonaktif), **Easy Provisioning & migrasi perangkat**. Platform mengirim notifikasi ke server Credential Manager. Pass suspend oleh Credential Manager hanya dapat di-resume oleh Credential Manager. |
| O-W10 | Pengguna menghapus pass juga dengan: sign out iCloud, reset perangkat (termasuk via Find My), **mematikan passcode**, atau unpair Apple Watch. |
| O-W11 | **Sharing opsional**: berbagi via iMessage/SMS/email/WhatsApp, dengan izin yang ditentukan Credential Manager dan **kode aktivasi 6 digit** opsional (sebaiknya dikirim lewat kanal terpisah). Mendukung lintas platform via IETF Secure Credential Transfer. iOS 16.1+. |
| O-W12 | Ruang lingkup wajib: provisioning (In-App atau Web), transaksi NFC, lifecycle. **Semua reader terkait wajib menerima mobile pass di samping kartu fisik.** |
| O-W13 | Server-to-server: autentikasi **JWT atau mTLS**, HTTPS, TLS 1.2+. Lingkungan wajib: **QA, Load Testing, Production**. |
| O-W14 | DR: multi-region, HA, active-active (disarankan) atau active-passive hot standby, failover otomatis, downtime ≤ **30 menit**, diuji bersama Apple. |
| O-W15 | SLA: **p90 latency < 2,2 detik** semua lingkungan; uptime **99,99% production**, 98% non-production, 95% QA. |
| O-W16 | Log aplikasi disimpan ≥ **25 hari**. Metrik/KPI disimpan **13 bulan (18 bulan disarankan)**. Pembaruan sertifikat otomatis ≥ **30 hari** sebelum kedaluwarsa. Respons engineering **P1 ≤ 15 menit**. |
| O-W17 | Peran tim wajib: sponsoring exec, signing authority, technical contact, prod technical contact, on-call. |
| O-W18 | Onboarding: minta kuesioner partisipan (access-partnerships@group.apple.com), lalu Apple dapat mengundang ke **Apple Business Register**. Tanggung jawab Credential Manager: template pass, firmware reader, integrasi server, app iOS, deployment reader. Apple: sertifikasi IOT reader. Bersama: pengujian end-to-end, termasuk uji di properti. |
| O-W19 | (E22) Jenis kunci di Apple Wallet: hotel, corporate, universitas, mobil, multi-family, single-family. Mendukung remote provisioning, Express Mode, power reserve. Partisipasi melalui proses **diligence bisnis & teknis**. |
| O-W20 | (E29) PassKit menyediakan `PKSecureElementPass` (dengan `passActivationState`) serta `PKAddSecureElementPassViewController`/`PKAddSecureElementPassConfiguration` untuk menambah pass Secure Element dari app. |

### 4.4 Aliro (CSA)

| ID | Observation |
|---|---|
| O-L01 | (E17, E20) Aliro 1.0 dirilis **26 Feb 2026** oleh CSA. Transport: **NFC** (tap), **BLE** (jarak jauh, inisiasi pengguna), **BLE + UWB** (hands-free). Program sertifikasi dibuka; produk bersertifikat pertama diharapkan akhir 2026. |
| O-L02 | (E20) Didukung Apple, Google, Samsung, ASSA ABLOY, Allegion, HID, Kastle, NXP, STMicroelectronics, dan lainnya. **Pada iOS, kredensial Aliro tinggal di Apple Wallet.** |
| O-L03 | (E18) Tier: **Tier 1 NFC (wajib** untuk semua hardware bersertifikat, ISO 7816 APDU), Tier 2 BLE (opsional), Tier 3 BLE+UWB (opsional). Target transaksi **< 500 ms** (fast path). |
| O-L04 | (E18, E19) Mutual authentication berbasis **PKI** (ECDSA, sertifikat), ephemeral key exchange, **tanpa shared secret**. Ada jalur *Expedited-Standard* dan *Expedited-Fast* (konteks tersimpan). Kunci privat wajib berada di Secure Element/HSM. |
| O-L05 | (E19) AID primary applet `A000000909ACCE5501`, step-up `A000000909ACCE5502`. Perintah: SELECT, AUTH0, LOAD CERTIFICATE, AUTH1, EXCHANGE, CONTROL FLOW, ENVELOPE, GET RESPONSE. Secure channel AES-GCM per arah. **Perangkat tidak mengungkap data identitas sebelum reader terautentikasi.** |
| O-L06 | (E19) Versi protokol teramati: 0.9 (Apple Wallet, Google Wallet) dan 1.0 (**Apple Wallet sejak iOS 26.4**, Samsung Wallet). Express Mode di Apple membutuhkan reader mengirim **TCI** yang cocok lewat ECP. |

### 4.5 BLE & reader/infrastruktur

| ID | Observation |
|---|---|
| O-B01 | (E24) HID Mobile Access di **iOS memakai BLE untuk "Tap"** dan "Twist & Go". Aplikasi dapat dipakai saat foreground, background, dan saat perangkat terkunci (izin "Always"). **Location Services** dipakai hanya untuk mendeteksi reader saat app tidak terbuka. |
| O-B02 | (E24) Saat iPhone didekatkan ke reader yang memancarkan NFC, lembar Apple Pay dapat muncul meski transaksi berjalan lewat BLE, dan tidak ada data kartu yang dipertukarkan. |
| O-B03 | (E24) Mobile ID unik per perangkat dan tidak dapat disalin; ganti perangkat berarti Mobile ID baru diterbitkan. App hanya mengumpulkan push ID, model, dan versi OS; tanpa GPS. |
| O-B04 | (E26) Pemindaian BLE di background **wajib memfilter service UUID** (yang juga dideklarasikan di mode `bluetooth-central`), berjalan lebih jarang, dan tidak otomatis lanjut setelah Bluetooth reset. State preservation & restoration memungkinkan app diluncurkan ulang di background. |
| O-B05 | (E32) `CBPeripheralManager` tersedia di macOS 10.9+ (juga iOS/iPadOS 6.0+, Mac Catalyst 13.1+, tvOS 9.0+, watchOS 2.0+, visionOS 1.0+). |
| O-B06 | (E32) `startAdvertising(_:)` hanya mendukung dua kunci data iklan: `CBAdvertisementDataLocalNameKey` dan `CBAdvertisementDataServiceUUIDsKey`. Iklan bersifat *best effort*; saat foreground tersedia hingga 28 B di iklan awal, ditambah 10 B di *scan response* khusus nama lokal. Akibatnya peripheral berbasis CoreBluetooth (iOS/macOS) **tidak dapat** mengiklankan *service data* seperti `group_id` (SDD §6.3). |
| O-B07 | (E34) Di iOS 10–16, ATS mengizinkan koneksi ke domain tanpa kualifikasi, domain `.local`, dan alamat IP secara default. **Mulai iOS 17, iPadOS 17, dan macOS 14, ATS tidak lagi mengizinkan koneksi ke alamat IP secara default**; alamat IP/CIDR harus ditambahkan di `NSExceptionDomains`. |
| O-R01 | (E25) SIA menyatakan (18 Mar 2026) **OSDP Transparent Mode terbuka untuk semua**. Paten HID terkait tidak akan membatasi implementasi yang patuh OSDP. Mode ini memungkinkan data aplikasi spesifik melewati kanal aman OSDP. OSDP v2.2.2 rilis Okt 2024; standar IEC 60839-11-5. |

### 4.6 Perangkat, OS, dan kebijakan

| ID | Observation |
|---|---|
| O-D01 | (E14) iOS 27 mendukung **iPhone 11 ke atas** dan **iPhone SE (gen 2 & 3)**, termasuk iPhone 16e, 17, 17 Pro/Pro Max, Air, 17e, 18 Pro/Pro Max, dan **iPhone Duo**. |
| O-D02 | (E15) iOS 26 menghapus dukungan **iPhone XS, XS Max, XR**. |
| O-P01 | (E16) App yang mendukung pembuatan akun **wajib** menyediakan inisiasi **penghapusan akun di dalam app** (termasuk akun yang dibuat otomatis atau via web). |
| O-P02 | (E27) Daftar negara Apple Pay (27 Okt 2026) **tidak memuat Indonesia**; Filipina diluncurkan Agustus 2026. |

---

## 5. Inferences (kesimpulan turunan — dengan dasar)

| ID | Inference | Dasar | Keyakinan |
|---|---|---|---|
| I-01 | Samsung meng-*clone* identitas kartu (UID dan/atau data sektor tidak terenkripsi, kemungkinan MIFARE Classic/Ultralight UID-based) lalu mengemulasikannya dari **eSE**, bukan HCE. Dasarnya: fitur butuh setting "Embedded Security Element" dan menolak kartu terenkripsi. | O-S03, O-S08, O-S17 | Sedang |
| I-02 | **iPhone tidak dapat mereplikasi alur "tempel kartu fisik → langsung jadi kartu di ponsel".** API publik hanya mengemulasikan ISO 7816-4 lewat AID terdaftar. UID iPhone diacak per tap, dan tidak ada API untuk mengatur UID atau mengemulasikan MIFARE Classic Crypto1. | O-A01, O-A02, O-A09, O-A23, E08 | Tinggi |
| I-03 | Agar iPhone berfungsi, **reader/ACS harus mendukung kredensial ISO-DEP berbasis AID**: protokol Anastrophe, Aliro, Seos, atau DESFire. Produk ini membutuhkan **kemitraan dengan operator gedung/vendor ACS**; aplikasi konsumen saja tidak cukup. | I-02, O-A07, O-W07, O-W12 | Tinggi |
| I-04 | Kartu fisik tetap berguna sebagai **bukti kepemilikan saat enrolment** (dibaca via `NFCTagReaderSession`). Setelah itu server menerbitkan kredensial digital baru yang memetakan hak akses yang sama. | O-A14, I-03 | Sedang |
| I-05 | Pemakaian "tanpa membuka app / saat layar mati" (O-S17) **tidak bisa** dicapai lewat kanal in-app (HCE/SE). Kanal in-app paling banter memakai *default contactless app* (Field-detect/Double-click) dengan autentikasi. Express Mode dan power reserve **hanya** tersedia untuk access pass di **Apple Wallet**. | O-A06, O-A15, O-W06 | Tinggi |
| I-06 | Di **Indonesia** saat ini kanal NFC in-app (HCE/SE) tidak dapat dipakai. Opsi yang tersisa: (a) Apple Wallet Access Program, bila Apple mengizinkan di ID (U07); (b) **BLE**; (c) luncurkan dulu di wilayah eligible (SG/MY/HK). | O-A08, O-P02, O-B01 | Tinggi |
| I-07 | Kontradiksi O-S10 (HK: tidak bisa saat layar mati/terkunci) vs O-S17 (PH S26: tanpa membuka app) kemungkinan karena perbedaan versi/perangkat/region. Tidak memengaruhi desain iOS (lihat I-05). | O-S10, O-S17 | Rendah |
| I-08 | **Apple Wallet Access Program adalah satu-satunya jalur resmi Apple yang mencapai paritas UX dengan Samsung**: tanpa membuka app (Express), auto-presentment, power reserve, Apple Watch, migrasi perangkat, dan suspend via Find My. | O-W05, O-W06, O-W09 | Tinggi |
| I-09 | Karena Aliro didukung Apple/Google/Samsung dan wajib NFC Tier 1, **reader yang dibeli gedung mulai sekarang sebaiknya Aliro-ready + ECP**. Dengan begitu satu investasi reader melayani iPhone (Wallet), Android, dan kanal Anastrophe. | O-L01–O-L03, O-W02, O-W07 | Sedang |
| I-10 | Kanal in-app Anastrophe **tidak boleh** memakai AID Aliro: AID itu dipakai applet Wallet, dan sertifikasi Aliro ditujukan untuk wallet/hardware. Kanal in-app memakai AID proprietary dengan **prinsip keamanan setara Aliro**: PKI, ephemeral ECDH, identitas terenkripsi sebelum reader terautentikasi. | O-L04, O-L05, O-A02 | Sedang |
| I-11 | Reader yang mengandalkan **UID/CSN** sebagai identitas **tidak kompatibel** dengan iPhone (UID acak), juga tidak aman. Reader 125 kHz sama sekali tidak bisa dibaca iPhone. | O-A23, E23 | Tinggi |
| I-12 | Dengan OSDP Transparent Mode yang kini terbuka, **logika protokol Anastrophe dapat dijalankan di gateway/panel** melalui reader transparan yang sudah terpasang. Syaratnya reader mendukung pass-through ISO 14443-4 untuk AID kustom. Ini mengurangi kebutuhan mengganti reader. | O-R01, U03 | Sedang |
| I-13 | **BLE adalah satu-satunya kanal in-app yang sudah terbukti untuk iPhone di wilayah non-eligible** (praktik HID). Keandalan background lebih rendah dan butuh reader ber-BLE. | O-B01, O-B04 | Tinggi |
| I-14 | Ketiadaan Apple Pay di Indonesia (O-P02) **meningkatkan risiko** bahwa Apple Wallet Access juga belum tersedia di ID. Ini belum terbukti, karena Program Guide tidak mencantumkan batasan wilayah (U07). | O-P02, E21 | Rendah |
| I-15 | `BGAppRefreshTask` berjalan tanpa UI foreground, sehingga operasi kunci `.userPresence` yang butuh UI autentikasi tidak bisa diselesaikan di sana. Jadi perpanjangan sertifikat di background **tidak dapat** membuat tanda tangan kunci kredensial (ADR-0009). Tanda tangan tetap bisa dibuat tanpa prompt kedua dengan memakai ulang `LAContext` yang baru diautentikasi untuk tap. | O-A25, O-A26, O-A27 | Sedang: belum diuji di perangkat |

---

## 6. Unknowns (belum terjawab — butuh otoritas/lingkungan)

| ID | Unknown | Otoritas/lingkungan yang dibutuhkan | Dampak | Status |
|---|---|---|---|---|
| U01 | Format teknis persis kartu yang didukung Samsung (tipe chip, data yang dibaca, applet eSE). | Analisis biner sah atau dokumen Samsung. | Rendah — Anastrophe tidak meng-clone. | Terbuka (tidak diprioritaskan) |
| U02 | Apakah/kapan Apple menambahkan **Indonesia** ke NFC & SE Platform. | Apple Developer Relations. | **Tinggi** | Terbuka — dicek ulang live 2026-11-01: belum |
| U03 | Model reader/ACS di gedung target; dukungan AID kustom, OSDP Transparent Mode, ECP v2.3, Aliro. | Vendor ACS mitra + survei lokasi. | **Tinggi** | Terbuka |
| U04 | Biaya komersial & SLA perjanjian NFC & SE Platform. | Apple (di bawah NDA). | Sedang | Terbuka |
| U05 | Apakah Core NFC dapat membaca identitas semua kartu legacy target (mis. MIFARE Classic 1K dilaporkan bermasalah, E08; DESFire dengan *random ID*). | Uji perangkat nyata dengan sampel kartu. | Sedang | Terbuka — kasus uji TC-ENR-14..16 |
| U06 | Latensi end-to-end dan ambang timing anti-relay yang dapat diterima reader target. | Uji HIL dengan reader nyata. | Sedang | Terbuka — TC-PERF-01, TC-SEC-01 |
| U07 | Apakah **Apple Wallet Access Program** menerima Anastrophe sebagai Credential Manager, dan apakah access pass tersedia di **Indonesia** dan wilayah pilot. | Apple (access-partnerships@group.apple.com). | **Tinggi** | Terbuka |
| U08 | Dukungan `CardSession` untuk APDU *extended length* / *command chaining*. | Uji perangkat; DTS Apple. | Rendah — protokol ANP/1 didesain < 255 B per APDU | Terbuka |
| U09 | Syarat lisensi/keanggotaan CSA dan sertifikasi Aliro untuk reader/gateway buatan sendiri. | CSA. | Sedang | Terbuka |
| U10 | Posisi antena NFC dan ergonomi tap pada **iPhone Duo** (form factor baru). | Uji perangkat. | Rendah | Terbuka |
| U11 | Keandalan unlock BLE di background pada iOS 26/27 (latensi, efek mode hemat daya). | Uji lapangan. | Sedang | Terbuka |
| U12 | Biaya/fee Apple Wallet Access Program dan sertifikasi IOT reader. | Apple. | Sedang | Terbuka |
| U13 | Kebijakan Apple terhadap **dua jalur sekaligus** dalam satu app (pass Wallet + kredensial in-app untuk kartu yang sama). | Apple (App Review/ABR). | Sedang | Terbuka |

---

## 7. Ringkasan untuk pengambil keputusan

1. **Meniru Samsung 1:1 di iOS lewat app biasa tidak mungkin** (I-02): iPhone tidak dapat meng-clone kartu akses fisik, dan UID iPhone diacak per tap (I-11).
2. **Ada tiga kanal resmi** untuk kredensial akses di iPhone:
   - **Kanal W — Apple Wallet Access Program** (Aliro/DESFire/Seos): paritas UX tertinggi dengan Samsung (Express Mode, power reserve, Apple Watch). Syaratnya kemitraan dengan Apple, reader ECP v2.3 bersertifikat IOT, dan infrastruktur SLA 99,99% (I-08).
   - **Kanal N — NFC dalam aplikasi**: `CredentialSession` (Secure Element, wilayah eligible termasuk HK/MY/SG/TW/VN) atau `CardSession` (HCE, EEA). Butuh entitlement dan app harus dibuka.
   - **Kanal B — BLE dalam aplikasi**: berlaku di semua wilayah termasuk Indonesia, sudah dipraktikkan HID (I-13). Butuh reader ber-BLE.
3. **Rekomendasi:** bangun backend sebagai *Credential Manager* yang agnostik kanal. MVP memakai kanal N (pilot di SG/MY/HK) dan kanal B (fallback universal; satu-satunya kanal in-app untuk Indonesia). Ajukan Apple Wallet Access Program secara paralel untuk fase 2 dengan Aliro (I-09).
4. Risiko terbesar: wilayah (Indonesia belum eligible, Apple Pay belum ada), persetujuan program Apple (U07), dan kompatibilitas reader (U03).

---

## 8. Verifikasi klaim dengan JEV (lapisan keputusan, ADR-0018)

16 klaim faktual kunci yang dipakai di PRD/SDD diverifikasi dengan `jev_verify` (model `jev-1.14.0`, 2026-11-01) terhadap kutipan verbatim dari E01, E03, E04, E11–E13, E15–E17, E21. Hasil: **16/16 verified** (confidence 0,82–1,0; semua `auto`), 0 contradicted, 0 unsupported. Input dan output mentah: [`jev-verify/`](jev-verify/).

| Klaim (ringkas) | Bukti | Confidence |
|---|---|---|
| Indonesia bukan wilayah eligible NFC & SE | E13 | 0,82 |
| HK/MY/SG/TW butuh iOS 18.4+; Vietnam iOS 26.0+ | E13 | 0,98 / 1,0 |
| HCE `CardSession` untuk EEA; emulasi ≤ 60 dtk | E04 | 1,0 |
| Assertion 15 dtk + tunggu 15 dtk; SE maks 2 assertion/80 dtk; wired timeout 15 dtk | E03, E11, E12 | 0,96–1,0 |
| Wallet: DESFire/Seos/Aliro; ECP v2.3+; 99,99% & p90 < 2,2 dtk; Express default aktif | E21 | 0,97–1,0 |
| Aliro 1.0 dirilis 26 Feb 2026 | E17 | 1,0 |
| iOS 26 menghapus XS/XS Max/XR | E15 | 1,0 |
| App wajib menyediakan hapus akun in-app | E16 | 1,0 |
| Samsung: maks 8 kartu, kartu terenkripsi tidak didukung | E01 | 1,0 |
