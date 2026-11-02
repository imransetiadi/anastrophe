# Verifier App Attest di backend (NFR-S03, langkah pertama) — desain

**Status:** fokus dari ADR-0052 (JEV 0,60, Provisional). Mode iterasi otomatis; pilihan bertanda *keputusan builder* dibuat penulis desain ini.

## Maksud

NFR-S03 mewajibkan App Attest untuk enrolment, provisioning, dan transfer, dan menjadi gerbang pra-pilot. Attestation nyata belum bisa dibuat karena build bertanda tangan dan iPhone belum tersedia. Verifikasi di server bisa dibangun sekarang dan dibuktikan dengan contoh attestation resmi Apple.

Unit ini membuat mekanisme verifikasi yang benar dan teruji. Penyambungan ke endpoint, penyimpanan kunci, dan kebijakan menyusul di unit berikutnya.

## Tujuan

1. **Paket `backend/internal/appattest`** dengan `Verifier`, dikonfigurasi oleh:
   - App ID (`<TeamID>.<BundleID>`);
   - lingkungan (production/development);
   - pool root, dengan bawaan Apple App Attestation Root CA yang tertanam dan sidik jarinya dipin (E38, O-AA04);
   - jam.
2. **Attestation:** `VerifyAttestation(attestation, clientDataHash, keyID)` menjalankan langkah O-AA01, lalu mengembalikan kunci publik (titik P-256 65 byte), key identifier, receipt, serta kategori validasi dan bundle version bila ada.
   - `clientDataHash` diberikan pemanggil. Protokol Anastrophe kelak memakai `SHA256(challenge)` (O-AA03).
   - Contoh resmi Apple memakai challenge mentah (O-AA05), jadi verifier tidak meng-hash challenge sendiri (*keputusan builder*).
3. **Assertion:** `VerifyAssertion(assertion, clientData, publicKey, previousCounter)` menjalankan langkah O-AA02 dan mengembalikan counter baru serta ekstensi bila ada.
   - Tanda tangan diverifikasi atas digest `SHA256(nonce)` (O-AA06).
   - Counter harus lebih besar dari `previousCounter`.
   - Pemeriksaan challenge di dalam `clientData` menjadi tanggung jawab pemanggil, karena format `clientData` diputuskan di unit penyambungan.
4. **Ekstensi authData** (`apple_validation_category_01`, `apple_bundle_version_01`):
   - Bila ada, ekstensi diurai dan dilaporkan. Bentuk yang salah (kategori bukan 4 byte, versi bukan teks) ditolak.
   - Bila `Config.Categories` tidak kosong, kategori yang ada harus termasuk daftar itu.
   - Ekstensi yang tidak ada diterima (I-17).
5. **Galat seragam:** semua kegagalan membungkus `ErrInvalid`, dengan alasan singkat untuk log. Pemanggil kelak menjawab klien secara seragam.
6. **Masukan rusak tidak membuat panic:**
   - batas ukuran: attestation ≤ 64 KiB, assertion ≤ 4 KiB;
   - decoder CBOR minimal: map berkunci teks/integer, byte/teks string, array, uint/negint; tanpa tag, float, simple value, atau panjang tak tentu; kedalaman ≤ 8; kunci duplikat dan sisa byte ditolak.

## Non-goal

- Endpoint challenge/attest/assert, penyimpanan kunci dan counter di database, dan sisi app (`DCAppAttestService`).
- Validasi receipt dan metrik risiko penipuan (U15).
- macOS (`aclBlob`) dan App Clip.
- Kebijakan endpoint mana yang wajib App Attest, kategori yang diterima di produksi, dan bypass untuk dev/simulator.

## Anti-goal

- Attestation yang diterima tanpa rantai lengkap ke root yang dikonfigurasi, atau root yang bisa dipilih dari isi attestation.
- Counter assertion yang tidak naik tetapi diterima.
- Panic atau alokasi besar karena panjang palsu di CBOR atau authData.
- Data pihak ketiga (E40) di repo. Data itu hanya dipakai untuk riset di scratchpad.
- Alasan kegagalan yang bocor ke klien. Alasan hanya untuk log, dan penyambungan kelak menjawab seragam.

## Desain

- **Konfigurasi:** `Config{AppID, Environment, Roots, Now, Categories}` dan `NewVerifier(Config) (*Verifier, error)`.
  - App ID divalidasi: `^[A-Z0-9]{10}\.[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*$`.
  - `Roots` nil berarti root Apple tertanam; `Now` nil berarti `time.Now`.
- **Root Apple:** berkas PEM di-embed (`go:embed`). Test memastikan SHA-256 DER-nya `1cb9823ba28ba6ad2d33a006941de2ae4f513ef1d4e831b9f7e0fa7b6242c932`.
- **Langkah attestation:**
  1. Ukuran dan CBOR; `fmt` = `apple-appattest`; `attStmt.x5c` berisi ≥ 2 sertifikat DER; `receipt` tidak kosong; `authData` ada.
  2. Rantai: leaf `x5c[0]`, intermediate `x5c[1:]`, root dari pool, waktu dari `Now`, extended key usage apa pun.
  3. Leaf memakai kunci ECDSA P-256.
  4. `nonce = SHA256(authData ‖ clientDataHash)`. Ekstensi OID `1.2.840.113635.100.8.2` berbentuk `SEQUENCE { [1] EXPLICIT OCTET STRING }` dan nilainya harus sama dengan `nonce`.
  5. `SHA256(titik)` = `keyID` (32 byte).
  6. authData diurai menurut I-16, lalu dicek: RP ID = `SHA256(AppID)`; counter 0; `aaguid` sesuai lingkungan; panjang `credentialId` 32 dan nilainya = `keyID`; kunci COSE harus satu item CBOR; sisa byte, bila ada, harus satu peta ekstensi.
- **Langkah assertion:**
  1. Ukuran dan CBOR `{signature, authenticatorData}`. Kunci lain diabaikan (*keputusan builder*: tanda tangan sudah menutup isinya).
  2. authenticatorData ≥ 37 byte, sisanya peta ekstensi opsional; RP ID cocok; counter > `previousCounter`.
  3. `publicKey` adalah titik P-256 tak terkompresi yang valid.
  4. `nonce = SHA256(authenticatorData ‖ SHA256(clientData))`, lalu `ecdsa.VerifyASN1(pub, SHA256(nonce), signature)`.
- **Alasan galat:** `format`, `chain`, `key`, `nonce`, `key_id`, `rp_id`, `counter`, `aaguid`, `credential_id`, `category`, `signature`. Tipe `*Error{Reason}` dengan `Unwrap() == ErrInvalid`.
- **Data uji:** contoh resmi Apple (E36) disimpan di `testdata/` beserta sumber, tanggal ambil, `clientDataHash` (challenge mentah), waktu periksa, dan catatan inkonsistensi (O-AA05). Kasus lain memakai vektor sintetis buatan test (CA uji → intermediate → leaf dengan ekstensi nonce).

## Uji

- **Contoh Apple:**
  - lulus dengan nilai yang diharapkan (key identifier, kategori 1, versi "1");
  - ditolak bila App ID salah, lingkungan development, `keyID` salah, `clientDataHash = SHA256(challenge)`, waktu sesudah kedaluwarsa, pool root uji, satu byte authData diubah, atau intermediate hilang.
- **Attestation sintetis:**
  - lulus pada jalur dasar, development + `appattestdevelop`, dan tanpa ekstensi;
  - ditolak bila counter ≠ 0, `credentialId` lain atau panjangnya bukan 32, receipt kosong, `fmt` salah, kunci leaf P-384, ekstensi nonce hilang atau rusak, kategori di luar daftar, atau tipe ekstensi salah.
- **Assertion sintetis:**
  - lulus pada jalur dasar dan dengan ekstensi;
  - ditolak bila counter ≤ sebelumnya, counter pertama 0, `clientData` lain, App ID lain, tanda tangan atas `nonce` tanpa hash kedua (mengunci O-AA06), kunci publik rusak, atau ukuran melebihi batas.
- **Decoder dan fuzz:** decoder CBOR menolak data terpotong, panjang tak tentu, kedalaman berlebih, kunci duplikat, sisa byte, dan tag. Fuzz `VerifyAttestation`/`VerifyAssertion` tidak pernah panic.

## Review Focus

1. Rantai ke root yang dikonfigurasi benar-benar wajib (intermediate hilang, urutan tertukar, root uji).
2. Masukan rusak tidak membuat panic atau alokasi besar (panjang palsu di CBOR dan authData).
3. Digest assertion dan counter yang selalu naik.
4. Konvensi `clientDataHash` jelas dan tidak ada hash tersembunyi.
5. Ekstensi tidak ada → diterima; ada tetapi rusak → ditolak; kebijakan kategori hanya bila dikonfigurasi.

## Diserahkan ke builder

Nama tipe dan fungsi, susunan berkas, format berkas data uji, dan helper pembuat vektor sintetis.
