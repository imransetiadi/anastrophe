---
type: backlog
project: anastrophe
updated: 2026-11-02
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

## Terbuka

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
- **Enrolment dan sapuan per jam (pra-ada, review perbaikan minor):** deadlock 40P01 bisa terjadi bila enrolment mengambil kunci audit gedung lalu menunggu baris yang dipegang sapuan; usulan perbaikan: tulis audit `enrollment.abandoned` di akhir transaksi setelah semua kunci baris diambil. Pola serupa pada `DecideEnrollment` dan audit `abandonStale` lintas gedung.
- **Provisioning (sisa):** penolakan operator yang bersamaan dengan perangkat melanjutkan instance menunggu dijawab `ENR-DUPLICATE` (review perbaikan minor 7); rahasia dan hash-nya sama-sama `Data`, jadi tertukar di pemanggil tetap terkompilasi; bawaan `update(id:)` non-atomik bisa terpakai diam-diam oleh store pembungkus baru (review perbaikan minor 9).
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
  - **Sisa instal ulang:** item Keychain dari instalasi lama (kunci kredensial, token status) tidak dibersihkan.
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
- **Test flaky:** `BLETapTests.autentikasiBatalMembatalkanPemindaian` sesekali gagal (pembatalan pemindaian bergantung waktu); lulus 6/6 saat diulang.
- **Riwayat tap:** judul baris "Ditolak · alasan" dirakit di kode (M8; dikerjakan saat bahasa ketiga ditambahkan); VoiceOver baris Status belum diperiksa dengan Accessibility Inspector.
