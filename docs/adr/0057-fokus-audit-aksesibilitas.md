# ADR-0057: Fokus berikutnya: audit aksesibilitas app (NFR-A01, TC-UX-01–04/09)

- **Status:** Provisional (JEV 0,70; ditinjau M2)
- **Tanggal:** 2026-11-02
- **Pengambil keputusan:** JEV (`jev_decide`, jev-1.14.0) sebagai lapisan keputusan; dikurasi tim produk
- **Rujukan:** NFR-A01, TC-UX-01, TC-UX-02, TC-UX-03, TC-UX-04, TC-UX-09, `docs/design-system/anastrophe/pages/ios-app.md` §3, §7, §9, ADR-0018, ADR-0056

## Konteks

Sesudah ADR-0056 ditutup dan PR #1 di-merge, 96 dari 151 test case P0 di QA belum punya hasil di §11.1. Sebagian besar butuh iPhone fisik, reader, atau lingkungan produksi. Yang bisa dikerjakan di host dan simulator antara lain test case aksesibilitas (TC-UX-01–04 dan TC-UX-09), privasi identitas kartu (TC-PRIV-01), kepatuhan statis (TC-ELG-05, TC-PRIV-04, TC-MGT-09), dan lokalisasi (TC-UX-06).

Aksesibilitas sejauh ini dijaga dengan disiplin di kode:
- tata letak khusus ukuran aksesibilitas;
- elemen VoiceOver yang digabung;
- pengumuman hasil presentasi lewat `AccessibilityNotification.Announcement`.

Namun aksesibilitas belum pernah diaudit secara sistematis. Design system §3 mengklaim semua pasangan token lolos WCAG AA ≥ 4,5:1, dan checklist §9 belum dicentang. Proyek Xcode hanya punya target app, tanpa target UI test.

## Hasil JEV

- **Hasil:** `audit_aksesibilitas` · confidence **0.70** · escaped: false · tanpa requirement *contradicted*
- **Log mentah:** [`jev-log/2026-11-02-round42.input.json`](jev-log/2026-11-02-round42.input.json), [`jev-log/2026-11-02-round42.output.json`](jev-log/2026-11-02-round42.output.json)

| Kandidat | Probabilitas | Catatan requirement |
|---|---|---|
| `audit_aksesibilitas` | 0.74 | ketiganya *supported* |
| `pemeriksa_kepatuhan_statis` | 0.10 | ketiganya *supported* |
| `privasi_identitas_kartu_e2e` | 0.07 | ketiganya *supported* |
| `lokalisasi_id_en` | 0.05 | ketiganya *supported* |

Confidence 0,70 berada di rentang Provisional (ADR-0018). Unit ini tidak menyentuh keputusan semantik keamanan, privasi, atau legal, jadi dikerjakan sekarang dan ditinjau di milestone M2.

## Keputusan

- **Kontras token (TC-UX-03):** test host menghitung rasio kontras WCAG dari nilai token di kode untuk pasangan yang dipakai UI, di mode terang dan gelap. Test yang sama memastikan tabel design system §3 sama dengan kode.
- **Audit otomatis (TC-UX-01, TC-UX-02, TC-UX-04):** target UI test XCUITest baru menjalankan `performAccessibilityAudit` atas layar utama dengan data demo, di mode terang, gelap, dan Dynamic Type AX5. Ukuran target sentuh konten app diperiksa terpisah, minimal 44 × 44 pt.
- **Temuan diperbaiki di kode.** Pengecualian audit hanya boleh sempit (satu jenis audit, satu elemen, satu alasan tertulis), tidak pernah per jenis audit.
- **Checklist §9 (TC-UX-09):** dinilai butir demi butir dengan bukti, termasuk butir yang masih menunggu perangkat atau fitur.
- **Hasil** dicatat di QA §11.1. Pemeriksaan manual dengan VoiceOver di iPhone fisik tetap tertunda dan ditulis demikian.

Desain dan rencananya ada di `docs/superpowers/specs/2026-11-02-audit-aksesibilitas-design.md` dan `docs/superpowers/plans/2026-11-02-audit-aksesibilitas.md`.

## Konsekuensi

- NFR-A01 bisa diperiksa ulang dengan satu perintah `xcodebuild test` di simulator, dan siap dijadikan langkah CI.
- Mode demo DEBUG bertambah beberapa layar (`-ANDemoScreen`) untuk audit dan screenshot; build Release tidak berubah.
- TC-UX-05 (Reduce Motion, P1), TC-UX-06 (lokalisasi), dan TC-ACC-02 (OTP) di luar cakupan unit ini.

## Penutupan unit (2026-11-06)

`jev_gate` penutupan unit dijalankan dua kali (2026-11-06) dan eskalasi kedua kali (composite 0,66 lalu 0,58; 0 klaim `contradicted` — lihat `jev-log/2026-11-06-audit-aksesibilitas-gate.json`), karena harness `AnastropheUITests/AccessibilityAudit.swift` (+829 baris) melebihi batas payload gate, bukan karena temuan cacat. **Pengguna menerima penutupan unit** berdasarkan bukti uji nyata yang sudah tercatat (Swift host 394 test, simulator paket 375 test, UI test audit 37/37 dan 36/37→37/37 di dua perangkat, 2/2 mutasi tertangkap, build Release bersih, `check_docs.py` 0 masalah). Status unit: **Selesai**, VoiceOver manual di iPhone fisik dan CI UI test tetap di backlog.
