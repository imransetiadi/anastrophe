# ADR-0003: Protokol kanal in-app: ANP/1 (proprietary, prinsip setara Aliro)

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** O-L04, O-L05, O-A02, I-10, SDD §7

## Konteks

Kanal N dan B membutuhkan protokol reader. AID Aliro dipakai applet Wallet; UID iPhone acak; kanal in-app harus mendaftarkan AID-nya sendiri.

## Keputusan

Gunakan **ANP/1**: AID proprietary `F0414E415354524F01`, ECDH P-256 ephemeral, reader diautentikasi dengan kunci *reader group* sebelum ponsel mengungkap identitas, tanda tangan ECDSA atas transcript, enkripsi AES-GCM. Pembingkaian identik untuk NFC (APDU < 255 B) dan BLE (GATT).

## Konsekuensi

Reader/gateway harus mengimplementasikan ANP/1, sehingga kita perlu reader referensi (ADR-0016). Dibutuhkan test vector protokol dan review kriptografi eksternal.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Which reader protocol should the in-app NFC and BLE channels of Anastrophe use?
- **Prioritas yang diberikan:** Strong security (no static identifiers, anti-replay, privacy against rogue readers), no third-party licensing dependency for R1, the same protocol over NFC APDUs and BLE GATT, small messages (each APDU under 255 bytes).
- **Hasil:** `anp1_proprietary` · confidence **0.93** · escaped: false
- **Biaya:** 3006 token input + 599 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `anp1_proprietary` | 0.94 | Anastrophe Protocol v1: own proprietary AID, ephemeral ECDH P-256 key agreement, reader authenticated by a reader-group key before the phone reveals any identity, phone signs the transcript with an ECDSA key in Secure Enclave or the SE applet, AES-GCM session encryption; framed identically over BLE. |
| `aliro_inapp` | 0.03 | Implement the Aliro user-device protocol inside the app/applet, reusing the Aliro AID A000000909ACCE5501. |
| `investigate` | 0.02 | _escape hatch_ |
| `none` | 0.01 | _escape hatch_ |
| `hid_seos_license` | 0 | License HID Seos and use HID's mobile SDK and readers. |
| `static_id` | 0 | Present a static credential identifier that the reader looks up. |
| `ask_user` | 0 | _escape hatch_ |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | Does not reuse an AID that belongs to another standard or wallet. | supported |
| 1 | Does not rely on a static identifier for authentication. | supported |
| 2 | Works over both NFC APDUs and BLE GATT without licensing a third party. | supported |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
