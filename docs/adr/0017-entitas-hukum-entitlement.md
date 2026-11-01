# ADR-0017: Entitas hukum untuk entitlement NFC & SE (terbuka)

- **Status:** Diusulkan — butuh keputusan manusia (eskalasi)
- **Tanggal:** 2026-11-01
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** E03, O-A06, O-A08, R2

## Konteks

Entitlement NFC & SE mensyaratkan pengembang *established* di wilayah eligible. Indonesia tidak termasuk. Implikasi biaya, pajak, dan legal belum diketahui tim produk.

## Keputusan

**Belum diputuskan.** JEV memilih *escape hatch* `investigate`, yang berarti fakta kunci belum ada. Butuh masukan legal/finance: entitas Singapura, entitas Malaysia, atau publisher mitra.

## Konsekuensi

Pilot NFC (ADR-0011) bergantung pada keputusan ini. Pilot BLE di Indonesia dapat berjalan tanpa keputusan ini.

## Catatan keputusan JEV

- **Alat:** `jev_decide` (model `jev-1.14.0`), `escalate_on_contradiction: true`
- **Pertanyaan:** How should the Indonesia-based company satisfy the NFC & SE entitlement's 'established in an eligible territory' requirement for the Singapore/Malaysia pilot?
- **Prioritas yang diberikan:** Legal compliance first; minimize cost and time to the Singapore/Malaysia pilot.
- **Hasil:** `investigate` · confidence **0.27** · escaped: true
- **Biaya:** 774 token input + 75 token output

| Kandidat | Probabilitas | Deskripsi |
|---|---|---|
| `investigate` | 0.39 | _escape hatch_ |
| `partner_publisher` | 0.2 | Have an eligible-territory partner publish a white-label app under its own developer account. |
| `singapore_entity` | 0.19 | Establish (or use an existing) Singapore subsidiary as the Apple developer account holder for the NFC & SE entitlement. |
| `ask_user` | 0.19 | _escape hatch_ |
| `malaysia_entity` | 0.02 | Establish (or use an existing) Malaysia subsidiary as the account holder. |
| `none` | 0.01 | _escape hatch_ |

> Bukti yang dikirim ke JEV adalah ringkasan fakta dari `docs/research/RESEARCH_EVIDENCE.md`. Input dan output mentah JEV tersimpan di [`jev-log/`](jev-log/).
