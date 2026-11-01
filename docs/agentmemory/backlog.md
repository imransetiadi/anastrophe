---
type: backlog
project: anastrophe
updated: 2026-11-01
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

## Terbuka

- **Audit:** waktu event bisa mundur sepanjang `seq` (waktu dari pemanggil); peran DB runtime masih pemilik tabel (perlu pemisahan peran di infrastruktur produksi).
- **Hapus kartu:** penghapusan lokal masih *best-effort*; penghapusan yang terputus setelah 204 pulih lewat `CARD-GONE`; `DELETE` membawa body (RFC 9110).
- **Perpanjangan:** celah test (cek kanal dan kunci group di renewer, kredensial non-ACTIVE di backend); slot pekerjaan tunggal tidak terikat ke tap; renewer menulis salinan kartu lama; endpoint `:challenge` tanpa autentikasi bisa memperbesar tabel (dibersihkan per jam) dan membedakan status kredensial; drift dokumen (ADR-0023 "paralel", SDD §8.4.2 App Attest, QA TC-DEV-09).
- **Presentasi:** hitung mundur HCE mulai saat lembar muncul dan angka `coolingDown` tidak berkurang (belum diverifikasi ulang); presentasi tumpang tindih (`heldIntent` dan `connectWaiters`); panjang fragmen BLE memakai panjang tulis `.withResponse`; paritas timing mengasumsikan maksimal 2 kunci per group.
- **Prioritas tinggi, keamanan (review akhir provisioning aman I1):** tanpa autentikasi perangkat, pihak yang tahu id perangkat dan identitas kartu (atau token undangan) bisa mengganti hash rahasia enrolment instance yang belum selesai lalu memprovisikannya. Menunggu keputusan pengguna di ADR-0041 (rekomendasi `first_writer_wins`).
- **Siklus hidup kartu (review akhir rencana siklus hidup):**
  - Pendaftaran ulang kartu fisik bisa membatalkan suspend/revoke (C1): menunggu keputusan pengguna di ADR-0038.
  - Deadlock jarang antara perpanjangan yang memasang hash (kredensial → instance) dan transisi operator (instance → kredensial); retry berhasil (M1).
  - `expires_at` denylist bisa lebih awal bila validitas kebijakan dipendekkan, dan belum ada purge baris kedaluwarsa (M3).
  - Penyegar status menulis ulang seluruh `Card` sehingga bisa tertimpa penulis lain sampai penyegaran berikutnya (M4).
  - Kartu yang dibuat sebelum fitur ini: yang ditangguhkan sebelum perpanjangan tidak pernah mendapat token; `CRED-NOT-RENEWABLE` belum dipetakan ke Ditangguhkan; token disimpan di id challenge bila record tanpa `serverCardID` (M5).
  - Penyegar tetap memeriksa kartu Dicabut, dan batas frekuensinya memakai jam dinding (M6).
  - Test tabel lengkap untuk pemetaan status (M7).
  - Revoke operator hanya mencatat jumlah, sedangkan hapus kartu menulis `credential.revoked` per kredensial (pemicu Site Sync §8.4.3) (M8).
  - Pesan transisi ilegal CLI bisa menyarankan `reject` untuk `PENDING_APPROVAL` (M10).
- **Undangan (review akhir rencana undangan):**
  - Melanjutkan instance ditolak setelah undangan kedaluwarsa, walau instance masih `PROVISIONING` (M2).
  - Waktu respons berbeda per jalur (tak dikenal ±122 µs, terpakai ±183 µs); tidak bisa dieksploitasi tanpa token 256 bit, perlu dicatat di TC-ENR-08 (M3).
  - `UPDATE` saat melanjutkan tanpa penjaga status di `invitation.go` dan `registry.go`, sehingga balapan dengan sapuan per jam bisa memberi 200 untuk instance yang baru `ABANDONED` (M4).
  - `--link-base` tidak divalidasi (https dan garis miring akhir) (M6).
  - CLI tidak mencetak id undangan, dan belum ada pencabutan undangan (bersama FR-51) (M7).
  - Hash idempotency jalur undangan belum diuji (M9).
  - Test kecil: galat tebusan pertama diabaikan, test bocor CLI hanya memeriksa bentuk base64 (M12).
- **Test flaky:** `BLETapTests.autentikasiBatalMembatalkanPemindaian` sesekali gagal (pembatalan pemindaian bergantung waktu); lulus 6/6 saat diulang.
- **Riwayat tap:** judul baris "Ditolak · alasan" dirakit di kode (M8; dikerjakan saat bahasa ketiga ditambahkan); VoiceOver baris Status belum diperiksa dengan Accessibility Inspector.
