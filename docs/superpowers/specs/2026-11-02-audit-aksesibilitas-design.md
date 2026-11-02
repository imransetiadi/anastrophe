# Audit aksesibilitas app (NFR-A01, TC-UX-01–04/09) — desain

**Status:** fokus dari ADR-0057 (JEV 0,70, Provisional). Mode iterasi otomatis; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

NFR-A01 (P0) menuntut:
- VoiceOver;
- Dynamic Type hingga AX5;
- kontras WCAG AA dengan token yang terverifikasi di design system;
- target sentuh ≥ 44 pt;
- Reduce Motion.

Test case P0-nya (TC-UX-01–04 dan TC-UX-09) belum punya hasil di QA §11.1.

Kode app sudah memperhatikan aksesibilitas: tata letak khusus ukuran aksesibilitas, elemen VoiceOver yang digabung, dan pengumuman hasil presentasi. Namun belum pernah ada audit yang bisa diulang.

Unit ini membuat audit itu, memperbaiki temuannya, dan mencatat hasilnya. Hasilnya harus jujur: yang belum bisa diuji tanpa iPhone fisik ditulis tertunda.

## Tujuan

1. **Kontras token (TC-UX-03).** Nilai token warna dibuka sebagai data di `ANDesignSystem` (nama, hex terang, hex gelap); `ANColor` tetap API yang dipakai view. Target test host baru `ANDesignSystemTests`:
   - menghitung rasio kontras WCAG 2.x untuk pasangan yang dipakai UI, di mode terang dan gelap. Setiap pasangan harus ≥ 4,5:1:
     - `foreground`, `mutedForeground`, `secondary`, `success`, `warning`, dan `destructive` di atas `background` dan `card`;
     - `onAccent` di atas `accent`;
     - `primary` di atas `background` dan `card`;
   - memastikan tabel `pages/ios-app.md` §3 sama dengan kode: hex setiap token, serta rasio yang tertulis di tabel (dibulatkan satu desimal) sama dengan hasil hitung.
2. **Permukaan baris memakai token.** Baris `List` (daftar kartu, detail, riwayat, Bantuan) memakai `ANColor.card` sebagai latar baris, sehingga semua pasangan teks/permukaan di UI tercakup tabel token. Saat ini di mode gelap baris memakai abu-abu sistem (*keputusan builder*: design system §3 menyebut `card` untuk permukaan kartu/baris).
3. **Target UI test `AnastropheUITests`** (XCUITest) di proyek Xcode, dengan skema bersama `Anastrophe`. Test action-nya menjalankan target ini di simulator, tanpa jaringan dan tanpa backend, memakai data demo DEBUG (`-ANDemo`).
4. **Audit per layar.** Setiap keadaan layar di daftar berikut diaudit dengan `performAccessibilityAudit` (semua jenis audit):
   - mode terang dan gelap dalam satu peluncuran (`XCUIDevice.shared.appearance`, dikembalikan ke terang sesudahnya);
   - ukuran teks AX5 (`UICTContentSizeCategoryAccessibilityXXXL`) dalam bahasa ID dan EN, masing-masing satu peluncuran.

   Keadaan layar:
   1. daftar kartu (empat kartu demo);
   2. daftar kosong;
   3. detail kartu aktif (dengan riwayat dan "Lihat semua");
   4. detail kartu ditangguhkan;
   5. riwayat lengkap;
   6. lembar presentasi yang menunggu reader;
   7. presentasi dengan izin Bluetooth ditolak;
   8. presentasi ditolak (hasil dengan Selesai dan Coba lagi);
   9. Bantuan, dengan satu topik FAQ dibuka;
   10. Tambah Kartu: pilih cara;
   11. Tambah Kartu: kode gedung dengan galat field;
   12. Tambah Kartu: konfirmasi gedung;
   13. Tambah Kartu: tautan undangan;
   14. Tambah Kartu: berhasil;
   15. Tambah Kartu: menunggu persetujuan;
   16. Tambah Kartu: gagal dengan tawaran undangan.
5. **Target sentuh (TC-UX-04)** diperiksa sendiri di setiap keadaan, karena ambang audit `hitRegion` tidak didokumentasikan Apple:
   - **Ukuran:** setiap tombol, tautan, dan field teks yang bisa diketuk berukuran ≥ 44 × 44 pt (toleransi 0,5 pt).
   - **Jarak:** dua elemen konten yang tidak bertumpuk dan tidak bersarang berjarak ≥ 8 pt.
   - Elemen di bilah navigasi dan di dalam sel daftar dikecualikan dari cek jarak (*keputusan builder*: tata letaknya dikelola sistem, dan baris daftar yang bersebelahan dipisah separator).
   - Elemen milik sistem dikecualikan dari cek ukuran dan jarak buatan sendiri (*keputusan builder*, jawaban builder check): bilah navigasi, toolbar, keyboard, dan grabber lembar. Elemen ini tetap diaudit `hitRegion` Apple, dan temuan Apple atasnya hanya boleh dikecualikan per elemen dengan alasan. Test tidak mengetik: isi field demo diatur di kode, jadi keyboard tidak muncul.
6. **Mode demo** (DEBUG saja) mendapat nilai `-ANDemoScreen` baru untuk keadaan di atas. Data demo dan perilaku Release tidak berubah. Layar Tambah Kartu di demo memakai alamat layanan `https://demo.invalid` (TLD cadangan RFC 2606) agar terlihat tersedia tanpa pernah tersambung (*keputusan builder*).
7. **Temuan diperbaiki di kode**, misalnya `frame(minHeight: 44)` yang diletakkan di luar tombol sehingga area ketuk tetap sebesar teks. Perbaikan yang berulang menjadi gaya di `ANDesignSystem`, misalnya gaya tombol sekunder dengan area ketuk 44 pt. Teks baru wajib ID dan EN, tanpa istilah teknis.
8. **Pengecualian audit:**
   - Satu-satunya pengecualian umum adalah kontras elemen nonaktif, yang dikecualikan WCAG 1.4.3.
   - Pengecualian lain hanya per elemen: jenis audit, elemen yang dikenali dengan pasti, dan alasan tertulis di test. Pengecualian per jenis audit dilarang.
   - **Halaman tergulir** (*keputusan builder* sesudah kalibrasi): sesudah digulir, konten melintas di bawah bahan kaca bilah navigasi, sehingga audit membaca teks setengah tertutup.
     - Isu kontras, teks terpotong, dan Dynamic Type pada elemen yang beririsan dengan bilah navigasi/toolbar dilewati. Elemen yang sama diaudit tanpa halangan di halaman sebelumnya.
     - Isu tanpa elemen yang bisa ditunjuk di halaman tergulir tidak menggagalkan test, tetapi dicetak `AUDIT-SKIP` dan jumlahnya dicatat di QA.
     - Di halaman yang belum digulir, semua isu tetap dihitung.
   - **Elemen bilah sistem:** tombol toolbar milik app (dikenali lewat identifier) dikecualikan dari audit Dynamic Type, karena item bilah iOS tidak mengikuti Dynamic Type dan sistem menyediakan Large Content Viewer. Judul dan tombol kembali buatan sistem di bilah navigasi dikecualikan dari audit teks terpotong dan Dynamic Type dengan alasan yang sama. Kontras dan `hitRegion` atas elemen bilah tetap diaudit.
   - Setiap pengecualian dicatat di QA §11.1.
9. **Lint sumber (host)** untuk anti-pola §8:
   - Tidak ada ukuran font tetap: `.system(size:` dan `fixedSize:`. `Font.custom(_:size:)` dan `relativeTo:` tetap boleh, karena keduanya ikut Dynamic Type, dan design system §2 mengizinkan wordmark merek dengan `relativeTo:` (*keputusan builder*, jawaban builder check).
   - Animasi (`withAnimation`, `.animation(`, `.transition(`, `.symbolEffect(`) hanya boleh di berkas yang membaca `accessibilityReduceMotion`.

   Saat ini kode tidak punya keduanya; lint menjaganya tetap begitu.
10. **Hasil** dicatat di QA §11.1 untuk TC-UX-01, -02, -03, -04, dan -09, termasuk jumlah temuan sebelum perbaikan. TC-UX-09 dinilai butir demi butir terhadap checklist §9: lulus, tertunda (butuh perangkat), atau belum berlaku (OTP belum ada, tombol Wallet di R2). README dan SDD mencatat perintah dan pendekatannya.

## Keputusan sesudah bukti audit pertama

Builder check menemukan dua pilihan yang bergantung pada temuan nyata. Keduanya diputuskan lewat JEV (ADR-0018) dengan bukti run RED, lalu dicatat sebagai ADR baru:

1. **Cakupan token.** Sebagian teks masih memakai warna sistem:
   - nilai `LabeledContent`, header dan footer seksi, deskripsi daftar kosong, dan placeholder: abu-abu sistem, ±3,4:1 di atas putih;
   - tombol teks, tautan, dan item toolbar: biru sistem, karena tidak ada aset AccentColor;
   - "Hapus kartu": merah sistem, ±3,5:1.

   Pilihannya:
   - semua teks dan warna interaktif dipindah ke token, dengan tint app `secondary` (tautan/info) atau `primary` (navigasi);
   - atau hanya elemen yang ditandai audit yang diperbaiki, dan klaim TC-UX-03 dipersempit.
2. **Kontras "nyaris lulus".** Audit bisa menandai teks kecil yang pasangan tokennya terbukti ≥ 4,5:1 di test host, karena audit membaca piksel yang di-antialias. Pilihannya:
   - pengecualian per elemen yang merujuk test host;
   - aturan umum kedua yang terbatas pada kategori itu;
   - atau token dianggap gagal dan dieskalasi.

**Diputuskan** (2026-11-02, dengan bukti run RED, inventaris warna sistem iOS 26.5, dan kalibrasi audit):
- **Butir 1:** [ADR-0058](../../adr/0058-cakupan-token-warna-tint-app.md), `token_semua_tint_secondary`, JEV 0,95. Semua teks dan warna interaktif app memakai token; tint app `secondary` ditambah aset AccentColor.
- **Butir 2:** [ADR-0059](../../adr/0059-pengecualian-kontras-per-elemen.md), `pengecualian_per_elemen_bukti`, JEV 0,93. Tanpa aturan kategori; pengecualian kontras hanya per elemen bertoken, dengan bukti test host dan pengukuran piksel.

## Non-goal

- Pemeriksaan manual VoiceOver di iPhone fisik dan Accessibility Inspector (tipe A penuh). Tetap tertunda dan ditulis demikian.
- Layar Lab (DEBUG saja), TC-UX-05 (Reduce Motion, P1) di luar lint, TC-UX-06 (lokalisasi), dan TC-ACC-02 (OTP).
- Desain ulang layar atau perubahan nilai token. Bila ada token yang gagal kontras, perubahan nilainya dieskalasi lewat ADR baru, bukan diubah diam-diam.
- CI. Repo belum punya CI; perintahnya didokumentasikan.

## Anti-goal

- Pengecualian audit yang luas demi test hijau.
- Label VoiceOver yang mengulang teks terlihat secara berlebihan, memuat istilah teknis ("NFC", "HCE", "APDU"), atau berbeda maknanya dari teks terlihat.
- Perubahan perilaku presentasi. Lembar presentasi demo hanya memakai launcher bernaskah, jadi tidak ada presentasi nyata (aturan 4).
- Elemen yang meniru Apple Wallet (aturan 7).

## Desain

- **Token:**
  - `ANColorToken` (nama, `light`, `dark` sebagai `UInt32`) dengan daftar semua token;
  - `ANColor.<token>` dibangun dari daftar itu;
  - rumus luminans relatif dan rasio kontras ada di target test (*keputusan builder*: belum ada pemakai di app).
- **Test token:** Swift Testing di `Packages/Tests/ANDesignSystemTests`. Tabel design system dibaca dari repo lewat `#filePath`, seperti `LocalizationCatalogTests`.
- **UI test:** XCTest (XCUITest). Satu kelas untuk terang/gelap dan satu untuk AX5, keduanya memakai helper bersama:
  - meluncurkan app dengan argumen demo;
  - menunggu elemen penanda keadaan;
  - menjalankan audit dengan handler pengecualian;
  - menjalankan cek target sentuh;
  - melampirkan screenshot.

  Elemen penanda memakai `accessibilityIdentifier`, agar test tidak bergantung pada bahasa (*keputusan builder*: identifier tidak terlihat pengguna dan tidak dibacakan VoiceOver).
- **Perangkat:** iPhone 17e (lebar terkecil yang tersedia) dan iPhone 17 Pro (perangkat di README), iOS 26.5.
- **Urutan kerja (TDD):** audit ditulis dulu dan dijalankan sebelum perbaikan. Temuan awal dicatat sebagai bukti RED, lalu diperbaiki sampai hijau.

## Uji

- Test token dan lint hijau di host. Mutasi yang harus tertangkap:
  - token `mutedForeground` diubah ke nilai yang gagal kontras;
  - hex di tabel dokumen diubah;
  - satu `.font(.system(size: 17))` disisipkan.
- UI test hijau di kedua perangkat. Mutasi yang harus tertangkap:
  - salah satu perbaikan area ketuk dibalik;
  - label tombol ikon dihapus;
  - pengecualian umum diperluas ke semua jenis audit.
- Suite paket host dan simulator tetap hijau.

## Review Focus

1. Pengecualian audit tetap sempit, dan cek target sentuh tidak bisa lulus tanpa elemen (layar kosong atau penanda tidak ditemukan harus gagal).
2. Mode demo baru tidak mengubah build Release dan tidak memulai presentasi nyata.
3. Perbaikan area ketuk benar-benar memperbesar area yang bisa diketuk, bukan hanya bingkai visual.
4. Tabel design system dan kode tidak bisa menyimpang tanpa test gagal.
5. Klaim di QA §11.1 sesuai yang benar-benar diuji; pemeriksaan manual dan perangkat tetap tertunda.

## Diserahkan ke builder

Nama berkas dan fungsi, susunan helper UI test, identifier, nama nilai `-ANDemoScreen`, dan cara memperbaiki setiap temuan, selama mengikuti design system.
