# Override Design System — Aplikasi iOS Anastrophe (SwiftUI)

> **Override terhadap [`../MASTER.md`](../MASTER.md)** sesuai pola Master + Overrides skill `ui-ux-pro-max`. File ini menimpa aturan MASTER untuk **aplikasi iOS**.
> MASTER (CSS/web) tetap berlaku untuk **portal admin web**. Pola halaman "Trust & Authority + Conversion" di MASTER hanya untuk situs pemasaran, tidak untuk konsol admin.
> Sumber: `ui-ux-pro-max` (`--design-system "security access control digital key mobile app"`, dial variance 3 / motion 3 / density 5), pencarian `--domain ux` (accessible authentication, loading feedback, touch target) dan `--stack swiftui` (Dynamic Type, semantic views). Semua rekomendasi disesuaikan dengan Apple HIG dan pedoman NFC & SE (O-A10).

## 1. Prinsip

1. **Tenang & tepercaya.** Gaya *Minimalism & Swiss*: bersih, kontras tinggi, hierarki tipografi jelas, tanpa ornamen.
2. **Satu tindakan utama per layar.** Contoh: "Gunakan kartu", "Tambah kartu".
3. **Keamanan terlihat, tetapi tidak menakutkan.** Status kartu dan alasan kegagalan selalu disertai langkah lanjut.
4. **Bukan tiruan Wallet.** UI in-app **tidak boleh** meniru tampilan pass Apple Wallet, tanda centang Apple Pay, atau ikon/merek Apple (O-A10). Kartu ditampilkan sebagai baris daftar/kartu datar, bukan tumpukan pass bergaya Wallet.

## 2. Tipografi (override MASTER)

| Peran | iOS | Catatan |
|---|---|---|
| Body, label, angka | **SF Pro (font sistem)** via text style (`.body`, `.headline`, `.caption`) | Wajib Dynamic Type (`.font(.body)`, bukan `.font(.system(size: 16))`). Mendukung aksara Latin/Tionghoa. |
| Wordmark/judul brand (opsional) | IBM Plex Sans via `Font.custom("IBMPlexSans-SemiBold", size:, relativeTo: .title)` | Hanya untuk judul brand; tetap ikut skala Dynamic Type. |
| Angka security code | `.monospacedDigit()` | Agar digit tidak bergeser. |

Uji hingga ukuran aksesibilitas terbesar (AX5) tanpa teks terpotong (NFR-A01).

## 3. Warna (token → Asset Catalog, light/dark)

Semua pasangan di bawah sudah dihitung dan lolos **WCAG AA ≥ 4,5:1**. Rasio dihitung terhadap `background`, kecuali `onAccent` yang dihitung terhadap `accent`. Nilai dan rasio tabel ini diuji terhadap kode oleh `ANDesignSystemTests` (TC-UX-03), termasuk teks di atas `card`.

| Token | Light | Dark | Pemakaian |
|---|---|---|---|
| `background` | `#F8FAFC` | `#020617` | Latar layar |
| `foreground` | `#020617` | `#F8FAFC` | Teks utama (19,3:1) |
| `card` | `#FFFFFF` | `#0F172A` | Permukaan kartu/baris |
| `mutedForeground` | `#475569` | `#94A3B8` | Teks sekunder (7,2:1 / 7,9:1) |
| `primary` | `#0F172A` | `#E2E8F0` | Navigasi, ikon utama |
| `secondary` | `#1E3A8A` | `#93C5FD` | Tautan, info (9,9:1 / 11,2:1) |
| `accent` (CTA) | `#A16207` | `#EAB308` | Tombol utama; teks di atasnya memakai `onAccent` |
| `onAccent` | `#FFFFFF` | `#020617` | Teks di atas `accent` (4,9:1 / 10,5:1) |
| `success` | `#15803D` | `#4ADE80` | Akses diberikan (4,8:1 / 11,6:1) |
| `warning` | `#B45309` | `#FBBF24` | "Perlu diperbarui" (4,8:1 / 12,1:1) |
| `destructive` | `#DC2626` | `#F87171` | Hapus/cabut/gagal (4,6:1 / 7,3:1) |

Status **tidak boleh** dibedakan oleh warna saja. Selalu sertakan ikon SF Symbol + teks, misalnya "Ditangguhkan".

## 4. Ikon & spasi

- **SF Symbols** saja; tanpa emoji sebagai ikon. Contoh: `building.2`, `key.fill`, `lock.open.fill`, `person.2`, `exclamationmark.triangle`.
- Grid 8 pt. Spasi standar 16 pt; antar-bagian 24 pt. Jarak antar target sentuh ≥ 8 pt.
- **Target sentuh minimum 44×44 pt.**

## 5. Komponen kunci

| Komponen | Spesifikasi |
|---|---|
| **Baris kartu** (Daftar Kunci) | Ikon gedung, nama kartu, nama gedung, badge status (ikon + teks), chevron. Satu ketukan membuka Detail; tombol "Gunakan" di trailing untuk kanal N/B. |
| **Lembar Presentasi (N)** | Judul "Dekatkan bagian atas iPhone ke pembaca kartu", ilustrasi posisi iPhone, cincin hitung mundur 60 dtk (HCE), tombol "Batal". Hasil memakai `.success`/`.failure` sistem (O-A22) + haptic `.sensoryFeedback(.success/.error)`. |
| **Status Kedekatan (B)** | Indikator "Mencari pembaca…" → "Pembaca Lobi ditemukan" → hasil. Tidak memakai animasi berdenyut terus-menerus bila Reduce Motion aktif. |
| **Input OTP** | `.textContentType(.oneTimeCode)` untuk autofill SMS/email. Paste **diizinkan** (WCAG 2.2 *Accessible Authentication*); tanpa batas waktu ketik yang ketat. |
| **Input security code** | `SecureField` angka (keypad numerik), tombol tampil/sembunyikan, konfirmasi 2×, pesan error di dekat field. |
| **Tombol aksi async** | Saat provisioning/transfer: tombol dinonaktifkan + `ProgressView`; cegah ketukan ganda. |
| **Pemuatan daftar** | Skeleton/`redacted(reason: .placeholder)`; jangan layar kosong. |
| **Tombol Wallet (kanal W)** | Hanya aset resmi *Add to Apple Wallet* (`PKAddPassButton`) sesuai pedoman Apple. |
| **Dialog destruktif** | Hapus kartu/akun memakai `confirmationDialog` dengan peran `.destructive` + autentikasi. |

## 6. Gerak & haptic

- Durasi 200–300 ms, easing standar sistem; tanpa animasi dekoratif.
- `@Environment(\.accessibilityReduceMotion)` dipatuhi: tampilkan state akhir tanpa animasi.
- Haptic hanya untuk hasil bermakna: grant → `.success`, ditolak → `.error`, kesalahan input → `.warning`.

## 7. Aksesibilitas (wajib)

- Label VoiceOver untuk semua tombol ikon. Status presentasi diumumkan (`AccessibilityNotification.Announcement`).
- Semantic views: aksi memakai `Button`, bukan `Image` dengan `onTapGesture`.
- Mode gelap dan terang diuji. Buat beberapa `#Preview` (Light, Dark, AX5, bahasa ID/EN).

## 8. Anti-pola (dilarang)

- Desain *playful*, UX keamanan yang buruk (pesan error samar, aksi destruktif tanpa konfirmasi), gradien ungu/pink ala "AI".
- Meniru tampilan Apple Wallet/Apple Pay (O-A10).
- Emoji sebagai ikon; ukuran font tetap; target sentuh < 44 pt; status hanya lewat warna.
- Istilah teknis di UI presentasi: "NFC", "HCE", "APDU".

## 9. Checklist sebelum rilis UI

- [ ] Semua teks memakai text style Dynamic Type; lolos AX5 tanpa terpotong
- [ ] Kontras token sesuai tabel §3 di mode terang & gelap
- [ ] Target sentuh ≥ 44 pt, jarak ≥ 8 pt
- [ ] VoiceOver: semua kontrol berlabel; hasil presentasi diumumkan
- [ ] Reduce Motion dipatuhi
- [ ] Tidak ada elemen yang meniru Wallet/Apple Pay; tombol Wallet memakai aset resmi
- [ ] OTP mendukung autofill & paste
- [ ] Aksi async menonaktifkan tombol + indikator progres
- [ ] Pesan error spesifik + langkah lanjut (katalog SDD §15)
