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
- **Alur Tambah Kartu (sisa, ADR-0043):**
  - **Persetujuan operator:** instance yang disetujui ditandai `ABANDONED` 15 menit setelah persetujuan bila perangkat belum kembali. Tanpa push (FR-62), penghuni sering melewatkan jendela itu dan permintaannya kembali menunggu. Memperpanjang umurnya melebarkan jendela risiko ADR-0041, jadi diputuskan bersama ADR-0041. Jalur yang andal saat ini: undangan berkartu (ADR-0035).
  - **Kartu placeholder:** "Menunggu persetujuan" di daftar (tampilan FR-17) belum ada; hasilnya hanya tampil di lembar.
  - **App Attest (NFR-S03):** belum diterapkan, dan wajib sebelum pilot. Perangkat dibuat di transaksi enrolment (ADR-0045, provisional); attestation kelak ditempel ke enrolment pertama.
  - **Jenis kartu:** FeliCa (butuh system code per gedung di Info.plist) dan identitas berbasis AID untuk DESFire random UID (TC-ENR-15) belum didukung.
  - **Urutan byte ISO 15693:** urutan `identifier` dari Core NFC perlu dicocokkan dengan format registri (`e004…`) lewat uji H.
  - **Universal Link:** entitlement Associated Domains dan berkas AASA menunggu domain produksi. Sampai itu, tautan undangan ditempel ke field.
  - **Pembatasan laju:** `GET /v1/sites/lookup` belum dibatasi laju (diserahkan ke infrastruktur). Kode 40 bit tidak praktis ditebak.
  - **Sisa instal ulang:** item Keychain dari instalasi lama (kunci kredensial, token status) tidak dibersihkan.
- **Test flaky:** `BLETapTests.autentikasiBatalMembatalkanPemindaian` sesekali gagal (pembatalan pemindaian bergantung waktu); lulus 6/6 saat diulang.
- **Riwayat tap:** judul baris "Ditolak · alasan" dirakit di kode (M8; dikerjakan saat bahasa ketiga ditambahkan); VoiceOver baris Status belum diperiksa dengan Accessibility Inspector.
