# Memory — catatan perubahan Anastrophe

Log kronologis setiap perubahan di repo ini, entri terbaru di atas. Catatan per sesi, keputusan, dan pelajaran yang saling bertaut ada di vault Obsidian [`docs/agentmemory/`](docs/agentmemory/MOC.md).

**Aturan pencatatan**

- Setiap unit kerja (rencana, perbaikan hasil review, keputusan JEV/ADR, perubahan dokumen) menambah satu entri di atas, dalam commit terakhir unit itu, dengan daftar semua commit-nya. Judul: `## AREA-YYYY-MM-DD-HHMM - Judul (Status)`.
- Isi entri: apa yang berubah dan mengapa, rujukan (FR/NFR/ADR/TC), hasil uji yang benar-benar dijalankan, dan catatan sesi Obsidian terkait. Catatan sesi dan [MOC](docs/agentmemory/MOC.md) diperbarui di commit yang sama.
- **Jangan** menulis secret, kunci, token, kontak pengguna, atau identitas kartu fisik (CLAUDE.md aturan 6 dan 9).
- Sumber kebenaran tetap `docs/` dan riwayat git; berkas ini ringkasannya.

## Status terkini

- Branch kerja: `feat/r1-scaffold`, di-push ke GitHub private `imransetiadi/anastrophe` (origin) atas permintaan pengguna; belum di-merge.
- Suite terakhir: Swift host 354 test (1 dilewati, tanpa gagal), simulator 352 test (1 dilewati; flaky BLE yang dikenal sesekali gagal lalu lulus saat diulang), backend Go 10 paket lulus dengan PostgreSQL.
- Menunggu keputusan pengguna:
  - ADR-0017 (entitas hukum untuk entitlement) dan ADR-0022 (bentuk reader uji BLE).
  - ADR-0038: cara mencegah pemegang kartu membatalkan suspend/revoke operator; rekomendasi `hold_pending_approval`, JEV 0,45.
  - ADR-0041: pengambilalihan enrolment yang belum selesai lewat id perangkat + identitas kartu; rekomendasi `first_writer_wins`, JEV 0,44.
  - ADR-0046: kontrol enumerasi identitas kartu lewat enrolment, yang menjadi **gerbang pra-pilot** bersama App Attest; rekomendasi deteksi per gedung + pembatas per perangkat yang di-attest, JEV 0,49.
  - ADR-0047: kedaluwarsa permintaan `PENDING_APPROVAL` (batas 4 per kartu sudah diterapkan), JEV 0,51.

  - Tinjauan 15 gate JEV (13 tereskalasi, 2 review): lab, perpanjangan, audit, hapus kartu, riwayat tap, minor riwayat tap, registri kartu, undangan, siklus hidup kartu, provisioning aman, perbaikan minor, alur Tambah Kartu, layar Bantuan, kebijakan gedung, filter daftar kartu (`docs/adr/jev-log/*-gate.json`).
  - Integrasi branch: merge ke `main` atau PR (branch sudah di-push).
  - `DEVELOPMENT_TEAM` di `Config/Local.xcconfig`, serta iPhone dan reader untuk uji bertipe H.

### Ringkasan kemampuan

| Area | Isi | Rujukan |
|---|---|---|
| App iOS R1 | ANP/1, kanal N-HCE dan B, penyimpanan SwiftData/Keychain, UI Daftar Kunci, detail, dan lembar presentasi | ADR-0002, ADR-0003, ADR-0009 |
| BLE | Pindai paralel saat lembar dibuka, dengan early exit | ADR-0019 |
| Backend | Go + PostgreSQL: enrolment, provisioning, idempotensi, problem RFC 9457 | ADR-0020, ADR-0021 |
| Perpanjangan | Sertifikat diperpanjang memakai autentikasi tap; kill switch hanya di `:renew` | ADR-0023 |
| Audit | Rantai hash per gedung, append-only, pseudonim sejak ditulis, perintah `anastrophe-audit` | ADR-0024, ADR-0025 |
| Hapus kartu | Bukti kepemilikan, kartu ditangguhkan, kartu tanpa kunci | ADR-0026, ADR-0027, ADR-0028, FR-31 |
| Riwayat tap | Log lokal 30 hari: lima terbaru di detail, "Lihat semua" ke riwayat penuh, store pulih sendiri bila rusak | FR-30, ADR-0029, ADR-0030 |
| Registri kartu | Enrolment hanya untuk kartu terdaftar (HMAC per gedung), alasan FR-13, perangkat tambahan menunggu operator, enrolment yang belum selesai dilanjutkan, CLI `anastrophe-registry` | FR-11, FR-13, FR-52, ADR-0031, ADR-0032, ADR-0034 |
| Undangan | Token sekali pakai (32 byte acak, hanya hash yang disimpan), CLI `invite` dengan identitas kartu dari berkas atau stdin, enrolment `{device_id, invitation}`, dan undangan berkartu yang menyetujui enrolment perangkat yang masih menunggu; app mengurai tautan `/i/<token>` | FR-12, FR-53, ADR-0033, ADR-0035 |
| Siklus hidup kartu | Operator: `list` (filter status, kanal, awalan id), `suspend`, `resume`, `revoke` (audit, denylist); app membaca status kartu dengan token baca status tanpa Face ID/passcode. Keterbatasan terbuka: pendaftaran ulang kartu fisik bisa membatalkan suspend/revoke (ADR-0038) | FR-38, FR-50 (sebagian), FR-51, ADR-0036, ADR-0037, ADR-0038 |
| Provisioning aman | Rahasia enrolment dari app (hanya hash di server) wajib untuk kredensial pertama; tambah kanal ke kartu aktif ditolak. Risiko sisa: id perangkat + identitas kartu bisa mengambil alih enrolment yang belum selesai (ADR-0041) | FR-16, ADR-0039, ADR-0040, ADR-0041 |
| Ketahanan | Update dijaga status, urutan kunci instance → kredensial, denylist dari sertifikat terpanjang + purge, pembaruan kartu atomik, jam monotonik yang ikut berjalan saat tidur | ADR-0042 |
| Tambah Kartu | Alur produksi di semua build: kode gedung + tempel kartu (pembaca identifier saja) atau tautan undangan, kanal otomatis, perangkat dibuat saat enrolment, batas 4 permintaan menunggu per kartu. Gerbang pra-pilot terbuka: App Attest + kontrol enumerasi kartu (ADR-0046) | FR-05, FR-10–FR-13, ADR-0043–ADR-0047 |
| Bantuan | Tombol Bantuan di tab Kunci: FAQ sepuluh topik (ID/EN), status cara akses di iPhone ini, iPhone yang didukung, laporan diagnostik tanpa rahasia | FR-60, FR-02, FR-27, FR-63, ADR-0048 |
| Kebijakan gedung | CLI `policy` untuk masa berlaku sertifikat dan kanal per gedung; kanal efektif gedung di lookup/enrolment dan ditegakkan saat provisioning; app memilih kanal yang diizinkan | FR-55 (sebagian), FR-05, ADR-0049 |

## API-2026-11-02-0613 - Filter kanal dan pencarian daftar kartu (Selesai, commit lokal; gate review)

Fokus dari ADR-0050 (JEV 1,0). `anastrophe-registry list` kini punya `--channel ble|nfcHCE` (kredensial ACTIVE/SUSPENDED) dan `--id <awalan id card instance>`, digabung AND dengan `--status`.

Rincian:
- Awalan id divalidasi lalu dibandingkan dengan `left()`, sehingga tanpa pola `LIKE` dari masukan.
- Keluaran tanpa identitas kartu atau kontak.
- FR-50 masih sebagian: pencarian nama atau nomor kartu menunggu portal dan akun.

Review akhir (opus) memberi verdict "With fixes". Dua celah test (kartu SUSPENDED dan AND dengan status) ditutup oleh `TestFilterDaftarStatusSuspendedDanAND`, yang terbukti menangkap dua mutasi yang lolos sebelumnya. Minor lain di backlog.

Bukti: Go 10 paket lulus; `check_docs` 0 masalah. `jev_gate`: review (composite 0,86).

Commit unit ini: `15efce0`, `e308e21`, `4651dbe`, `02daca4`, dan commit ini. Obsidian: `sessions/2026-11-02-filter-daftar-kartu.md`, `decisions/ADR-0050…`, `backlog.md`, dan MOC. Belum di-push sejak `1f87775`.

## API-2026-11-02-0559 - Kebijakan gedung: masa berlaku dan kanal per gedung (Selesai, commit lokal; gate review)

Fokus dari ADR-0049 (JEV 0,63, Provisional). Ini irisan FR-55 yang bisa dibangun sekarang; persetujuan opsional (FR-17) dan perpanjangan tidak disentuh.

Isi pekerjaan:
- **CLI `anastrophe-registry policy`:** baca/ubah masa berlaku (1–30 hari) dan kanal (`ble`, `nfcHCE`, `semua`), audit, dan peringatan bila tidak ada kanal efektif.
- **Store:** pembaruan JSONB di SQL (`zones_bitmap` 64-bit aman), dan pembacaan aman untuk nilai yang bukan array.
- **Kanal efektif gedung:** dikirim di lookup kode gedung dan respons enrolment. Provisioning menolak kanal terlarang hanya sesudah rahasia enrolment diperiksa.
- **App:** pemeriksaan sebelum enrolment (jalur kartu), pemilihan ulang sesudah enrolment, pesan netral bila penyebabnya bukan iPhone, dan "Coba lagi" yang mencari ulang kode gedung.

Review akhir (opus) memberi verdict "With fixes":
- `policy.channels` bukan array → 500, diperbaiki;
- Minor 1–3 dinaikkan dan diperbaiki;
- test masa berlaku lewat `UpdateSitePolicy` ditambahkan;
- sisa minor di [backlog](docs/agentmemory/backlog.md).

Bukti:
- Go 10 paket lulus; Swift host 354 test, simulator 352 test.
- Mutasi tertangkap.
- E2e lab: `nfcHCE` saja → pesan tanpa card instance; `semua` → kartu `ble` aktif 3,0 hari.
- `check_docs` 0 masalah.

`jev_gate`: review (composite 0,79, `test_gap`).

Commit unit ini: `c34516a`, `3dd7289`, `07509f5`, `8c99c8f`, `bb6c899`, `f0b2a95`, `bd4b0fa`, dan commit ini. Obsidian: `sessions/2026-11-02-kebijakan-gedung.md`, `decisions/ADR-0049…`, `backlog.md`, dan MOC. Belum di-push sejak `1f87775`.

## APP-2026-11-02-0518 - Layar Bantuan dan FAQ in-app (Selesai, commit lokal; gate tereskalasi)

Fokus dari ADR-0048 (JEV 0,99). Setelah alur Tambah Kartu ada, FAQ menjadi P0 murni app berikutnya yang tidak terblokir: FR-60, FR-02, FR-27, ditambah FR-63 (P1).

Isi pekerjaan:
- **Pintu masuk:** tombol "Bantuan" di tab Kunci untuk semua build.
- **`HelpTopic`:** sepuluh topik FAQ ID/EN sesuai perilaku R1:
  - perpanjangan saat kartu dipakai dengan internet;
  - hapus kartu di iPhone lama sebelum menambah di iPhone baru;
  - perangkat tambahan perlu persetujuan;
  - layar terkunci butuh buka app + Face ID;
  - tanpa menjanjikan fitur yang belum ada.
- **Status cara akses** di iPhone ini; build tanpa emulasi tidak menyalahkan iPhone atau wilayah.
- **iPhone yang didukung.**
- **`DiagnosticsReport`** lewat `ShareLink`:
  - tanpa id, token, nama kartu, zona, atau host layanan;
  - penyimpanan gagal → "kartu: tidak terbaca".

Review akhir (opus) memberi verdict "With fixes"; 3 Important diperbaiki:
- jawaban offline;
- laporan saat penyimpanan gagal;
- panduan ganti iPhone.

Minor 6 dinaikkan dan diperbaiki. Sisa minor di [backlog](docs/agentmemory/backlog.md).

Bukti:
- Swift host 345 test, simulator 343 test; build Debug dan Release sukses.
- Screenshot ID/EN/AX5.
- Mutasi tertangkap.
- `jev_verify` 5/5 klaim platform FAQ.
- `check_docs` 0 masalah.

`jev_gate` tereskalasi (composite 0,83, `safe_to_apply` 0,73).

Commit unit ini: `84ebff0`, `d1a15e6`, `6915b5b`, `aa5af43`, `dd94518`, `d479f9d`, dan commit ini. Obsidian: `sessions/2026-11-02-bantuan-faq.md`, `decisions/ADR-0048…`, `backlog.md`, dan MOC. Belum di-push sejak `1f87775`.

## APP-2026-11-02-0445 - Alur Tambah Kartu produksi (Selesai, commit lokal; gate tereskalasi; gerbang pra-pilot terbuka)

Fokus dari ADR-0043 (JEV 0,98): build Release belum punya cara menambah kartu, karena tombolnya hanya di DEBUG dan membuka Lab. Keputusan pendukung:
- kode gedung untuk jalur kartu fisik (ADR-0044, 0,96);
- baris perangkat dibuat di transaksi enrolment (ADR-0045, 0,77 Provisional).

Isi pekerjaan:
- **Backend:**
  - migrasi 0013 `sites.join_code`;
  - `GET /v1/sites/lookup` (404 `SITE-NOT-FOUND` identik, `no-store`);
  - CLI `site-code` dan `join_code` di devseed;
  - `ensureDevice` di transaksi enrolment kartu dan undangan.
- **App:**
  - `SiteJoinCode`, `lookupSite`, dan `KeychainDeviceIdentityStore` (dibuat ulang setelah instal ulang);
  - `BackendConfiguration` (Info.plist `ANAPIBaseURL`, https);
  - `CardProvisioner` produksi (kanal otomatis N-HCE > B, tanpa enrolment bila tidak ada kanal);
  - pembaca Core NFC yang hanya membaca identifier, sesudah `connect`;
  - `AddCardModel`/`AddCardView`, tombol "Tambah kartu akses" di semua build, dan `onOpenURL` yang hanya mengisi field;
  - teks ID/EN.
- **E2e:** argumen lab `-ANAPIBaseURL`, `-ANLabCardReader`, `-ANLabAddCode`, `-ANLabOpenURL`.

Review akhir (opus) memberi verdict "With fixes": 0 Critical, 3 Important.

- **Diperbaiki:**
  - #2 banjir permintaan menunggu: batas 4 per kartu (`ENR-PENDING-LIMIT`, ADR-0047, tereskalasi 0,51; diterapkan sebagai inti bersama dua kandidat teratas);
  - #3 identifier setelah `connect` (tanpa test otomatis; uji H);
  - #7 gedung tanpa registri ditawari undangan (dinaikkan dari minor).
- **#1 oracle tebakan identitas kartu:** dicatat sebagai gerbang pra-pilot (ADR-0046, tereskalasi 0,49). Backend tidak boleh dibuka untuk pilot sebelum App Attest dan kontrol enumerasi ada.
- **Minor lain:** di [backlog](docs/agentmemory/backlog.md).

Bukti:
- Go 10 paket lulus; Swift host 334 test; simulator 332 test (flaky BLE yang dikenal gagal sekali, lulus saat diulang; modul BLE tidak berubah).
- Build Debug dan Release sukses.
- Mutasi tertangkap: aturan Bluetooth, guard ketuk ganda (setelah test diperkuat), batas pending.
- E2e simulator:
  - kode gedung + pembaca palsu → kartu aktif, perangkat 1→2;
  - instal ulang + kartu tak terdaftar → pesan + tawaran undangan, perangkat tetap 2;
  - undangan → kartu aktif, perangkat 3;
  - teks ID dan "Layanan belum tersedia" benar.
- `check_docs` 0 masalah.

`jev_gate` tereskalasi (composite 0,64, `spec_match`); 8/8 klaim terverifikasi.

Commit unit ini: `a34c090`, `c375487`, `c270989`, `ffddcc1`, `bfa90dd`, `fba0e33`, `a0505a3`, `5794516`, `c512bdc`, `9ea64a0`, dan commit ini. Obsidian: `sessions/2026-11-02-alur-tambah-kartu.md`, `decisions/ADR-0043…0045`, `backlog.md`, dan MOC. Belum di-push sejak `1f87775`.

## API-2026-11-02-0207 - Perbaikan minor tertunda dari tiga review terakhir (Selesai, commit lokal; gate tereskalasi)

Fokus dari ADR-0042. JEV mengeskalasi pilihan fokus (0,41); rekomendasi penulis diterapkan atas dasar tujuan iterasi berkelanjutan dan persetujuan umum pengguna, dan pengguna bisa membatalkannya. ADR-0038 dan ADR-0041 tidak disentuh.

Isi pekerjaan:
- **Store:**
  - Update kini dijaga status: hash rahasia hanya untuk instance yang menunggu, dan resume diulang sekali bila sapuan menandai instance `ABANDONED` di tengah transaksi.
  - Perpanjangan mengunci instance sebelum kredensial (dibuktikan dengan test deterministik `NOWAIT`).
  - Revoke operator menulis audit `credential.revoked` per kredensial.
  - Migrasi 0012 `max_not_after`: denylist bertahan sampai sertifikat terpanjang yang pernah diterbitkan habis (`GREATEST`), lalu dibuang sapuan per jam.
- **CLI:** `invite` mencetak id undangan, dan `--link-base` harus tepat `https://<domain>/i/`.
- **Test:** idempotency rahasia, hash, dan token undangan; alur persetujuan operator lewat HTTP; peta rahasia fixture dijaga mutex.
- **App:**
  - `CardStore.update(id:mutate:)` atomik dan dipakai penyegar status.
  - Penyegar melewati kartu Dicabut dan membatasi frekuensi dengan `ContinuousClock`, yang ikut berjalan saat ponsel tidur.
  - Perpanjangan menyimpan `serverCardID` dari challenge.
  - Parameter rahasia enrolment di `APIClient` kini wajib.

Review akhir (opus): 0 Critical, 0 Important; kelima Review Focus terpenuhi. Fix pass:
- `GREATEST` untuk masa berlaku denylist.
- Path `/i/` untuk `--link-base`.
- `ContinuousClock` untuk penyegar (dinaikkan dari minor karena kartu ditangguhkan bisa tetap tampil Aktif setelah ponsel tidur).
- Sinkron SDD dan backlog.
- Minor lain dan deadlock enrolment–sapuan yang sudah ada sebelumnya dicatat di [backlog](docs/agentmemory/backlog.md).

Bukti:
- Go 10 paket lulus; Swift host 288 test, simulator 286 test; `check_docs` 0 masalah.
- RED terlihat untuk setiap perbaikan, dan uji mutasi tertangkap.

`jev_gate` tereskalasi (composite 0,73, `spec_match`); 7 klaim terverifikasi.

Commit unit ini: `77f6149`, `79ad48e`, `543576b`, `8f12f03`, `6bfe802`, `cc31e88`, dan commit ini. Obsidian: `sessions/2026-11-02-perbaikan-minor.md`, `decisions/ADR-0042…`, `backlog.md`, dan MOC. Belum di-push sejak `1f87775`.

## API-2026-11-02-0123 - Provisioning kredensial yang aman (Selesai dengan risiko sisa terbuka, commit lokal; I1 dan gate tereskalasi)

Fokus dari ADR-0039 (JEV 0,92), untuk menutup celah prioritas tinggi dari review siklus hidup: kredensial bisa diterbitkan lewat id instance yang dibocorkan `:challenge`. Mekanisme dari ADR-0040: ronde 24 tereskalasi (0,43), lalu ronde 25 dengan bukti baru (app tidak pernah menambah kanal) menghasilkan 0,83.

Isi pekerjaan:
- **Server (migrasi 0011):** `provisioning_key_hash` (SHA-256 saja) dipasang dalam transaksi enrolment untuk instance yang dikembalikan kepada perangkat. Jalur tanpa Idempotency-Key kini memakai `Store.InTx`.
  - Provisioning wajib `Authorization: Bearer <rahasia>`. Rahasia hilang, rusak, atau salah dijawab 404 `ENR-NOT-FOUND` yang identik dengan id tak dikenal, dan diperiksa sebelum status diungkap.
  - Provisioning hanya untuk `PROVISIONING`; hash dihapus setelah kredensial pertama, dan tambah kanal ke kartu aktif ditolak.
- **App:** `ProvisioningSecret` hanya ada di memori. Hash dikirim saat enrolment (kartu maupun undangan), dan bearer dikirim saat kredensial pertama.
- **Test:** fixture Go kini bertindak sebagai klien yang benar. `allTablesText` mendekode kolom `bytea`, sehingga semua test kebocoran bisa melihat teks yang bocor ke body idempotency.

Review akhir (opus): siap merge setelah perbaikan; 0 Critical.
- **I2 (test kebocoran buta base64/bytea):** diperbaiki dan dibuktikan dengan mutasi: dulu lolos, kini tertangkap.
- **I1 (pengambilalihan instance yang belum selesai lewat id perangkat + identitas kartu):** JEV 0,44, jadi dieskalasi sebagai **ADR-0041**. Rekomendasi: `first_writer_wins`. Dokumen kini menyatakan risiko sisa ini dan backlog membukanya lagi sebagai prioritas tinggi.
- **M3 dan M5:** koreksi dokumen dan komentar. Minor lain ditunda di backlog.

Bukti:
- Go 10 paket lulus; Swift host 284 test, simulator 282 test; `check_docs` 0 masalah.
- Lab simulator: app memprovisikan normal dan hash terhapus. Id instance dari `:challenge` tanpa rahasia maupun dengan rahasia palsu dijawab 404 identik dengan id tak dikenal; jumlah kredensial tetap 1, dan log API tanpa bearer.

`jev_gate` tereskalasi (composite 0,74, `safe_to_apply` 0,36); 7 klaim terverifikasi.

Commit unit ini: `16a61bb`, `61a0d97`, `4f8da9b`, `cf0e73c`, `6edc450`, dan commit ini. Obsidian: `sessions/2026-11-02-provisioning-aman.md`, `decisions/ADR-0039…`, `ADR-0040…`, `ADR-0041…`, `backlog.md`, dan MOC. Belum di-push sejak `1f87775`.

## API-2026-11-02-0044 - Siklus hidup kartu oleh operator dan status kartu di app (Selesai dengan keterbatasan terbuka, commit lokal; C1 dan gate tereskalasi)

Fokus dari ADR-0036 (JEV 0,98). Mekanisme status dari ADR-0037 (JEV 0,96): token baca status yang dibuat app, dan server hanya menyimpan hash-nya.

Isi pekerjaan:
- **Store dan migrasi 0010:** `status_token_hash` dan `denylist_entries`.
  - `SuspendCard`, `ResumeCard`, `RevokeCardInstance`: instance dikunci dan status asal diperiksa; kredensial mengikuti status; audit `card.*`; alasan pencabutan berupa kode.
  - Hapus kartu dan pencabutan operator memakai helper yang sama, jadi keduanya mengisi denylist.
- **HTTP:** `status_token_hash` opsional di provisioning (hanya dipasang bila belum ada) dan di `:renew` (boleh mengganti). `GET /v1/cards/{id}/status` dengan bearer token, dan semua kegagalan dijawab 404 `CARD-NOT-FOUND` yang identik. `:renew` memeriksa status setelah bukti kepemilikan.
- **CLI:** `list`, `suspend`, `resume`, `revoke --reason <kode>`, dengan peringatan ADR-0038 setelah suspend/revoke.
- **App:** token di Keychain `afterFirstUnlockThisDeviceOnly`. `CardStatusRefresher` berjalan saat layar Kunci dimuat dan saat app kembali aktif, paling sering sekali per menit:
  - Ditangguhkan, Aktif, atau Dicabut mengikuti server.
  - "Perlu dipindahkan" tidak ditimpa, dan galat jaringan mempertahankan status.
  - Token yang ditolak server dihapus agar perpanjangan berikutnya memasang token baru.

Review akhir (opus): siap merge setelah perbaikan.
- **C1 (pemegang kartu bisa membatalkan suspend/revoke dengan mendaftar ulang kartu fisik):** JEV 0,45, jadi dieskalasi sebagai **ADR-0038**. Rekomendasi: `hold_pending_approval`. FR-51 belum dinyatakan terpenuhi.
- **Diperbaiki dengan test RED → GREEN:**
  - I1: hash token bisa ditimpa lewat provisioning tanpa autentikasi.
  - I2: ID QA ganda; `check_docs.py` kini mendeteksinya.
  - M2: `:renew` membocorkan penangguhan.

Bukti:
- Go 10 paket lulus, `go vet` bersih.
- Swift host 281 test, simulator 279 test.
- `check_docs` 0 masalah.
- Lab simulator: `suspend` lalu buka ulang app → Suspended; `resume` → Active; `revoke --reason hilang` → Revoked. Kredensial `REVOKED`, satu baris denylist (`expires_at` = `not_after`), audit lengkap, dan log API tanpa token.

`jev_gate` tereskalasi (composite 0,74, `test_gap`); 9 klaim terverifikasi. Celah pra-ada yang ditemukan reviewer: kredensial bisa diterbitkan lewat id instance yang didapat dari `:challenge`. Celah ini tercatat di SDD dan menjadi prioritas tinggi di [backlog](docs/agentmemory/backlog.md).

Commit unit ini: `f1f0611`, `203161e`, `f06f6cc`, `d02e59e`, `2ab4477`, `613c278`, dan commit ini. Obsidian: `sessions/2026-11-02-siklus-hidup-kartu.md`, `decisions/ADR-0036…`, `ADR-0037…`, `ADR-0038…`, `backlog.md`, dan MOC. Belum di-push sejak `1f87775`.

## API-2026-11-01-2348 - Enrolment via undangan dan perbaikan review akhirnya (Selesai, commit lokal; gate tereskalasi)

Fokus dari ADR-0033 (JEV 0,89). Temuan review I1 diputuskan JEV sebagai ADR-0035 (`promote_existing`, 0,94, Diterima).

Isi pekerjaan:
- **Store dan migrasi 0009:** tabel `invitations` (hash SHA-256 token, gedung, kartu opsional, zona, masa berlaku) dan `card_instances.invitation_id`. Pemakaian tunggal dikunci `FOR UPDATE`; undangan dianggap terpakai selama punya instance yang tidak `ABANDONED`.
- **HTTP:** `POST /v1/enrollments` menerima tepat satu dari `card` atau `invitation`. Undangan tak dikenal, kedaluwarsa, terpakai, atau yang kartunya keluar dari registri dijawab identik 404 `ENR-INVITATION-INVALID`. Hash idempotency memakai hash token.
- **CLI `anastrophe-registry invite`:** token dicetak sekali. Identitas kartu dibaca dari `--card-file <berkas>|-`, bukan argumen. `--zones` hanya untuk undangan tanpa kartu. `--contact` ditunda sampai FR-03.
- **App:** `InvitationLink.token(from:)` (`https://<host>/i/<token>`), `createEnrollment(deviceID:invitation:)`, teks ID/EN "Undangan tidak berlaku atau sudah dipakai.", dan argumen lab `-ANLabInvite`.
- **ADR-0035:** perangkat yang masih `PENDING_APPROVAL`/`PROVISIONING` untuk kartu yang sama melanjutkan instance-nya lewat undangan berkartu, dengan audit `enrollment.approved` yang memuat id undangan. Tidak ada instance baru.

Review akhir (opus): siap merge setelah perbaikan; 0 Critical. Diperbaiki dengan test RED → GREEN dan uji mutasi:
- I1 (jalan buntu, ADR-0035)
- I2 (kartu `REMOVED`)
- I3 (identitas kartu dan kontak di argumen CLI, aturan 6)
- I4 (batas 8 kartu tanpa test, aturan 8)
- M1 (token lab berawalan `-`)
- M5 (`--zones` diabaikan diam-diam)
- M8 (audit tanpa id undangan, bagian dari ADR-0035)

Bukti:
- Go `ANASTROPHE_REQUIRE_PG=1 go test ./...` 10 paket lulus, `go vet` bersih.
- Swift host 260 test, simulator 258 test.
- `check_docs` 0 masalah.
- Lab simulator: undangan tanpa kartu fisik → `ACTIVE` dengan 1 kredensial. Token terpakai → teks undangan tak berlaku, dan responsnya identik dengan token acak. Perangkat yang menunggu persetujuan menebus undangan berkartu dari stdin, lalu instance yang sama menjadi `ACTIVE`. Token dan identitas kartu tidak muncul di log API maupun dump database.

`jev_gate` tereskalasi (composite 0,70, `test_gap`); 10 klaim terverifikasi, 2 perlu tinjauan. Minor tertunda (M2, M3, M4, M6, M7, M9, M12) dicatat di [backlog](docs/agentmemory/backlog.md).

Commit unit ini: `792695e`, `8b9da67`, `1334464`, `53195f5`, dan commit ini. Obsidian: `sessions/2026-11-01-undangan.md`, `decisions/ADR-0035…`, `backlog.md`, dan MOC. Belum di-push sejak `1f87775`.

## API-2026-11-01-2257 - Registri kartu fisik dan enrolment berbasis kartu, beserta perbaikan review (Selesai, commit lokal; gate tereskalasi)

Fokus dari ADR-0031 (JEV 0,88), dengan aturan perangkat tambahan ADR-0032 (JEV 0,71, provisional).

Isi pekerjaan:
- **Paket `internal/registry`:** identitas kartu kanonik per teknologi, normalisasi kontak, dan MAC per gedung (HKDF dev; KMS menyusul).
- **Migrasi 0007:** `physical_cards` yang hanya menyimpan HMAC.
- **`POST /v1/enrollments`:** mewajibkan kartu, dengan galat `ENR-NOT-REGISTERED`, `ENR-SITE-UNSUPPORTED`, dan `ENR-DUPLICATE`, serta provisioning `PENDING_APPROVAL` → 409. Hash idempotency memakai HMAC.
- **CLI `anastrophe-registry`:** perintah `import`, `approve`, dan `reject`; devseed mendaftarkan kartu lab.
- **App:** `CardIdentity` dengan deskripsi disamarkan, `EnrollmentStart`, teks FR-13 dalam ID/EN, dan argumen `-ANLabCard`.

Review akhir: "with fixes". Semua perbaikan berikut dikerjakan:
- **C1:** perpanjangan sempat memakai zona kebijakan gedung, bukan zona kartu (*fail-open*). Kini satu helper zona dipakai bersama penerbitan dan perpanjangan.
- **I1 (ADR-0034, JEV 0,81):** perangkat yang sama melanjutkan enrolment yang belum selesai, dan `PROVISIONING` tanpa kredensial menjadi `ABANDONED` setelah 15 menit (migrasi 0008, sapuan per jam).
- **I2:** test kebocoran tidak lagi menggantung.
- **I3:** impor CSV menerima BOM dan membatalkan impor saat tanda kutip rusak.
- **Minor:** perangkat penuh tanpa oracle registri, pemindaian seluruh tabel, normalisasi ID gedung, urutan impor tanpa deadlock, hex tanpa tanda `+`/`-`, `--operator` sebagai pegangan buram, CSV di-ignore, devseed `-new-device` tanpa kunci, serta drift SDD dan GLOSSARY.

Bukti:
- Go 10 paket lulus; host 253 test dan simulator 251 test (1 dilewati).
- Uji mutasi tertangkap untuk kunci baris kartu, penandaan terbengkalai, urutan batas, hash idempotency, dan kebocoran CLI.
- Lab simulator end-to-end dua kali. Yang terakhir: perangkat 2 `PENDING_APPROVAL` → disetujui operator → app diluncurkan ulang → instance yang sama dilanjutkan → `ACTIVE` dengan kredensial; log API tanpa identitas kartu.
- `jev_gate` tereskalasi (composite 0,55). Klaim 1 terlalu luas karena perangkat penuh sengaja menerima `ENR-LIMIT`.

Juga: ADR-0033 (JEV 0,89) memilih fokus berikutnya, enrolment via undangan. Spesifikasi dan rencananya sudah ditulis. Backlog minor diverifikasi ulang terhadap kode: sebagian besar catatan lama ternyata sudah selesai.

Commit unit ini: `8398997`, `d30efd2`, `24eecbd`, `fc22ebd`, `694b34e`, `6b2d943`, `f221d58`, `6d8a3f1`, `2eaa044`, `e6ff15d`, dan commit ini. Obsidian: `sessions/2026-11-01-registri-kartu.md`, `decisions/ADR-0033…`, `decisions/ADR-0034…`, `backlog.md`, dan MOC. Belum di-push sejak `1f87775`.

## IOS-2026-11-01-1902 - Minor riwayat tap selesai: review akhir dan perbaikannya (Selesai, commit lokal; gate tereskalasi)

Review akhir oleh subagent baru atas `947ae3f..97e8216`: siap merge, tanpa Critical/Important, lima minor. Kelimanya dikerjakan:
- **Minor 1, dinaikkan ke Important:** pembersihan entri yatim memakai cuplikan kartu yang basi, sehingga riwayat kartu yang baru ditambahkan selama `load()` bisa terhapus. Kini daftar kartu dibaca ulang tepat sebelum menghapus. Test `kartuBaruSaatMuatTidakKehilanganRiwayat`: RED lalu GREEN.
- **Minor 2:** kontrak `CardStore.all()` (semua kartu atau gagal) dan `removeAll(except:)` ditulis di doc comment, dengan test penjaga `barisKartuTakTerbacaMembuatAllGagal`.
- **Minor 3:** dua test bergerbang diberi batas waktu satu menit. Mutasi membuktikan test gagal setelah 64 detik, bukan menggantung.
- **Minor 4:** baris Status digabung untuk VoiceOver. Baru diverifikasi lewat kode.
- **Minor 5:** test hapus kartu memakai kartu kedua yang benar-benar ada di store.

Suite: host 244 test (1 dilewati), simulator 242 (`TEST SUCCEEDED`). Dokumen: SDD 2.8 (§5.3 pembersihan riwayat) dan QA TC-MGT-01 beserta jumlah test.

`jev_gate`: semua klaim terverifikasi (0 *contradicted*, 0 *unsupported*), tetapi tereskalasi (composite 0,73, safe_to_apply 0,46); masuk daftar tinjauan README sebagai gate keenam.

Commit unit ini: `e6b0544`, `f899544`, `33e1103`, `97e8216`, dan commit ini. Obsidian: `sessions/2026-11-01-minor-riwayat-tap-dan-registri.md` dan MOC. Berikutnya: rencana implementasi registri kartu fisik (ADR-0031/0032).

## DOC-2026-11-01-1856 - ADR-0001 dikembalikan ke keputusan asli (Selesai)

Atas permintaan pengguna, kalimat Keputusan ADR-0001 dikembalikan ke versi aslinya: Anastrophe **tidak** meng-clone UID atau data sektor kartu fisik, dan setiap kartu digital adalah kredensial baru. ADR-0001 kembali konsisten dengan judul dan Konteksnya, CLAUDE.md aturan 1, serta PRD NG1/FR-11, sehingga butir klarifikasinya dihapus dari daftar tunggu. Aturan pencatatan di atas juga diperjelas menjadi per unit kerja, sesuai praktik dan catatan review. Di-push ke GitHub agar remote memuat versi asli. Obsidian: `sessions/2026-11-01-minor-riwayat-tap-dan-registri.md` dan MOC.

## DOC-2026-11-01-1843 - Minor riwayat tap, fokus registri (ADR-0031/0032), draf spesifikasi registri, push ke GitHub (Sebagian; review akhir minor masih berjalan)

Minor riwayat tap (rencana `docs/superpowers/plans/2026-11-01-riwayat-tap-minor.md`) di commit `e6b0544`, `f899544`, `33e1103`, `97e8216`:
- Baris riwayat yang tak terbaca dilewati.
- Entri kartu yang sudah tidak ada dibersihkan saat daftar dimuat, hanya bila kartu berhasil dibaca.
- Daftar kartu tampil sebelum riwayat selesai dimuat.
- `switch` pencatat dibuat exhaustive, dengan test urutan simpan-lalu-teruskan dan test batal di background lewat wrapper.
- Badge status tidak lagi terpotong ("Ac-tive") pada AX5, memakai `AnyLayout` seperti `CardRow`.

Bukti: RED lalu GREEN atau uji mutasi untuk setiap perubahan. Host 242 test (1 dilewati), simulator 240 (`TEST SUCCEEDED`, 1 dilewati). Screenshot AX5 dan ukuran standar sudah diperiksa. M8 diputuskan tidak dikerjakan (ruling di ledger). Review akhir subagent masih berjalan; perbaikannya menyusul di entri berikutnya.

Keputusan JEV:
- ADR-0031 `registry_enrolment_server` (0,88): iterasi berikutnya adalah registri kartu fisik dan pencocokan enrolment di server.
- ADR-0032 `pending_for_additional` (0,71, provisional): sebelum ada akun, perangkat pertama mendapat `PROVISIONING` dan perangkat tambahan `PENDING_APPROVAL` (disetujui lewat CLI operator).

Draf spesifikasi: `docs/superpowers/specs/2026-11-01-registri-kartu-design.md`.

ADR-0001: perubahan dari pengguna, disetujui eksplisit, ikut di-commit. Kalimat Keputusan kini berbunyi "meng-clone UID/data sektor kartu fisik", sehingga bertentangan dengan judul dan Konteks ADR itu, CLAUDE.md aturan 1, serta PRD NG1/FR-11. Hal ini masuk daftar klarifikasi.

Push pertama ke GitHub private `imransetiadi/anastrophe`, branch `feat/r1-scaffold`, atas permintaan pengguna. Seluruh riwayat dipindai lebih dulu: tanpa private key, token, `.p8`/`.p12`/`.env`, maupun `Local.xcconfig`.

Obsidian: `sessions/2026-11-01-minor-riwayat-tap-dan-registri.md`, `decisions/ADR-0031-fokus-registri-enrolment-server.md`, `decisions/ADR-0032-perangkat-tambahan-menunggu-persetujuan.md`, dan MOC.

## IOS-2026-11-01-1820 - Perbaikan review riwayat tap: store pulih sendiri dan "Lihat semua" (Selesai, commit lokal; gate tereskalasi)

Review akhir oleh subagent baru atas `de10af4..284762c` tidak menemukan Critical, tetapi menemukan dua Important. I1: store riwayat yang gagal dibuka membuat seluruh app masuk mode "penyimpanan tidak tersedia". I2: detail hanya menampilkan 20 baris di bawah judul "30 hari". JEV memutuskan ADR-0029 `reset_on_corruption_only` (0,87) dan ADR-0030 `inline_recent_plus_all` (0,95).

`SwiftDataTapHistoryStore.openRecovering(directory:)` tidak pernah gagal. Store dibuat ulang sekali hanya bila berkasnya rusak (galat Cocoa 259) atau skemanya tidak cocok dengan model, yang dibaca dari metadata Core Data. Galat lain memakai riwayat sementara di memori tanpa menghapus berkas. `AppServices.live()` memakai fungsi ini. Detail menampilkan lima tap terbaru dan baris "Lihat semua" (dengan jumlah entri) ke layar riwayat 30 hari penuh. String baru ID/EN `detail.history.see_all`; demo mengisi delapan entri.

Bukti:
- RED kompilasi lalu GREEN untuk `TapHistoryRecoveryTests` (4), `TapHistoryPreviewTests` (2), dan test penjaga `riwayatLebihDariDuaPuluhTetapDimuatSemua`.
- Mutasi `isUnusable` (false dan true) serta batas 20 tertangkap.
- Host 235 test (1 dilewati, tanpa gagal); simulator 233 (`TEST SUCCEEDED`).
- Screenshot mode terang, mode gelap (build sementara batas 2), dan AX5.
- `check_docs.py` 0 masalah.

Dokumen: SDD 2.7 (§5.3). QA TC-MGT-01 diperbarui dan dipindah ke atas TC-MGT-02. Status SDD kini menyebut ADR-0017 dan ADR-0022 sebagai yang menunggu.

`jev_gate` dua run tereskalasi (composite 0,662 lalu 0,6885). Pada run kedua, empat klaim *unsupported* karena log uji hanya dikirim di kolom `tests`. Gate ini masuk daftar tinjauan di README. Minor tertunda M1–M8 dan badge status "Ac-tive" pada AX5 dicatat di ledger.

Obsidian: `sessions/2026-11-01-perbaikan-riwayat-tap.md`, `decisions/ADR-0029-pemulihan-store-riwayat-tap.md`, `decisions/ADR-0030-tampilan-riwayat-tap.md`, `lessons/swiftdata-galat-tersembunyi.md`, `lessons/jev-gate-butir-evidence.md`, dan MOC. Tidak push, tidak merge.

## DOC-2026-11-01-1805 - Memory.md dan vault Obsidian docs/agentmemory (Selesai)

Permintaan pengguna: berkas `Memory.md` untuk menyimpan setiap perubahan, lalu integrasi dengan Obsidian. `Memory.md` di root menjadi log kronologis dengan format entri yang sama seperti proyek lain milik pengguna. Riwayat sebelumnya diisi dari git (tabel di bawah).

Vault Obsidian `docs/agentmemory/` berisi `MOC.md`, `sessions/`, `decisions/`, dan `lessons/`:
- `.obsidian/app.json` di-commit agar tautan baru tetap Markdown relatif, sehingga terbaca di GitHub dan diperiksa `check_docs.py`.
- `workspace*.json`, `cache`, dan `.trash/` di-ignore, begitu pula `/.obsidian/` bila root repo dibuka sebagai vault.
- Vault didaftarkan ke daftar vault Obsidian lokal.

Obsidian: `sessions/2026-11-01-memory-dan-obsidian.md`.

## IOS-2026-11-01-1449 - Riwayat tap lokal 30 hari (FR-30), commit 284762c (Selesai; review: 2 Important)

Store SwiftData terpisah (`taps.store`, proteksi `.complete`, tidak ikut backup). `RecordingLauncher` hanya mencatat hasil diizinkan atau ditolak, tanpa nama reader, lokasi, atau identitas kartu. Riwayat dipangkas setelah 30 hari, dihapus bersama kartu, dan tampil di detail kartu. Suite saat itu: host 228 test (227 lulus, 1 dilewati), simulator 226 (225 lulus, 1 dilewati). Review akhir: tanpa Critical, dua Important (I1, I2), delapan minor. Obsidian: `sessions/2026-11-01-riwayat-tap.md`.

## Riwayat commit sebelum Memory.md

Terbaru di atas; semua di `feat/r1-scaffold`, 2026-11-01.

| Commit | Ringkasan |
|---|---|
| `284762c` | feat(app): riwayat tap lokal 30 hari di detail kartu (FR-30) |
| `de10af4` | docs(jev): gate penutupan rencana hapus kartu (eskalasi) dan daftar gate di README |
| `255656f` | fix(delete): perbaikan review akhir hapus kartu (C1, I1–I4, M2, M5; ADR-0027/0028) |
| `eb2cd45` | docs(adr): ADR-0027 hapus kartu ditangguhkan (0,94) dan ADR-0028 hapus kartu tanpa kunci (1,0) |
| `475ef29` | feat(backend): perintah operator anastrophe-audit untuk verifikasi rantai audit |
| `47e7a7b` | feat(app): hapus kartu — Detail → Pengaturan → Hapus dengan konfirmasi + autentikasi (FR-31) |
| `a56705a` | feat(backend): DELETE /v1/cards/{id} dengan bukti kepemilikan kunci (FR-31, ADR-0026) |
| `f81d27a` | docs: ADR-0026 hapus kartu dengan bukti kepemilikan (JEV 0,98), spesifikasi dan rencana FR-31 |
| `115b0db` | feat(app): peringatan "Perlu terhubung ke internet" untuk kartu yang perlu diperbarui (TC-DEV-10) |
| `127afa7` | fix(renewal): pekerjaan perpanjangan terikat ke tap tertentu (minor review M3) |
| `39087f4` | test(l10n): penjaga katalog string ID/EN dan kunci localized() yang dipakai kode |
| `b2ed49c` | fix(audit): waktu event tidak mundur sepanjang seq (minor review audit 3) |
| `38dcf56` | docs(readme): daftar gate penutupan yang menunggu tinjauan |
| `3e1ed60` | docs(jev): gate penutupan rencana audit (eskalasi, semua klaim verified) |
| `a06ba99` | fix(audit): perbaikan review akhir audit (C1, I1, I2, I3) + ADR-0025 |
| `a77d7c2` | fix(renewal): minor review perpanjangan (M1, M4–M9) |
| `1d93435` | docs(jev): gate penutupan rencana perpanjangan (eskalasi, semua klaim verified) |
| `a5c2cd4` | fix(renewal): perbaikan review akhir perpanjangan (C1 teks, I1, I2, I3) |
| `f9e6cff` | feat(backend): catat audit enrolment, provisioning, dan perpanjangan dalam transaksi yang sama |
| `433704a` | feat(backend): log audit append-only berantai hash per gedung (FR-54, ADR-0024) |
| `25b37c6` | docs(plan): spesifikasi dan rencana audit log berantai hash per gedung (FR-54, ADR-0024) |
| `6c8c498` | docs(adr): ADR-0024 rantai hash audit per gedung (JEV per_site_chain 0,95) |
| `51dfc4b` | docs(glossary): istilah perpanjangan (ADR-0023), reader uji (ADR-0022), dan lab |
| `7f59abb` | fix(app): kartu kedaluwarsa yang bisa diperpanjang tetap bisa di-tap; status "Perlu diperbarui" |
| `61717f6` | fix(lab): minor review lab (M3-nit, M4c, M5, M6, M7) |
| `2c9f986` | fix(ui): separator detail kartu rata dan tombol utama nonaktif terlihat redup |
| `7d66e39` | docs(jev): gate lab run 3 dengan bukti e2e pasca-perbaikan (tetap eskalasi) |
| `00df0d3` | feat(lab): perpanjangan lab (-ANLabRenew, tombol detail) + dokumen ADR-0023, terverifikasi e2e |
| `5577855` | feat(app): perpanjangan sertifikat di alur tap (hook prepare + RenewalScheduler, ADR-0023) |
| `965f922` | feat(app): CredentialRenewer — perpanjangan sertifikat dengan bukti kepemilikan kunci (FR-45) |
| `f663eaf` | feat(app): kontrak perpanjangan sertifikat (RenewalPolicy, not_before, renewalURL, API challenge/renew) |
| `b4f3505` | docs(jev): catat jev_gate penutupan rencana lab (eskalasi, semua klaim verified) |
| `6de92c2` | fix(lab): perbaikan review akhir lab (I1, M1–M4): slot server, moveKey, pemulihan devseed |
| `8716785` | docs(adr): ADR-0022 reader uji BLE (eskalasi) dan ADR-0023 perpanjangan via autentikasi tap |
| `ff2b184` | feat(backend): perpanjangan sertifikat FR-45 (challenge + renew, ADR-0023) |
| `6b4b8be` | feat(lab): pemicu DEBUG -ANLabBackend + form "Backend dev", terverifikasi end-to-end |
| `f71b5f5` | feat(lab): provisioning lab lewat backend dev (moveKey + provisionViaBackend) |
| `20ce1db` | feat(backend): perintah dev anastrophe-devseed untuk lab end-to-end |
| `a8d32fd` | fix(backend): idempotency enrolment tracer, test DB tak lagi dilewati diam-diam (minor 5, 11, 12) |
| `353a655` | fix(backend): migrasi aman antar-replika, zona fail-closed, kebijakan gedung (minor 2, 6, 7) |
| `eb9f747` | docs(adr): ADR-0021 CBOR/COSE minimal (amandemen ADR-0020) |
| `79cc24f` | fix(backend): decoder CBOR & verifier COSE ketat (minor review 3) |
| `260907d` | fix(backend): pengerasan lapisan HTTP (minor review 1, 8, 9, 10, 13) |
| `094a812` | fix(backend): idempotency satu transaksi, cek status kartu, test race deterministik |
| `c9f1ea7` | feat(networking): APIClient.createEnrollment untuk endpoint tracer backend |
| `460fbf1` | feat(backend): provisioning kredensial POST /v1/enrollments/{id}/credentials |
| `a02de72` | feat(backend): skema PostgreSQL R1 dan invarian 8 kartu per perangkat |
| `5154b30` | feat(backend): penerbitan CredentialCert COSE_Sign1 ES256 (SDD §7.3) |
| `d57aab2` | test(backend): kesesuaian test vector ANP/1 v1 di Go (TC-PROTO-01) |
| `bd9d4ba` | feat(backend): pondasi API Go, RFC 9457, dan GET /v1/config |
| `065d097` | docs(adr): ADR-0020 backend Go (provisional) dan topologi diterima di SDD §12 |
| `507fca8` | feat(ble): pindai paralel dengan autentikasi (ADR-0019) |
| `0130f47` | feat(ios): R1 tracer bullet — ANP/1, kanal N-HCE & B, penyimpanan, UI |
| `400719d` | docs: dokumen produk Anastrophe, ADR, design system, dan aturan proyek |
