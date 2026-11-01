# Kebijakan gedung: masa berlaku sertifikat dan kanal per gedung (FR-55 sebagian) — desain

**Status:** fokus dari ADR-0049 (JEV 0,63, Provisional). Pengguna memakai mode iterasi otomatis; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

Operator belum bisa mengatur kebijakan gedung tanpa SQL. Kanal juga masih global, jadi app bisa memasang kredensial Bluetooth untuk gedung yang hanya punya pembaca "Tempel ke pembaca", atau sebaliknya. Iterasi ini memberi operator alat untuk dua butir FR-55 yang sudah punya dasar di sistem: masa berlaku sertifikat (ADR-0010) dan kanal yang diizinkan. Kanal itu ditegakkan server dan dipahami app.

## Tujuan

1. **CLI baca:** `anastrophe-registry policy --site <uuid>` mencetak kebijakan saat ini (masa berlaku, kanal, jumlah zona) tanpa mengubah apa pun.
2. **CLI ubah:** `anastrophe-registry policy --site <uuid> [--cert-validity-days N] [--channels ble,nfcHCE|semua] --operator <pegangan>` mengubah hanya kunci yang diberikan.
   - Kunci lain di `sites.policy`, termasuk zona, dipertahankan.
   - Masa berlaku harus 1–30; kanal hanya `ble` dan/atau `nfcHCE`, dan `semua` menghapus pembatasan.
   - Audit `site.policy_updated` mencatat nilai baru. Nilainya bukan rahasia.
3. **Kanal efektif gedung:** irisan `policy.channels` dengan kanal global `/v1/config`. Tanpa `policy.channels`, kanal efektif = kanal global.
4. **Penegakan server:** provisioning dengan kanal di luar kanal efektif gedung ditolak 400 `ENR-INVALID-CHANNEL`, sama dengan kanal yang dimatikan global.
   - Penolakan ini terjadi sesudah pemeriksaan rahasia enrolment, sehingga tidak membocorkan kebijakan sebelum autentikasi (ADR-0040).
5. **App tahu kanal gedung:**
   - `GET /v1/sites/lookup` dan respons `POST /v1/enrollments` membawa `channels` (kanal efektif gedung).
   - Jalur kartu memeriksa sebelum enrolment: kanal global ∩ kanal gedung ∩ kelayakan perangkat. Tanpa kanal, enrolment tidak dikirim.
   - Sesudah enrolment, app memilih ulang dari `channels` respons, dan ini satu-satunya sumber untuk jalur undangan. Bila tidak ada kanal yang bisa dipakai, kunci lokal dibuang dan app menampilkan "Cara akses yang diizinkan gedung ini belum tersedia di iPhone ini. Hubungi pengelola gedung."
   - Server lama tanpa `channels` diperlakukan sama dengan "semua kanal global".

## Non-goal

- Persetujuan opsional per gedung (FR-17), maks anggota, kecocokan pemegang, interval sinkron reader, dan TRA per zona.
- Mencabut atau tidak memperpanjang kredensial yang kanalnya kemudian dilarang. Kill switch tetap global di `:renew` (ADR-0023).
- Mengubah `/v1/config` menjadi per gedung.

## Anti-goal

- Kebijakan dibocorkan sebelum rahasia enrolment diperiksa.
- CLI yang menimpa zona atau kunci kebijakan lain saat mengubah satu kunci.
- Nilai di luar 1–30 atau kanal tak dikenal yang tersimpan.
- App yang memasang kredensial untuk kanal yang tidak diizinkan gedung.

## Uji

- **Store:**
  - pembaruan sebagian mempertahankan zona;
  - validasi 1–30 dan kanal;
  - audit;
  - kanal efektif muncul di lookup dan enrolment.
- **HTTP:**
  - lookup dan enrolment membawa `channels`;
  - provisioning dengan kanal terlarang → 400 `ENR-INVALID-CHANNEL` sesudah pemeriksaan rahasia (tanpa rahasia tetap 404 `ENR-NOT-FOUND`).
- **CLI:** baca, ubah sebagian, `semua`, argumen salah.
- **Swift:**
  - pemilihan kanal dengan kanal gedung (sebelum dan sesudah enrolment);
  - pesan baru;
  - server lama tanpa `channels`.
- **E2e lab:**
  - gedung `nfcHCE` saja di simulator (tanpa emulasi) → pesan tanpa provisioning;
  - gedung `ble` → kartu aktif.

## Review Focus

1. Pembaruan sebagian tidak menghapus zona atau kunci lain di `sites.policy`.
2. Urutan pemeriksaan provisioning tidak membocorkan kebijakan sebelum autentikasi rahasia.
3. App tidak membuang slot server saat jalur kartu sudah tahu tidak ada kanal yang diizinkan.
4. Kompatibilitas: respons tanpa `channels` (server lama) dan kebijakan tanpa `channels` tetap berfungsi.
5. Masa berlaku dari CLI benar-benar dipakai saat sertifikat diterbitkan dan diperpanjang.

## Diserahkan ke builder

Nama fungsi, format keluaran CLI, dan susunan kata pesan.
