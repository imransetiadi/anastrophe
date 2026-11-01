# CLAUDE.md — Aturan proyek Anastrophe

## Produk & sumber kebenaran

Anastrophe = aplikasi iOS kartu akses (padanan Samsung Wallet NFC Access Card) dengan tiga kanal: **W** Apple Wallet (Aliro, R2), **N** NFC in-app (N-SE `CredentialSession` / N-HCE `CardSession`), **B** BLE in-app.

| Hal | Sumber |
|---|---|
| Requirement | `docs/PRD.md` (`FR-xx`, `NFR-xx`, `US-xx`) |
| Desain | `docs/SDD.md` |
| Keputusan | `docs/adr/NNNN-slug.md` (format 4 digit, mis. ADR-0003) |
| Pengujian | `docs/QA_SUITE.md` (`TC-<AREA>-NN`, `AT-xx`) |
| Bukti riset | `docs/research/RESEARCH_EVIDENCE.md` (`E`, `O-`, `I-`, `U`) |
| Bahasa domain | `GLOSSARY.md` |
| UI | `docs/design-system/anastrophe/` (MASTER = web/portal; `pages/ios-app.md` = app iOS) |

## Aturan yang tidak boleh dilanggar

1. **Jangan pernah** mengimplementasikan clone UID / MIFARE Classic atau menyalin data kartu fisik (ADR-0001). Kartu fisik hanya bukti kepemilikan saat enrolment.
2. ANP/1 (ADR-0003, SDD §7): ponsel **tidak** mengungkap identitas apa pun sebelum `sig_R` reader group valid. Respons untuk group tak dikenal dan tanda tangan salah harus identik (`6982`). Setiap APDU < 255 B. Jangan pakai AID Aliro di kanal in-app.
3. Jangan buat `CardSession()` sebelum `NFCReaderSession.readingAvailable`, `CardSession.isSupported`, dan `await CardSession.isEligible` bernilai true. Untuk SE, cek `CredentialSession.isEligible`.
4. Presentment assertion hanya saat pengguna aktif memilih kartu, di foreground. Patuhi 15 dtk + cooldown (HCE) dan 2 per 80 dtk (SE).
5. Kunci kredensial in-app: Secure Enclave, `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` + `[.privateKeyUsage, .userPresence]` (ADR-0009). Tidak boleh ikut backup.
6. Identitas kartu fisik mentah dan kontak pengguna tidak boleh disimpan atau di-log. Server hanya menyimpan HMAC per gedung.
7. UI in-app tidak boleh meniru Apple Wallet/Apple Pay. Teks presentasi tanpa istilah "NFC". Tombol Wallet hanya aset resmi.
8. Batas 8 kartu per perangkat ditegakkan di app **dan** server. Minimum iOS 26.0 (ADR-0006).
9. **Secret tidak pernah masuk repo**, termasuk key JEV (ada di config MCP lokal `~/.claude.json`), secret agentmemory, dan kunci Apple. `.claude/settings.local.json` di-ignore.

## Lapisan keputusan: JEV (ADR-0018)

- Keputusan desain terbatas (2–6 opsi) → `jev_decide` dengan bukti dari ledger, prioritas eksplisit, dan ≤ 3 requirement, serta `escalate_on_contradiction: true`.
- Status: confidence ≥ 0,80 **Diterima**; 0,60–0,80 **Provisional** (tinjau di milestone); < 0,60 atau escape (`ask_user`/`investigate`/`none`) → **eskalasi ke pengguna**. Jangan mengajukan ulang keputusan yang sama tanpa bukti baru.
- Catat setiap keputusan sebagai ADR baru di `docs/adr/` dan simpan input/output mentah di `docs/adr/jev-log/`.
- Klaim faktual baru di dokumen → `jev_verify` terhadap bukti. Sebelum menyatakan milestone/tugas selesai → `jev_gate` (klaim + bukti uji).

## Konvensi kerja

- **superpowers:** spesifikasi di `docs/superpowers/specs/YYYY-MM-DD-<topik>-design.md`; rencana di `docs/superpowers/plans/YYYY-MM-DD-<fitur>.md`. Ikuti TDD dan *verification-before-completion*. Buat branch sebelum commit (jangan commit langsung ke `main`). Commit hanya bila diminta.
- **mattpocock-skills:** `domain-modeling` saat istilah/ADR berubah (perbarui `GLOSSARY.md`). `to-tickets` untuk backlog (jalankan `/setup-matt-pocock-skills` sekali). `grill-with-docs` untuk review desain, dengan keputusan diserahkan ke JEV.
- **ui-ux-pro-max:** baca `pages/ios-app.md` sebelum membangun layar iOS. Jangan pakai `--force` pada design system tanpa izin pengguna.
- **Memori:** agentmemory (`memory_save`/`memory_smart_search`) untuk keputusan & konteks penting; claude-mem menangkap sesi otomatis. Jangan simpan secret atau data pribadi ke memori.
- **Dokumen:** setiap perubahan requirement → perbarui traceability QA §14. Jalankan `python3 scripts/docs/check_docs.py .` (wajib 0 masalah) dan render Mermaid sebelum selesai. Klaim platform harus merujuk ID bukti (metode REA: Observation/Inference/Unknown).
- **Kode:** modul Swift berprefix `AN` (`ANCore`, `ANDesignSystem`, `ANCrypto`, `ANProtocol`, `ANNFCEnroll`, `ANChannelNFC`, `ANChannelBLE`, `ANWallet`, `ANNetworking`, `ANStorage`, `ANFeatures`). I/O NFC/BLE/jaringan di balik protokol agar bisa di-mock. Kasus uji bertipe H butuh iPhone fisik + reader.
- **Bahasa:** dokumen dalam Bahasa Indonesia (istilah teknis boleh Inggris); string UI tersedia dalam ID dan EN.

## Skill REA

Ada di `.claude/skills/reverse-engineer-anything/`. Pakai **hanya** untuk target yang sah: build Anastrophe sendiri, atau firmware/SDK vendor mitra dengan izin tertulis. Jangan pakai untuk membongkar Samsung Wallet atau aplikasi pihak ketiga demi menyalin kode/aset atau melewati proteksi.
