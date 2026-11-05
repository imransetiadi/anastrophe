---
type: backlog
project: anastrophe
updated: 2026-11-04
---
# Backlog minor tertunda (terverifikasi terhadap kode, 2026-11-01)

Ledger rencana (`.superpowers/sdd/*/progress.md`) tidak ikut git dan sebagian catatan "minor (deferred)" di sana sudah usang. Daftar ini mencocokkan catatan itu dengan kode saat ini. Hanya item yang benar-benar terbuka yang tersisa di bagian **Terbuka**.

## Sudah selesai (diperiksa di kode)

| Catatan lama | Bukti |
|---|---|
| Responder ANP/1 menandai terautentikasi sebelum identitas tersegel | `ANP1Responder` baru mengeset `.authenticated` setelah `sealIdentity` berhasil; kegagalan kembali ke `.selected` |
| P1/P2 tidak divalidasi (nonce `GET_CERT` berulang dengan AAD berbeda) | Perintah kelas 0x80 wajib P1 = P2 = 0, jadi AAD konstan |
| Reader di bawah ambang menampilkan "Waktu habis" (TC-PRSB-05) | Fase `readerOutOfRange` punya teks dan ikon sendiri |
| Buffer `BLEFrameAssembler` tidak dibatasi | `maxMessageSize = 256` dengan guard |
| `PresentmentLimits.hceSessionSeconds` tak terpakai | Sudah tidak ada di kode |
| `hasKey` menelan galat Keychain | `RestoreCheck` memakai `try?` sehingga galat tidak menandai kartu "Perlu dipindahkan" |
| Fallback penyimpanan diam-diam di Release | `AppEnvironment` jatuh ke `storageUnavailable()`, bukan layanan in-memory |
| devseed tanpa guard dev | Hanya database lokal kecuali `-allow-remote` (`TestHanyaDatabaseLokal`) |
| Kanal respons server tidak dicek | `provisionViaBackend` menolak kanal yang berbeda |
| Kode `URLError` tidak tampil di pesan DEBUG | Pesan lab memuat kode `URLError` |
| `zones` nil tersimpan sebagai `null` | Respons provisioning memakai `[]` (test `zones` harus `[]`) |
| `-ANDemoScreen presentation` memulai presentasi live | Layar presentasi tidak dibuka otomatis |
| Peringatan Swift 6 di `LiveCardEmulation` | Tidak muncul lagi di build terakhir |
| Kebersihan skrip lab (`__pycache__`, `init` menimpa `site.json`, tmp berisi kunci CA) | `__pycache__/` di-ignore; `init` butuh `--force` dan menulis dengan izin 0600; test memakai `addCleanup(shutil.rmtree, ...)` |
| Penerbitan kredensial lewat id instance dari `:challenge` (prioritas tinggi, review akhir siklus hidup) | ADR-0040: provisioning wajib rahasia enrolment dan hanya untuk instance `PROVISIONING` (`TestProvisioningTanpaRahasiaIdentik`; lab: 404 tanpa rahasia) |
| Minor siklus hidup M1/M3/M4/M5b/M6/M8, provisioning M1/M2/M4/M5/M6, undangan M4/M6/M7(id)/M9 | Rencana perbaikan minor (ADR-0042): update dijaga status, urutan kunci perpanjangan, denylist dari sertifikat terpanjang + purge, pembaruan kartu terarah, jam `ContinuousClock`, parameter rahasia wajib, CLI id undangan dan `--link-base` `/i/` |
| Deadlock 40P01 enrolment–sapuan per jam (pra-ada, review perbaikan minor), termasuk audit `abandonStale` lintas gedung | ADR-0051: audit enrolment dan sapuan ditahan lalu ditulis di akhir transaksi, berurutan per rantai; lanjutan `PENDING_APPROVAL` dikunci di dalam enrolment (`TestEnrolmentKartuTidakMemegangKunciAuditSaatMenunggu`, `TestSapuanMenulisAuditBerurutanPerRantai`, TC-DR-05). siklus dengan `DecideEnrollment` diputus kunci lanjutan `PENDING_APPROVAL`; siklus dengan `policy`/`site-code` (`sites FOR UPDATE`) diputus `FOR KEY SHARE` baris gedung sebelum kunci rantai (`TestEnrolmentTidakMemegangKunciRantaiSaatMenungguBarisGedung`) |
| Aksesibilitas, sisa Task 4–5 (ADR-0057): GREEN UI test di dua perangkat, mutasi UI, `strings` Release, screenshot, pengecualian per elemen, penjaga mode gelap, UI test fungsional "Gunakan", dokumen | QA §11.1 TC-UX-01–04 dan TC-UX-09, SDD §5.10; `KunciFungsionalTests`, `testPenjagaModeMenolakModeSalah`, mutasi `present.cancel` dan label Bantuan tertangkap |
| Sisa instal ulang: item Keychain dari instalasi lama tidak dibersihkan (alur Tambah Kartu, ADR-0043) | ADR-0053: semua item service app dihapus pada peluncuran pertama tanpa penanda dan tanpa kartu lokal, sebelum layanan dipakai (`instalUlangMembersihkanSisa`, TC-DEV-13) |

## Terbuka

- **Aksesibilitas (ADR-0057; rencana selesai, penutupan unit tertunda):**
  - `jev_gate` dijalankan 2026-11-06 (dua run, bukti bertambah di run kedua): **eskalasi** kedua kali (composite 0,66 lalu 0,58; limiting rubric `test_gap` lalu `correctness`; 0 klaim `contradicted` di kedua run). Menunggu keputusan pengguna: terima penutupan berdasarkan bukti uji nyata yang sudah tercatat, atau minta review akhir manusia/subagent atas `AnastropheUITests/AccessibilityAudit.swift` (harness +829 baris, di luar batas payload gate). Log: `docs/adr/jev-log/2026-11-06-audit-aksesibilitas-gate.json`, sesi: `sessions/2026-11-06-audit-aksesibilitas-gate.md`.
  - Pemeriksaan VoiceOver manual di iPhone fisik (sisi H TC-UX-01), TC-UX-05 dengan Reduce Motion aktif, dan CI untuk UI test.
  - Pesan galat belum dicocokkan butir per butir dengan katalog SDD §15 (butir terakhir checklist design system §9).
  - Audit Apple di riwayat AX5 halaman 2 (iPhone 17e) selalu habis waktu dan kini lulus lewat audit ulang sesudah isi digeser 48 pt. Bila pola ini muncul di posisi lain, selidiki penyebabnya, mis. jumlah baris riwayat demo.
- **Test BLE flaky:** `autentikasiBatalMembatalkanPemindaian` sesekali gagal (`scanCount == 0 || scanWasCancelled`) saat mesin sangat sibuk, lalu lulus 6/6 saat diulang. Pembatalan pindai belum tercatat sebelum aliran selesai.

- **Audit:** waktu event bisa mundur sepanjang `seq` (waktu dari pemanggil); peran DB runtime masih pemilik tabel (perlu pemisahan peran di infrastruktur produksi).
- **Hapus kartu:** penghapusan lokal masih *best-effort*; penghapusan yang terputus setelah 204 pulih lewat `CARD-GONE`; `DELETE` membawa body (RFC 9110).
- **Perpanjangan:** celah test (cek kanal dan kunci group di renewer, kredensial non-ACTIVE di backend); slot pekerjaan tunggal tidak terikat ke tap; renewer menulis salinan kartu lama; endpoint `:challenge` tanpa autentikasi bisa memperbesar tabel (dibersihkan per jam) dan membedakan status kredensial; drift dokumen (ADR-0023 "paralel", SDD §8.4.2 App Attest, QA TC-DEV-09).
- **Presentasi:** hitung mundur HCE mulai saat lembar muncul dan angka `coolingDown` tidak berkurang (belum diverifikasi ulang); presentasi tumpang tindih (`heldIntent` dan `connectWaiters`); panjang fragmen BLE memakai panjang tulis `.withResponse`; paritas timing mengasumsikan maksimal 2 kunci per group.
- **Prioritas tinggi, keamanan (review akhir provisioning aman I1):** tanpa autentikasi perangkat, pihak yang tahu id perangkat dan identitas kartu (atau token undangan) bisa mengganti hash rahasia enrolment instance yang belum selesai lalu memprovisikannya. Menunggu keputusan pengguna di ADR-0041 (rekomendasi `first_writer_wins`).
- **Siklus hidup kartu (sisa setelah rencana perbaikan minor):**
  - Pendaftaran ulang kartu fisik bisa membatalkan suspend/revoke (C1): menunggu keputusan pengguna di ADR-0038.
  - `CRED-NOT-RENEWABLE` belum dipetakan ke Ditangguhkan untuk kartu pra-fitur tanpa token (M5a; ambigu dengan kill switch).
  - Test tabel lengkap untuk pemetaan status (M7); pesan transisi ilegal CLI bisa menyarankan `reject` untuk `PENDING_APPROVAL` (M10).
  - Perpanjangan dan `KeysViewModel.load` masih menulis ulang seluruh kartu, sehingga perubahan status dari penyegar bisa terbalik sampai penyegaran berikutnya (review perbaikan minor 5).
  - Purge denylist belum memberi margin toleransi jam reader ±5 menit; belum berdampak sebelum Site Sync ada (review perbaikan minor 4).
  - Belum ada indeks `denylist_entries.expires_at` (review perbaikan minor 9).
- **Provisioning (sisa):** penolakan operator yang bersamaan dengan perangkat melanjutkan instance menunggu kini membuat permintaan `PENDING_APPROVAL` baru (201), sama dengan pengiriman ulang sesudah penolakan; dulu `ENR-DUPLICATE` (review perbaikan minor 7). Perilaku ini direproduksi reviewer ADR-0051 tetapi belum dipin test; rahasia dan hash-nya sama-sama `Data`, jadi tertukar di pemanggil tetap terkompilasi; bawaan `update(id:)` non-atomik bisa terpakai diam-diam oleh store pembungkus baru (review perbaikan minor 9).
- **Test konkurensi:** tiga test baru memakai jeda 300 ms; di runner lambat bisa lulus tanpa menguji balapan (tidak pernah gagal palsu); ganti dengan polling `pg_stat_activity` (review perbaikan minor 8).
- **Undangan (sisa):**
  - Melanjutkan instance ditolak setelah undangan kedaluwarsa, walau instance masih `PROVISIONING` (M2).
  - Waktu respons berbeda per jalur (tak dikenal ±122 µs, terpakai ±183 µs); tidak bisa dieksploitasi tanpa token 256 bit, perlu dicatat di TC-ENR-08 (M3).
  - Belum ada pencabutan undangan (bersama FR-51) (sisa M7).
  - Test kecil: galat tebusan pertama diabaikan (M12).
- **Gerbang pra-pilot (prioritas tinggi, keamanan; review akhir alur Tambah Kartu):**
  - **Enumerasi kartu (ADR-0046, menunggu pengguna):** enrolment adalah oracle tebakan identitas kartu tanpa autentikasi (NUID 4 byte, `site_id` dari kode gedung, `device_id` bebas). Wajib App Attest ditambah pembatas atau deteksi kegagalan `ENR-NOT-REGISTERED` sebelum backend dibuka untuk pilot (TC-SEC-15).
  - **Kedaluwarsa permintaan (ADR-0047, menunggu pengguna):** `PENDING_APPROVAL` masih tanpa kedaluwarsa, walau batas 4 per kartu sudah diterapkan.
  - **Info perangkat:** CLI `list` belum menampilkan info perangkat (mis. waktu pertama terlihat) untuk membedakan permintaan menunggu.
- **Alur Tambah Kartu (sisa, ADR-0043):**
  - **Persetujuan operator:** instance yang disetujui ditandai `ABANDONED` 15 menit setelah persetujuan bila perangkat belum kembali. Tanpa push (FR-62), penghuni sering melewatkan jendela itu dan permintaannya kembali menunggu. Memperpanjang umurnya melebarkan jendela risiko ADR-0041, jadi diputuskan bersama ADR-0041. Jalur yang andal saat ini: undangan berkartu (ADR-0035).
  - **Kartu placeholder:** "Menunggu persetujuan" di daftar (tampilan FR-17) belum ada; hasilnya hanya tampil di lembar.
  - **App Attest (NFR-S03):** belum diterapkan, dan wajib sebelum pilot. Perangkat dibuat di transaksi enrolment (ADR-0045, provisional); attestation kelak ditempel ke enrolment pertama.
  - **Jenis kartu:** FeliCa (butuh system code per gedung di Info.plist) dan identitas berbasis AID untuk DESFire random UID (TC-ENR-15) belum didukung.
  - **Urutan byte ISO 15693:** urutan `identifier` dari Core NFC perlu dicocokkan dengan format registri (`e004…`) lewat uji H.
  - **Universal Link:** entitlement Associated Domains dan berkas AASA menunggu domain produksi. Sampai itu, tautan undangan ditempel ke field.
  - **Pembatasan laju:** `GET /v1/sites/lookup` belum dibatasi laju (diserahkan ke infrastruktur). Kode 40 bit tidak praktis ditebak.
  - **Minor review akhir** (pengguna memutuskan apakah dikerjakan):
    - **#4 pembacaan kartu:** cabang ISO 7816 belum terjangkau tanpa `select-identifiers` (Unknown, uji H). App belum punya batas waktu baca sendiri (±20 dtk) maupun petunjuk undangan setelah Batal; kartu yang tidak pernah dilaporkan Core NFC menunggu batas waktu sistem ±60 dtk.
    - **#5 siklus hidup pembaca:** batal sebelum sesi dimulai masih memulai sesi, dan panggilan kedua bersamaan dijawab `cardReaderUnavailable`. Penjaga identitas sesi sudah diperbaiki.
    - **#6 test identitas:** `identitasKartuTidakTertinggal` lebih lemah dari klaim Review Focus 1, karena deskripsi `CardIdentity` sudah disamarkan. Perlu tambahan cek base64, huruf besar, dan `Mirror`.
    - **#8 tautan saat app dingin:** `onOpenURL` kemungkinan melewatkan tautan yang membuka app dari keadaan mati (`KeysView` baru ada setelah layanan siap). `-ANLabOpenURL` juga tidak lewat `onOpenURL`. Laten sampai Associated Domains.
    - **#9 normalisasi kode:** karakter tak terlihat (U+200B, U+FEFF, U+200E) dan tanda hubung tipografis ditolak; `ß` diterima Swift tetapi ditolak Go. Vektor test disalin, bukan fixture bersama.
    - **#11 nits:**
      - subject audit rotasi memakai `siteID` dari pemanggil;
      - `deviceID()` melakukan I/O sinkron di main actor;
      - doc paket devseed masih menyebut keluaran lama;
      - `site-code` tanpa `--site` dijawab "gedung tidak ditemukan";
      - `SiteJoinCode.display` belum terpakai.
- **Bantuan (minor review akhir, ADR-0048)** — pengguna memutuskan apakah dikerjakan:
  - **M1 status kanal:** nilai awal kosong sempat terbaca "belum tersedia" sebelum dimuat; status tidak disegarkan setelah kembali dari Pengaturan; `availability()` dipanggil dua kali.
  - **M2 tautan undangan:** tautan yang dibuka saat Bantuan tampil tertahan sampai Bantuan ditutup (laten sampai Associated Domains).
  - **M3 isi laporan:** tanggal berlaku ditulis dalam UTC, bukan waktu lokal; belum ada stempel waktu pembuatan; `bahasa` memakai `Locale.current`, bukan bahasa app; status enum ditulis lewat deskripsi implisit.
  - **M5 hapus kartu:** jawaban belum menyebut butuh internet dan Face ID/kode sandi; EN "through this iPhone" berbeda dari dialog ("with this iPhone").
  - **M7 klaim tanpa bukti:** Bluetooth "semua wilayah" tanpa syarat gedung memakai pembaca Bluetooth (sudah di SDD, belum di salinan app); klaim hapus lewat Lacak tanpa ID bukti; "autentikasi" di jawaban ponsel hilang belum diganti "Face ID, Touch ID, atau kode sandi".
  - **M8 duplikasi:** salinan perangkat didukung ada di empat string.
  - **M10 aksesibilitas:** `ProgressView` laporan belum berlabel.
- **Kebijakan gedung (minor review akhir, ADR-0049)** — pengguna memutuskan apakah dikerjakan:
  - **Cek lebih awal:** kanal gedung baru diperiksa sesudah penghuni menempel kartu, padahal kelayakan perangkat sudah diketahui di langkah konfirmasi gedung.
  - **Galat domain:** `ENR-INVALID-CHANNEL` belum dipetakan ke galat domain di app, sehingga kebijakan yang berubah di antara enrolment dan provisioning tampil sebagai galat umum.
  - **Tolak lebih awal (butuh perubahan spec/ADR):** server bisa menolak enrolment bila kanal efektif gedung kosong, sesudah bukti kartu atau token, untuk menghindari slot/undangan tertahan.
  - **E2e belum dijalankan:** jalur pembatasan non-kosong (`--channels ble`) belum diuji e2e; sudah tercakup test unit.
  - **Perpanjangan:** perpanjangan tetap menerbitkan sertifikat untuk kanal yang kemudian dilarang gedung (ADR-0023; butuh keputusan sendiri).
- **Filter daftar kartu (minor review akhir, ADR-0050):**
  - CLI mengulang validasi awalan id store hanya untuk memilih pesan galat; lebih baik `CardInstanceFilter.Validate()` sebelum membuka database.
  - Aturan status kredensial (ACTIVE/SUSPENDED) tertulis dua kali di query (kolom KANAL dan filter `--channel`).
  - Bantuan `--channel` menyebut "kredensial aktif" padahal mencakup SUSPENDED.
  - Awalan id belum divalidasi posisinya sebagai UUID: tanda hubung salah tempat menghasilkan daftar kosong, bukan galat yang jelas.
- **Deadlock enrolment–sapuan (minor review akhir, ADR-0051):**
  - `withDeferredAudits`: belum ada test bahwa galat fn menang atas galat flush; galat flush sisi Go (marshal/NUL) di jalur galat dibuang (payload saat ini tidak bisa memicunya); `deferAudits` tanpa flush tidak dijaga.
  - `TestSapuanMenulisAuditBerurutanPerRantai` menangkap mutasi "tanpa urut" ±69/70 kali (4+4 UUID acak kadang sudah terurut).
  - Lanjutan `PENDING_APPROVAL` di jalur undangan belum dikunci. Cabang ini tak terjangkau saat ini, dan pengerasannya cukup 3 baris seperti jalur kartu.
  - Sisa risiko: kunci rantai memakai `hashtext(chain)`, sedangkan urutan memakai nama rantai; tabrakan hash (±2⁻³² per pasangan) masih bisa memicu 40P01 yang dideteksi PostgreSQL.
- **App Attest — wajib di unit penyambungan (minor review akhir, ADR-0052):**
  - **Challenge sekali pakai:** server menerbitkan dan mengonsumsinya sendiri. `VerifyAttestation` saat ini menerima `clientDataHash` kosong, dan `VerifyAssertion` tidak memeriksa challenge di `clientData`. Pertimbangkan wrapper yang menghitung `SHA256(challenge)` dan callback pemeriksa challenge, dengan test challenge basi.
  - **Penyimpanan per perangkat:** kunci publik dan counter disimpan per perangkat, dan counter diperbarui atomik (compare-and-swap) untuk menolak replay bersamaan.
  - **Receipt:** belum terautentikasi (di luar nonce), jadi jangan dipakai sampai validasi receipt (U15).
  - **Kategori:** `Config.Categories` wajib diisi di produksi. Saat ini kategori 0 (invalid) dan 7–9 diterima bila daftar kosong.
  - **Platform:** tolak platform credCert selain `iphoneos` (OID `1.2.840.113635.100.8.7`), karena attestation macOS butuh cek `aclBlob`.
  - **`Verifier` nilai nol:** panic di `v.now`. Wajibkan `NewVerifier` atau jaga nilai nol.
  - **Uji H (U14):** capture attestation + assertion dari build bertanda tangan dengan App ID Anastrophe, termasuk iOS 26.x.
  - **Catatan kecil:** `p256PublicKey` memakai field `X`/`Y` ecdsa yang ditandai deprecated di toolchain baru (alternatif: SPKI tetap + `x509.ParsePKIXPublicKey`).
- **Pembersihan instal ulang (minor review akhir, ADR-0053):**
  - **Gagal-hapus + enrolment:** bila penghapusan gagal lalu pengguna melakukan enrolment di sesi yang sama, `deviceID()` membuat penanda dan sisa tidak lagi dicoba. Bisa ditutup dengan memanggil pembersihan di awal enrolment, sebelum `deviceID()`.
  - **Store bersama:** pembersihan bergantung pada satu `SecretStore` yang dipakai semua store di `live()`, dan bawaan protokol `false` membuat pembungkus bisa diam-diam tidak ikut. Tambahkan komentar aturan store bersama, atau hapus bawaan itu.
  - **Rekomendasi:**
    - factory `live()` + `prepareInstall()` dengan test paket;
    - komentar migrasi bila path store kartu berubah;
    - `isProtectedDataAvailable` bila kelak ada peluncuran latar;
    - hitungan item Keychain (tanpa nilai) di layar Lab DEBUG untuk TC-DEV-06/13;
    - `SecItemDelete` jangan di main actor (O-K01; saat ini satu kali saat instal ulang).
  - **Pra-ada (ditemukan reviewer):**
    - `.task` bisa membuat `AppServices` kedua sesudah scene tersambung ulang;
    - proteksi SQLite bawaan Core Data mungkin menimpa klaim `.complete` di SDD §5.3;
    - deteksi restore di SDD tidak cocok dengan store kartu yang dikecualikan dari backup.
- **Observabilitas backend (minor review akhir, ADR-0054):**
  - **Test wiring produksi:** wiring `request_id` produksi (`loggerFromEnv` + `WithRequestID`) belum dipin test end-to-end. Reviewer memverifikasinya lewat uji asap.
  - **CONNECT:** redirect trailing-slash pada CONNECT bisa menjadikan path mentah sebagai pola. Ini laten sampai ada rute subtree; perlakukan CONNECT sebagai `/` atau batasi jumlah rute di `Metrics`.
  - **Panic sesudah header:** panic sesudah header ditulis tercatat sebagai 200. Tandai `panicked` di recoverer agar terhitung 500.
  - **413:** 413 tidak lagi menutup koneksi, karena `statusRecorder` menyembunyikan `requestTooLarge`. Set `Connection: close` di `readBody` saat `MaxBytesError`.
  - **Rekomendasi:**
    - `ErrorLog` `http.Server` ke slog level Warn, karena log net/http sendiri bisa memuat IP saat panic lolos middleware;
    - `ANASTROPHE_LOG_FORMAT` tidak peka huruf besar, atau tolak nilai tak dikenal.
- **Uji beban (temuan baseline lab, ADR-0055):**
  - **Rute gabungan:** challenge dan renew berbagi pola `POST /v1/credentials/{action}`, sehingga latensinya tidak bisa dibedakan di `/metrics`. Pertimbangkan rute terpisah atau label aksi terbatas.
  - **Enrolment melambat pada c=32:** p95 naik dari 5 ke 25 ms (baseline ulang sesudah review akhir). Kandidat penyebab: serialisasi rantai audit per gedung (semua beban di satu gedung), penandatanganan CA perangkat lunak, dan CPU yang dipakai bersama. Butuh profil (pprof, wait event PostgreSQL) di lingkungan Load dan skenario multi-gedung.
  - **Klien boros CPU:** generator beban sendiri berat (keygen P-256 dan tanda tangan per iterasi enrol/renew). Di lingkungan Load, jalankan klien di mesin terpisah.
  - **Uji belum dikerjakan:** uji 1.000 rps campuran (TC-PERF-05 penuh) dan uji panjang (rendam) belum dilakukan.
  - **Alat (minor tertunda dari review akhir):**
    - validasi input: `-rate` yang sangat besar membuat selang token 0, dan `-offset` bisa negatif atau overflow;
    - pool kartu atau kredensial yang habis tercatat sebagai galat di tabel langkah (exit 3 sudah membedakannya dari galat API);
    - penjaga kartu sintetis hanya memeriksa awalan `084c54`, jadi impor ke gedung sungguhan masih mungkin. Usul: `--allow-synthetic` di `anastrophe-registry import`;
    - laporan belum mencetak metadata run (commit, versi, ukuran pool DB, tujuan log), dan presisi angkanya kasar;
    - celah test: `Measure` yang mencatat durasi nol, serta pernyataan bahwa rahasia tidak muncul di laporan;
    - memori recorder tumbuh tanpa batas pada uji rendam (simpan histogram, bukan semua sampel);
    - laporan mentah baseline hanya tersimpan lokal;
    - koreksi coordinated omission: ukur latensi dari jadwal token (open-loop), agar latensi dekat titik jenuh tidak terlalu optimistis.
- **Pemindaian keamanan (ADR-0056):**
  - **Lingkungan lokal:** perbarui `cryptography` ke 50.* di interpreter pyenv (`python3 -m pip install -r scripts/anp1/requirements.txt`). Pemindai dengan interpreter bawaan tetap exit 1 sampai itu dilakukan.
  - **CI dan hook:** jalankan `scripts/security/scan.py` sebagai langkah CI begitu CI ada, dengan checkout riwayat penuh (`fetch-depth: 0`) dan `pip install -r scripts/*/requirements.txt` lebih dulu. Hook pre-commit (`gitleaks git --staged --redact .`) bersifat opsional dan tidak dipasang otomatis.
  - **Minor review akhir:**
    - include `-r` di berkas requirements belum diikuti;
    - cabang `.package(` belum punya test, dan hanya `Packages/Package.swift` yang dibaca (paket lokal lain dengan dependensi remote akan lolos);
    - satu pemeriksaan yang gagal menghentikan pemeriksaan sisanya, dan exit 2 menutupi temuan nyata;
    - `scan_level` govulncheck tidak dicek (versi terpin memakai `symbol`).
  - **Cakupan yang belum ada:** blob biner di riwayat (mis. `.p12` yang ter-commit), isi commit merge, pesan commit, dan arsip terkompresi di dalam produk build.
  - **Alias OSV:** satu CVE bisa tercetak dua kali (GHSA dan PYSEC). Kelompokkan menurut `aliases` agar jumlah advisori tidak berlipat.
  - **Keparahan Go:** govulncheck tidak memberi skor, jadi kebijakannya "terpanggil = gagal". Tinjau ulang bila ada sumber keparahan yang andal.
  - **Masih terbuka:** audit `.ipa` bertanda tangan (TC-SEC-07), MASVS (TC-SEC-06), SAST, dan pentest eksternal (TC-SEC-12).
- **Test flaky:** `BLETapTests.autentikasiBatalMembatalkanPemindaian` sesekali gagal (pembatalan pemindaian bergantung waktu); lulus 6/6 saat diulang.
- **Riwayat tap:** judul baris "Ditolak · alasan" dirakit di kode (M8; dikerjakan saat bahasa ketiga ditambahkan); VoiceOver baris Status belum diperiksa dengan Accessibility Inspector.
