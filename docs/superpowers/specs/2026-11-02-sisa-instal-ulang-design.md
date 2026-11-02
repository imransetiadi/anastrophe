# Bersihkan sisa Keychain saat instal ulang (FR-43 sebagian) — desain

**Status:** fokus dari ADR-0053 (JEV 0,39, tereskalasi; diterapkan karena berisiko rendah dan tanpa semantik keamanan baru). Mode iterasi otomatis; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

Instal ulang menghapus kartu di SwiftData dan membuat ulang device id (ADR-0045). Namun item Keychain service `app.anastrophe` dari instalasi lama tertinggal:

- blob kunci Secure Enclave (`cred.key.*`);
- record kredensial (`cred.record.*`);
- token baca status (`status-token.*`);
- counter.

FR-43 menyatakan instal ulang membuat kredensial N/B tidak dapat dipakai, jadi materi kredensial lama tidak boleh tetap tinggal di perangkat.

## Tujuan

1. **`SecretStore.deleteAll()`:** menghapus semua item service app.
   - Keychain: satu `SecItemDelete` dengan query kelas + service, tanpa account.
   - Keychain kosong bukan galat.
   - Implementasi in-memory dan simulator mengikuti.
2. **`KeychainDeviceIdentityStore.purgeLeftoversIfFreshInstall(hasCards:) throws -> Bool`:**
   - Bila penanda instalasi tidak ada dan `hasCards` false: `deleteAll()`, lalu buat penanda (dikecualikan dari backup), lalu kembalikan true.
   - Bila penanda ada, atau kartu masih ada: tidak melakukan apa-apa dan mengembalikan false. Dengan begitu `deviceID()` tetap berperilaku seperti ADR-0045.
   - Bila penghapusan gagal: galat diteruskan dan penanda tidak dibuat, sehingga dicoba lagi di peluncuran berikutnya.
3. **`AppServices.prepareInstall() async`:**
   - membaca store kartu; bila pembacaan gagal, store dianggap berisi kartu;
   - memanggil pembersihan; galat pembersihan tidak menghentikan app.
   - `AppEnvironment.makeServices()` memanggilnya sesudah `live()` berhasil dan sebelum layanan diberikan ke UI. Karena itu tidak ada balapan dengan alur Tambah Kartu (*keputusan builder*).

## Non-goal

- Status UNREACHABLE di server.
- Transfer perangkat (FR-41).
- Penawaran "pindahkan kartu" sesudah instal ulang.
- Perubahan pada deteksi restore (kunci hilang → "Perlu dipindahkan").

## Anti-goal

- Kunci kartu yang masih ada di store ikut terhapus, misalnya saat pembaruan dari build tanpa penanda atau saat store kartu gagal dibaca.
- Penanda dibuat padahal penghapusan gagal, sehingga sisa tidak pernah dibersihkan.
- Pembersihan berjalan sesudah UI bisa membuat kartu baru.
- Item service atau app lain ikut terhapus.

## Uji

- **Keychain:**
  - `deleteAll` memakai query kelas + service tanpa account;
  - item service lain utuh;
  - kosong bukan galat;
  - galat lain diteruskan.
- **Identitas:**
  - instal ulang tanpa kartu → semua item terhapus, penanda dibuat (dikecualikan dari backup), dan `deviceID()` membuat id baru yang stabil;
  - kartu ada → tidak ada yang terhapus dan penanda tidak dibuat;
  - penanda ada → tidak ada yang terhapus;
  - penghapusan gagal → galat dan penanda tidak dibuat.
- **AppServices:**
  - store kosong → sisa terhapus;
  - kartu ada → utuh;
  - store gagal dibaca → utuh.

## Review Focus

1. Kartu yang masih ada tidak pernah kehilangan kuncinya, termasuk saat store kartu gagal dibaca.
2. Penanda tidak dibuat sebelum penghapusan berhasil.
3. Pembersihan selesai sebelum UI menerima layanan.
4. Query penghapusan hanya mencakup service app.
5. TC-ENR-23 (id baru sesudah instal ulang dan stabil sesudahnya) tetap lulus.

## Diserahkan ke builder

Nama fungsi dan susunan test.
