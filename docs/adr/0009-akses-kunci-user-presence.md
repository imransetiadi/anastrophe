# ADR-0009: Kontrol akses kunci in-app: `.userPresence`

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** E03, O-W10, FR-44

## Konteks

Platform Apple mengizinkan passcode sebagai fallback biometrik untuk transaksi kontak. `.biometryCurrentSet` membuat kunci hilang saat Face ID didaftarkan ulang.

## Keputusan

Kunci Secure Enclave memakai `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` + `[.privateKeyUsage, .userPresence]`.

## Konsekuensi

Perubahan biometrik tidak membatalkan kredensial. Pencurian dengan passcode diketahui dimitigasi lewat suspend jarak jauh. Mematikan passcode menghapus kunci (FR-44).

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Which Keychain/Secure Enclave access control should protect Anastrophe's in-app credential private keys (HCE and BLE channels)?
- **Prioritas yang diberikan:** Do not lock users out unexpectedly (e.g., after Face ID re-enrollment), match Apple's platform behavior for contactless credentials, still require user authentication per presentment; remote revocation covers the stolen-and-passcode-known case.
- **Hasil:** `user_presence` · confidence **0.93** · escaped: false
- **Biaya:** 1730 token input + 329 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `user_presence` | 0.94 | kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly with [.privateKeyUsage, .userPresence]. |
| `biometry_any` | 0.02 | kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly with [.privateKeyUsage, .biometryAny]. |
| `none` | 0.02 | _escape hatch_ |
| `ask_user` | 0.01 | _escape hatch_ |
| `investigate` | 0.01 | _escape hatch_ |
| `biometry_current_set` | 0 | kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly with [.privateKeyUsage, .biometryCurrentSet]. |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | The credential remains usable after the user re-enrolls Face ID. | supported |
| 1 | Each presentment requires user authentication on the device. | supported |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
