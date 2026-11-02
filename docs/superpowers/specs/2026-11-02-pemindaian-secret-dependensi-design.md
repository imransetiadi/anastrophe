# Pemindaian secret dan dependensi (TC-SEC-11) — desain

**Status:** fokus dari ADR-0056 (JEV 0,93, Diterima). Mode iterasi otomatis; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

TC-SEC-11 (P0, NFR-S09) menuntut dua hal: tidak ada secret di repo maupun build, dan tidak ada CVE kritis yang terbuka. Aturan 9 CLAUDE.md (secret tidak pernah masuk repo) selama ini hanya dijaga dengan disiplin.

Unit ini membuat pemeriksaan yang bisa diulang dengan satu perintah, lalu mencatat hasil pertamanya. Pemeriksaan itu juga siap dijadikan langkah CI kelak.

## Tujuan

1. **Konfigurasi `.gitleaks.toml`** di root repo:
   - memperluas aturan bawaan gitleaks (`[extend] useDefault = true`);
   - allowlist sempit, masing-masing dengan alasan:
     - nilai persis `P256.Signing.PrivateKey`, yaitu anotasi tipe Swift yang tertangkap aturan `generic-api-key`;
     - path persis `Packages/Tests/ANCryptoTests/Resources/anp1-v1.json`, yaitu vektor uji ANP/1 deterministik dari `scripts/anp1/gen_vectors.py` (SDD §7).
2. **Pembungkus `scripts/security/scan.py`** (Python stdlib) dengan subperintah:
   - `secrets`: gitleaks `git` atas seluruh riwayat, ditambah `git --staged` atas perubahan yang di-stage. Selalu dengan `--redact`.
   - `build <path>`: produk build `.app`. Setiap berkas di bundle diekstrak string cetaknya (minimal 8 karakter) ke direktori cermin sementara, lalu dipindai dengan gitleaks `dir`. Temuan dilaporkan dengan path relatif bundle (*keputusan builder*: biner Mach-O dan plist biner tidak dibaca gitleaks sebagai teks).
   - `deps`, tiga pemeriksaan:
     - govulncheck dengan versi terpin, dijalankan di `backend/` dengan keluaran JSON;
     - app iOS tetap tanpa paket remote: `Packages/Package.swift` tanpa `.package(`, dan `project.pbxproj` tanpa `XCRemoteSwiftPackageReference`;
     - dependensi Python di `scripts/*/requirements.txt`: versi yang terpasang diperiksa ke OSV (`api.osv.dev`). Yang dikirim hanya nama paket dan versi.
   - Tanpa subperintah, `secrets` dan `deps` dijalankan. `build` ikut dijalankan bila `--build <path>` diberikan.
3. **Kebijakan dan exit code:**
   - Secret apa pun → exit 1.
   - Go: kerentanan dengan jejak panggilan sampai fungsi → exit 1. Temuan tingkat modul atau paket saja → informasi (*keputusan builder*: govulncheck tidak memberi skor keparahan, dan kode yang terpanggil adalah risiko nyata).
   - Swift: paket remote muncul → exit 1, sampai pemindai untuk ekosistem itu ditambahkan.
   - Python: advisori OSV yang mengenai versi terpasang → exit 1. Paket yang tidak terpasang → informasi.
   - Alat tidak ada, jaringan gagal, atau keluaran alat tidak bisa diurai → exit 2 dengan pesan jelas, tidak pernah lulus.
4. **Keluaran tidak pernah mencetak nilai secret.** Laporan hanya memuat aturan, berkas, baris, dan commit (7 karakter).
5. **Hasil pertama** dicatat di QA §11.1 (TC-SEC-11). Perintah masuk README, pendekatannya masuk SDD (keamanan), dan tindak lanjut (CI, hook pre-commit) masuk backlog.

## Non-goal

- CI (repo belum punya) dan pemasangan hook git otomatis. Hook hanya didokumentasikan.
- Audit `.ipa` bertanda tangan (TC-SEC-07), MASVS (TC-SEC-06), pentest (TC-SEC-12), dan SAST.
- Penulisan ulang riwayat git atau rotasi kunci. Bila ada temuan nyata, keputusan itu milik pengguna.

## Anti-goal

- Allowlist per aturan, per ekstensi, atau per direktori luas yang membutakan pemindai.
- Nilai secret tercetak di log, laporan, dokumen, atau memori.
- Pemindaian yang lulus diam-diam saat alat atau jaringan gagal.
- Secret uji literal di repo untuk menguji pemindai. Fixture dirakit saat runtime, agar repo sendiri tetap bersih.

## Desain

- **Test `scripts/security/test_scan.py` (unittest)** memakai repo git sementara:
  - token palsu berpola aturan bawaan (dirakit saat runtime) di commit → terdeteksi; di perubahan yang di-stage → terdeteksi;
  - deklarasi Swift beranotasi tipe `P256.Signing.PrivateKey` → tidak terdeteksi, tetapi string acak yang di-assign ke variabel `api_key` di berkas `.swift` → tetap terdeteksi (allowlist tidak terlalu luas);
  - isi vektor di path allowlist → tidak terdeteksi, tetapi isi yang sama di path lain → terdeteksi;
  - build: berkas biner berisi token palsu → terdeteksi dengan path relatif bundle, dan laporan tidak memuat nilai token;
  - govulncheck:
    - fixture JSON dengan finding yang jejaknya sampai fungsi → exit 1;
    - finding tingkat modul saja → lulus dengan informasi;
    - JSON rusak atau alat gagal → exit 2;
  - Swift: `project.pbxproj` dengan `XCRemoteSwiftPackageReference` → exit 1;
  - OSV: respons dengan vuln → exit 1; respons kosong → lulus; jaringan gagal → exit 2. Fungsi HTTP diinjeksi, jadi test tidak menyentuh jaringan.
- **Versi alat:**
  - gitleaks minimal 8.30, diperiksa lewat `gitleaks version`;
  - govulncheck dipin di skrip ke versi yang tersedia saat implementasi (`golang.org/x/vuln/cmd/govulncheck@<versi>`).
- **Run nyata:** riwayat, perubahan yang di-stage, build Release simulator yang segar dari HEAD, dan dependensi.

## Uji

- unittest hijau.
- Mutasi yang tertangkap: allowlist dilebarkan, `--redact` dihapus, temuan Go yang terpanggil dianggap informasi, exit 2 menjadi 0, dan ekstraksi string biner dimatikan.
- Hasil run nyata dicatat di QA §11.1.

## Review Focus

1. Allowlist sempit: tidak menyembunyikan secret nyata di kode Swift atau JSON lain.
2. Tidak ada jalur yang mencetak nilai secret, termasuk saat gitleaks atau parser gagal.
3. Kegagalan alat atau jaringan tidak pernah lulus diam-diam.
4. Kebijakan govulncheck: temuan yang terpanggil gagal, dan parser tahan terhadap aliran JSON beberapa objek.
5. Pemindaian build mencakup biner (lewat string) dan berkas teks di dalam bundle.

## Diserahkan ke builder

Nama fungsi, susunan berkas, format laporan, dan panjang minimum string biner.
