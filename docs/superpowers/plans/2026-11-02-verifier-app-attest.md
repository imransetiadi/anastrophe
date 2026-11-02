# Verifier App Attest — Rencana Implementasi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paket backend `internal/appattest` memverifikasi attestation dan assertion App Attest menurut langkah Apple, terbukti dengan contoh resmi Apple dan vektor sintetis.

**Architecture:** decoder CBOR minimal dan pengurai authData. `Verifier` menjalankan langkah attestation (rantai x5c ke root Apple tertanam, nonce, key id, RP ID, counter, aaguid, credentialId, ekstensi) dan langkah assertion (RP ID, counter, digest `SHA256(nonce)`). Paket ini belum dipakai endpoint.

**Tech Stack:** Go 1.27 (`crypto/x509`, `crypto/ecdsa`, `encoding/asn1`, `embed`).

**Spec:** `docs/superpowers/specs/2026-11-02-verifier-app-attest-design.md` (ADR-0052).

## Global Constraints

- **Batas paket:** `internal/appattest` saja. Tidak ada perubahan endpoint, database, CLI, atau app.
- **Data pihak ketiga:** tidak boleh masuk repo. Data uji repo hanya contoh resmi Apple (E36) beserta sumbernya, ditambah vektor sintetis.
- **Galat:** semua kegagalan verifikasi `errors.Is(err, ErrInvalid)`. Alasan hanya di `*Error.Reason`.
- **Masukan rusak:** tidak ada panic. Batasnya: attestation ≤ 64 KiB, assertion ≤ 4 KiB, kedalaman CBOR ≤ 8.
- **Commit:** pesan berbahasa Indonesia dan diakhiri `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Tanpa push.
- **Verifikasi:** `go -C backend vet ./...`, `env ANASTROPHE_REQUIRE_PG=1 go -C backend test ./...`, dan `check_docs` exit 0.

## Review Focus

1. **Rantai wajib lengkap ke root yang dikonfigurasi.** Test: `TestContohAppleDitolak` (intermediate hilang, pool root uji, kedaluwarsa) dan `TestAttestationSintetisDitolak/urutan_x5c_tertukar`.
2. **Panjang palsu tidak membuat panic atau alokasi besar.** Test: `TestDecodeCBORMenolak`, `TestAuthDataMenolak` (panjang `credentialId` 0xFFFF, panjang byte string 2^32), `FuzzVerifyAttestation`, `FuzzVerifyAssertion`.
3. **Digest assertion dan counter.** Test: `TestAssertionSintetisDitolak/hash_tunggal`, `/counter_tidak_naik`, `/counter_pertama_nol`.
4. **`clientDataHash` dari pemanggil.** Test: `TestContohAppleLulus` (challenge mentah) dan `TestContohAppleDitolak/clientDataHash_sha256` (nonce).
5. **Ekstensi.** Test: `TestAttestationSintetisLulus/tanpa_ekstensi`, `TestAttestationSintetisDitolak/kategori_di_luar_daftar`, `/kategori_bukan_4_byte`, `/versi_bukan_teks`.

---

### Task 1: Decoder CBOR dan pengurai authData

**Files:**
- Create: `backend/internal/appattest/cbor.go`, `backend/internal/appattest/authdata.go`, `backend/internal/appattest/errors.go`, `backend/internal/appattest/cbor_test.go`, `backend/internal/appattest/authdata_test.go`

**Interfaces:**
- Produces:
  - `var ErrInvalid = errors.New(...)`; `type Error struct{ Reason string; Err error }` dengan `Error()` dan `Unwrap() error` (mengembalikan `ErrInvalid`); `func invalid(reason string, err error) error`.
  - `func decodeCBOR(data []byte) (any, error)`. Tipe hasil: `uint64`, `int64`, `[]byte`, `string`, `[]any`, `map[any]any` dengan kunci `string` atau `int64`.
  - `type authData struct{ RPIDHash []byte; Flags byte; Counter uint32; AAGUID []byte; CredentialID []byte; Category *uint32; BundleVersion *string }`.
  - `func parseAttestationAuthData(b []byte) (authData, error)` dan `func parseAssertionAuthData(b []byte) (authData, error)` (I-16).

- [ ] **Step 1: Tulis test yang gagal:**
  - `TestDecodeCBORLulus`: map kunci teks dan integer, array, byte string, teks, uint, negint.
  - `TestDecodeCBORMenolak`: data terpotong, panjang tak tentu (info 31), kedalaman 9, kunci duplikat, sisa byte, tag (major 6), float/simple (major 7), panjang byte string 2^32 tanpa data, dan teks UTF-8 rusak.
  - `TestAuthDataAttestationLulus`: susunan header + aaguid + credentialId + kunci COSE + ekstensi `{apple_bundle_version_01: "7", apple_validation_category_01: h'04000000'}` → kategori 4, versi "7"; versi tanpa ekstensi juga lulus (Category dan BundleVersion nil).
  - `TestAuthDataAssertionLulus`: header 37 byte saja; header + ekstensi.
  - `TestAuthDataMenolak`: kurang dari 37 byte; panjang `credentialId` 0xFFFF; kunci COSE bukan item CBOR; sisa sesudah ekstensi; ekstensi bukan map; kategori bukan 4 byte; versi bukan teks.
- [ ] **Step 2: Jalankan** `go -C backend test ./internal/appattest/`. Expected: FAIL (build).
- [ ] **Step 3: Implementasikan.**
  - Panjang dicek terhadap sisa data sebelum alokasi.
  - Kunci map hanya `string` atau `int64`, dan duplikat ditolak.
  - Ekstensi: kunci tak dikenal diabaikan; `apple_validation_category_01` wajib `[]byte` 4 byte (uint32 little-endian); `apple_bundle_version_01` wajib `string`.
- [ ] **Step 4: Jalankan.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(appattest): decoder CBOR dan pengurai authData App Attest (ADR-0052)`.

### Task 2: Verifikasi attestation

**Files:**
- Create: `backend/internal/appattest/verifier.go`, `backend/internal/appattest/apple_app_attestation_root_ca.pem`, `backend/internal/appattest/testdata/apple-sample-attestation-2026.json`, `backend/internal/appattest/verifier_test.go`, `backend/internal/appattest/synthetic_test.go`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `type Environment int` dengan konstanta `Production` dan `Development`.
  - `type Config struct{ AppID string; Environment Environment; Roots *x509.CertPool; Now func() time.Time; Categories []uint32 }`.
  - `func NewVerifier(cfg Config) (*Verifier, error)`.
  - `type Attestation struct{ PublicKey, KeyID, Receipt []byte; ValidationCategory *uint32; BundleVersion *string }`.
  - `func (v *Verifier) VerifyAttestation(attestation, clientDataHash, keyID []byte) (Attestation, error)`.
  - `const MaxAttestationSize = 64 << 10`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `TestRootAppleTertanam`: SHA-256 DER root = `1cb9823ba28ba6ad2d33a006941de2ae4f513ef1d4e831b9f7e0fa7b6242c932`.
  - `TestNewVerifierMenolakAppIDRusak`: "", "1234.com.x", "1234567890", "1234567890.com/x".
  - `TestContohAppleLulus`: App ID `1234567890.com.example.myapp`, production, `clientDataHash = []byte("example_server_challenge")`, keyID dari base64 `zgSY9YSD+7TaDXssY6WlOPVS1K3Lmk+pFhlcSWE+ZV0=`, `Now` = 2026-04-21T12:00:00Z. Hasilnya: `SHA256(PublicKey)` = keyID, `len(PublicKey)` 65, kategori 1, versi "1", receipt tidak kosong.
  - `TestContohAppleDitolak` (subtest per alasan):
    - App ID lain → `rp_id`;
    - Development → `aaguid`;
    - keyID lain → `key_id`;
    - `clientDataHash = SHA256(challenge)` → `nonce`;
    - `Now` 2026-11-02 → `chain`;
    - pool root uji → `chain`;
    - satu byte authData diubah → `nonce`;
    - x5c tanpa intermediate → `chain`.
  - `TestAttestationSintetisLulus`: dasar; development + `appattestdevelop`; tanpa ekstensi.
  - `TestAttestationSintetisDitolak`: counter 1 → `counter`; credentialId lain → `credential_id`; receipt kosong → `format`; `fmt` lain → `format`; leaf P-384 → `key`; tanpa ekstensi nonce → `nonce`; ekstensi nonce rusak → `nonce`; `urutan_x5c_tertukar` → `chain`; `kategori_di_luar_daftar` (`Categories: []uint32{4}`, kategori 3) → `category`; `kategori_bukan_4_byte` / `versi_bukan_teks` → `format`.
- [ ] **Step 2: Jalankan.** Expected: FAIL.
- [ ] **Step 3: Implementasikan** langkah spec §Desain secara berurutan.
  - Root Apple di-embed. PEM diambil dari E38 dan diperiksa sidik jarinya.
  - Testdata contoh Apple: JSON dengan `source`, `retrieved`, `appId`, `keyId`, `clientDataHash` (teks challenge mentah), `attestation` (base64), `checkTime`, dan `notes` (O-AA05).
  - Helper sintetis (`synthetic_test.go`): CA uji P-256 → intermediate → leaf dengan ekstensi `1.2.840.113635.100.8.2` (`SEQUENCE{[1] EXPLICIT OCTET STRING}`) dan authData yang dirakit.
- [ ] **Step 4: Jalankan.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(appattest): verifikasi attestation App Attest dengan contoh resmi Apple (ADR-0052)`.

### Task 3: Verifikasi assertion dan fuzz

**Files:**
- Modify: `backend/internal/appattest/verifier.go`, `backend/internal/appattest/synthetic_test.go`
- Create: `backend/internal/appattest/assertion_test.go`, `backend/internal/appattest/fuzz_test.go`

**Interfaces:**
- Consumes: Task 1 dan Task 2.
- Produces:
  - `type Assertion struct{ Counter uint32; ValidationCategory *uint32; BundleVersion *string }`.
  - `func (v *Verifier) VerifyAssertion(assertion, clientData, publicKey []byte, previousCounter uint32) (Assertion, error)`.
  - `const MaxAssertionSize = 4 << 10`.

- [ ] **Step 1: Tulis test yang gagal:**
  - `TestAssertionSintetisLulus`: counter 5 dengan sebelumnya 4 → Counter 5; dengan ekstensi kategori 3 dan versi "9".
  - `TestAssertionSintetisDitolak`:
    - `counter_tidak_naik` (5 vs 5) → `counter`;
    - `counter_pertama_nol` (0 vs 0) → `counter`;
    - `clientData` lain → `signature`;
    - App ID lain → `rp_id`;
    - `hash_tunggal` (tanda tangan atas `nonce` langsung) → `signature`;
    - kunci publik 64 byte / titik di luar kurva → `key`;
    - assertion 4 KiB + 1 → `format`;
    - tanpa `signature` → `format`.
  - `FuzzVerifyAttestation` dan `FuzzVerifyAssertion`, dengan seed contoh Apple dan vektor sintetis: tidak panic, dan setiap galat `errors.Is(err, ErrInvalid)`.
- [ ] **Step 2: Jalankan.** Expected: FAIL.
- [ ] **Step 3: Implementasikan** spec §Desain langkah assertion.
- [ ] **Step 4: Jalankan** test, lalu `go -C backend test ./internal/appattest/ -run '^$' -fuzz FuzzVerifyAttestation -fuzztime 20s` dan yang sama untuk assertion. Expected: PASS, tanpa crash.
- [ ] **Step 5: Commit** `feat(appattest): verifikasi assertion App Attest dengan digest SHA256(nonce) (ADR-0052)`.

### Task 4: Dokumen

**Files:**
- Modify:
  - `docs/SDD.md`: §10.4 "App Attest (NFR-S03)" berisi langkah verifikasi server, konvensi `clientDataHash`, digest assertion, kebijakan ekstensi, dan status belum disambungkan; plus revisi.
  - `docs/QA_SUITE.md`: TC-SEC-16 "Verifier App Attest di server" (U), hasil di §11.1, dan §14 NFR-S03.
  - `backend/README.md` bila ada daftar paket.

- [ ] **Step 1: Perbarui dokumen**, lalu jalankan `check_docs` (exit 0).
- [ ] **Step 2: Commit** `docs: verifier App Attest (SDD §10.4, QA TC-SEC-16)`.
