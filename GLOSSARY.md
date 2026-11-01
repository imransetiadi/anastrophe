# Glossary — Anastrophe

Bahasa domain bersama (*ubiquitous language*) untuk PRD, SDD, QA Suite, kode, dan percakapan. Dikelola dengan skill `domain-modeling`. Bila istilah berubah, perbarui file ini **dan** ADR terkait di `docs/adr/`.

## Inti domain

| Istilah | Definisi | Bukan | Nama di kode |
|---|---|---|---|
| **Gedung (Site)** | Properti fisik yang dikelola satu operator, dengan Site CA, zona, dan reader sendiri. | Organisasi (satu organisasi bisa punya banyak gedung) | `Site` |
| **Organisasi** | Badan operator/pengelola yang memiliki satu atau lebih gedung. | Pengguna akhir | `Organization` |
| **Zona** | Kelompok pintu/reader dengan aturan akses sama, misalnya Lobi, Lift lt. 10, Parkir. | Reader individual | `Zone` |
| **Reader** | Perangkat di pintu yang berkomunikasi dengan iPhone lewat NFC/BLE dan meneruskan keputusan ke panel. | Panel/ACS | `Reader` |
| **Reader group** | Kumpulan reader di satu gedung yang berbagi satu pasangan kunci identitas. Dipakai untuk membuktikan ke iPhone bahwa reader itu sah sebelum identitas kredensial diungkap. | Site CA | `ReaderGroup` |
| **Edge Gateway** | Perangkat di gedung yang menjalankan ANP/1 untuk reader transparan (OSDP Transparent Mode) dan menyinkronkan cache/denylist. | Reader | `EdgeGateway` |
| **ACS (panel)** | Access Control System milik operator: memutuskan buka/tolak berdasarkan identitas yang diteruskan reader. | Backend Anastrophe | `AccessControlSystem` |
| **Kartu fisik** | Kartu/fob plastik yang sudah ada; dipakai **hanya** sebagai bukti kepemilikan saat enrolment. | Kredensial | `PhysicalCard` |
| **Registri kartu** | Daftar kartu fisik milik gedung (identitas & kontak pemegang dalam bentuk HMAC, zona). | Database kredensial | `CardRegistry` |
| **Identitas kartu** | Nilai yang dibaca dari kartu fisik saat enrolment (UID ISO 14443A/15693/FeliCa, atau ID aplikasi ISO 7816). Hanya dikirim lewat TLS lalu di-HMAC per gedung; tidak pernah disimpan, dicatat, atau dipakai sebagai faktor autentikasi. | Kredensial | `CardIdentity` |
| **Perangkat tambahan** | Perangkat yang mendaftarkan kartu fisik yang sudah dipegang perangkat lain. Sebelum ada akun, card instance-nya menunggu persetujuan operator (ADR-0032). | Anggota (setelah akun ada) | — |
| **Enrolment terbengkalai** | Card instance `PROVISIONING` tanpa kredensial yang melewati 15 menit; menjadi `ABANDONED` dan tidak lagi memakai slot (ADR-0034). | Ditolak operator (`REJECTED`) | `ABANDONED` |
| **Kartu (digital)** | Hak akses seorang pengguna atas satu kartu fisik/undangan di satu iPhone, seperti yang terlihat di daftar Kunci. Maksimal 8 per perangkat. | Kredensial (satu kartu bisa punya kredensial per kanal) | `CardInstance` |
| **Kredensial** | Pasangan kunci + sertifikat untuk **satu kanal** dari sebuah kartu digital. Kunci privatnya tidak pernah keluar dari Secure Enclave/SE. | Kartu fisik; pass Wallet | `Credential` |
| **Sertifikat kredensial** | Pernyataan yang ditandatangani Site CA: `cred_id`, kunci publik, zona, dan masa berlaku (default 7 hari). | Sertifikat TLS | `CredentialCert` |
| **Site CA** | Kunci penandatangan per gedung (disimpan di HSM) untuk sertifikat kredensial dan reader group. | CA TLS publik | `SiteCA` |
| **Pass Wallet** | Access pass di Apple Wallet (kanal W). Dikelola via Apple Access Platform. | Kredensial in-app | `WalletPass` |
| **Kanal** | Cara iPhone mempresentasikan kredensial: **W** (Apple Wallet), **N** (NFC in-app: N-SE / N-HCE), **B** (BLE in-app). | Transport jaringan | `Channel` |
| **Presentasi** | Satu transaksi iPhone ↔ reader untuk membuka akses. | Enrolment | `Presentment` |
| **Enrolment** | Proses menambah kartu: verifikasi kepemilikan → security code → provisioning kredensial. | Provisioning saja | `Enrollment` |
| **Provisioning** | Pembuatan kunci + penerbitan sertifikat (N-HCE/B), instalasi + personalisasi applet (N-SE), atau *Add to Apple Wallet* (W). | Enrolment (lebih luas) | `Provisioning` |

## Peran

| Istilah | Definisi | Nama di kode |
|---|---|---|
| **Pemegang utama (PRIMARY)** | Pengguna yang kontak terverifikasinya cocok dengan pemegang di registri (ADR-0004). Membuat security code dan mengelola anggota. | `Role.primary` |
| **Anggota (MEMBER)** | Pengguna yang bergabung ke kartu pemegang utama dengan security code. Tidak dapat mengelola anggota lain. | `Role.member` |
| **Admin gedung** | Peran portal: Org Owner, Site Admin, Security Officer (audit read-only), Helpdesk, Integrator. | `AdminRole` |
| **Credential Manager / Credential Provider / Participating Provider** | Peran dalam Apple Wallet Access Program (O-W03). Anastrophe menargetkan Credential Manager + Credential Provider (Aliro); operator gedung = Participating Provider. | — |

## Keamanan & lifecycle

| Istilah | Definisi | Nama di kode |
|---|---|---|
| **Security code** | Kode 6 digit buatan pemegang utama; diverifikasi server dan dibatasi percobaannya (ADR-0005). | `SecurityCode` |
| **Undangan** | Token sekali pakai dari admin untuk enrolment tanpa kartu fisik (ADR-0033). Bisa diikat ke kartu terdaftar; undangan berkartu sekaligus menyetujui enrolment perangkat itu yang masih menunggu untuk kartu tersebut (ADR-0035). | `Invitation` |
| **Sengketa klaim** | Laporan pemegang sah bahwa kartunya diklaim orang lain; diputuskan admin (FR-59). | `ClaimDispute` |
| **Suspend / Resume** | Penangguhan sementara kredensial/pass (pengguna, admin, atau Lost Mode). Sebelum portal ada, operator memakai CLI `anastrophe-registry suspend\|resume` (ADR-0036). | `suspend()` / `resume()` |
| **Revoke (cabut)** | Penonaktifan permanen kredensial; masuk denylist reader. | `revoke()` |
| **Denylist** | Daftar `cred_id` yang dicabut, disinkronkan ke reader/gateway. Ditulis saat pencabutan oleh operator maupun hapus kartu, sampai sertifikatnya kedaluwarsa (ADR-0036). | `Denylist` |
| **Token baca status** | Token 32 byte per kartu digital yang dibuat app untuk membaca status kartu dari server tanpa Face ID atau passcode; server hanya menyimpan hash-nya (ADR-0037). | `StatusToken` |
| **Transfer perangkat** | Re-provisioning ke iPhone baru dan pencabutan kredensial lama (ADR-0007). | `DeviceTransfer` |
| **Perpanjangan** | Penerbitan ulang sertifikat untuk kunci yang sama (FR-45). Hanya setelah autentikasi tap: sertifikat kedaluwarsa diperpanjang sebelum presentasi, sisa < 50% setelah tap (ADR-0023). | `CredentialRenewer`, `RenewalScheduler`, `RenewalPolicy` |
| **Nonce perpanjangan** | 32 B acak dari server, berlaku 120 dtk, sekali pakai, terikat ke satu kredensial (SDD §8.4.2). | `RenewalChallenge` |
| **Bukti kepemilikan** | Tanda tangan kunci kredensial atas nonce server yang membuktikan perangkat masih memegang kunci: `"ANP1-RENEW"` ‖ `cred_id` ‖ nonce untuk perpanjangan, `"ANP1-REVOKE"` ‖ `cred_id` ‖ nonce ‖ ID kartu untuk hapus kartu (ADR-0026). | `RenewalChallenge.message(credentialID:)`, `revokeMessage(credentialID:cardID:)` |
| **Backend penerbit** | Base URL backend yang menerbitkan kredensial, disimpan per record untuk perpanjangan. Kartu tanpa backend penerbit (lab `lab_ca.py`) tidak diperpanjang. | `CredentialRecord.renewalURL` |
| **Rantai audit** | Urutan baris `audit_events` per gedung (`site:<uuid>`) yang saling terhubung lewat hash; satu rantai per gedung (ADR-0024). | `AuditChain(siteID)` |
| **Rantai platform** | Rantai audit untuk event tanpa gedung (mis. `account.deleted`). | `AuditChain("")` |
| **Head rantai** | Baris terakhir sebuah rantai `(chain, seq, hash)`, dicatat per jam ke log terpusat sebagai anchor parsial. | `AuditHeads` |
| **Perlu diperbarui** | Status tampilan kartu aktif dengan sisa masa berlaku < 24 jam atau yang sudah lewat (FR-38, TC-DEV-10). | `CardStatus.needsRenewal`, `Card.displayStatus` |
| **UNREACHABLE** | Status server untuk kredensial yang perangkatnya tidak lagi melapor (mis. app dihapus). | `.unreachable` |

## Protokol & platform

| Istilah | Definisi |
|---|---|
| **ANP/1** | Anastrophe Protocol v1: protokol kanal N/B (AID `F0414E415354524F01`), ECDH P-256 + ECDSA + AES-GCM (ADR-0003, SDD §7). |
| **AID / APDU** | Application Identifier / unit perintah ISO 7816-4. |
| **Aliro** | Standar CSA untuk kredensial akses mobile; dipakai di kanal W (R2). |
| **ECP / TCI / TRA** | Enhanced Contactless Polling / Terminal Capabilities Identifier / Terminal Requested Authentication (fitur reader untuk pass Wallet). |
| **Express Mode** | Memakai pass Wallet tanpa Face ID/Touch ID/passcode (hanya kanal W). |
| **Presentment intent assertion** | Klaim eksklusif sementara atas UI kontak agar app default (mis. Apple Pay) tidak muncul (N). |
| **Secure Enclave / Secure Element (SE)** | Prosesor keamanan untuk kunci & biometrik / chip aman tempat applet kredensial berjalan. |
| **OSDP Transparent Mode** | Mode OSDP yang meneruskan data aplikasi (APDU) dari reader ke panel/gateway lewat kanal aman. |

## Lab & pengujian

| Istilah | Definisi |
|---|---|
| **Reader uji** | Peripheral BLE untuk pengujian lab (rig R7) yang menjalankan sisi reader ANP/1. Bentuknya (Mac atau dev board) menunggu ADR-0022. |
| **devseed** | Perintah dev `anastrophe-devseed` yang menyiapkan gedung, reader group, dan perangkat lab; hanya untuk database lokal. |
| **Provisioning lab** | Alur DEBUG yang mengambil kartu langsung dari backend dev (`-ANLabBackend`) atau dari `lab_ca.py`; tidak ada di build Release. |

## Istilah yang dihindari

- "Clone kartu" atau "salin kartu". Gunakan "tambah kartu" atau "enrolment" (ADR-0001).
- "NFC" di teks UI presentasi. Gunakan "Dekatkan bagian atas iPhone ke pembaca kartu".
- "Wallet" untuk kredensial in-app. Istilah itu khusus untuk pass Apple Wallet (kanal W).
