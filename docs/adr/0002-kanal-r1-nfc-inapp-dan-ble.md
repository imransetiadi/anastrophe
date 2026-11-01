# ADR-0002: Kanal kredensial R1: NFC in-app + BLE; Apple Wallet di R2

- **Status:** Diterima
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** O-A08, O-A01, O-W12–O-W18, O-B01, PRD §5

## Konteks

Tiga kanal resmi tersedia (W/N/B) dengan syarat dan cakupan wilayah berbeda. Indonesia tidak eligible untuk NFC in-app (E13), dan Apple Pay belum tersedia di Indonesia (O-P02).

## Keputusan

R1 merilis **kanal N** (N-SE di wilayah eligible, N-HCE di EEA) **dan kanal B** sebagai fallback universal, satu-satunya kanal di Indonesia. Kanal W (Apple Wallet) dikejar paralel untuk R2.

## Konsekuensi

Dibutuhkan abstraksi `CredentialChannel` di app dan backend yang agnostik kanal. Reader pilot harus mendukung ANP/1 lewat NFC dan BLE (ADR-0016).

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** Which credential channels should Release 1 (MVP) of the Anastrophe iPhone access-card app ship?
- **Prioritas yang diberikan:** Ship R1 on schedule for customers of an Indonesia-based company; demonstrate NFC tap on iPhone where legally possible; avoid depending on uncertain third-party approvals for R1; keep the architecture ready to add Apple Wallet later.
- **Hasil:** `nfc_inapp_plus_ble` · confidence **0.89** · escaped: false
- **Biaya:** 3179 token input + 596 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `nfc_inapp_plus_ble` | 0.91 | R1 ships in-app NFC (Secure Element via CredentialSession in eligible territories, HCE in the EEA) plus BLE as the universal fallback (the only channel in Indonesia). Apple Wallet is pursued in parallel for R2. |
| `ble_only` | 0.04 | R1 ships BLE only in all markets; NFC (in-app or Wallet) comes later. |
| `investigate` | 0.02 | _escape hatch_ |
| `none` | 0.02 | _escape hatch_ |
| `ask_user` | 0.01 | _escape hatch_ |
| `nfc_inapp_only` | 0 | R1 ships in-app NFC only, launching only in eligible territories. |
| `wallet_first` | 0 | R1 waits for Apple Wallet Access Program acceptance and ships Apple Wallet access passes (Aliro) first. |

Cek requirement untuk kandidat terpilih:

| # | Requirement | Jawaban JEV |
|---|---|---|
| 0 | The R1 channel set is usable by end users located in Indonesia. | supported |
| 1 | R1 does not depend on acceptance into the Apple Wallet Access Program. | supported |
| 2 | R1 offers NFC tap on iPhone in at least one market. | supported |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
