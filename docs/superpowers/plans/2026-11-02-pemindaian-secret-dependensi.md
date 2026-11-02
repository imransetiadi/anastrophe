# Pemindaian secret dan dependensi (TC-SEC-11) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** satu perintah (`python3 scripts/security/scan.py`) yang memindai secret di riwayat git, perubahan yang di-stage, dan produk build, serta memindai dependensi backend Go, app iOS, dan alat Python. Hasil pertamanya dicatat untuk TC-SEC-11.

**Architecture:** konfigurasi repo `.gitleaks.toml` (aturan bawaan + allowlist sempit) dan pembungkus Python stdlib. Pembungkus menjalankan gitleaks, govulncheck, dan kueri OSV, lalu menerapkan kebijakan exit code 0/1/2 tanpa pernah mencetak nilai secret.

**Tech Stack:** Python 3 stdlib (unittest, subprocess, json, urllib), gitleaks ≥ 8.30 (PATH), govulncheck `golang.org/x/vuln/cmd/govulncheck@v1.9.0` lewat `go run`, OSV API.

**Spec:** `docs/superpowers/specs/2026-11-02-pemindaian-secret-dependensi-design.md`

## Global Constraints

- Python stdlib saja; tidak ada `pip install`.
- gitleaks selalu dijalankan dengan `--redact`. Laporan memuat aturan, berkas, baris, dan commit (7 karakter), tidak pernah nilai secret.
- Tidak ada secret uji literal di berkas repo. Test merakit token palsu saat runtime.
- Exit code: 0 bersih, 1 ada temuan, 2 alat tidak ada, alat gagal, jaringan gagal, atau keluaran tidak bisa diurai.
- Yang dikirim ke OSV hanya nama paket dan versi.
- Tanpa CI, tanpa pemasangan hook git, tanpa penulisan ulang riwayat. Secret nyata di riwayat dieskalasi ke pengguna.
- Dokumen dan pesan dalam Bahasa Indonesia.

## Review Focus

1. Allowlist sempit: secret nyata di kode Swift atau JSON lain tetap terdeteksi (test `test_kunci_acak_di_swift_tetap_terdeteksi`, `test_vektor_di_path_lain_terdeteksi`).
2. Tidak ada jalur yang mencetak nilai secret, termasuk saat parser gagal (test `test_laporan_tanpa_nilai_secret`).
3. Kegagalan alat atau jaringan memberi exit 2, tidak pernah 0 (test `test_gitleaks_tidak_ada_exit_2`, `test_govulncheck_json_rusak_exit_2`, `test_osv_jaringan_gagal_exit_2`).
4. Temuan Go yang terpanggil gagal, dan parser menerima aliran beberapa objek JSON (test `test_govulncheck_terpanggil_gagal`).
5. Build: biner dipindai lewat string cetak dengan path relatif bundle (test `test_build_biner_terdeteksi_tanpa_nilai`).

---

### Task 1: Konfigurasi gitleaks dan pemindaian secret

**Files:**
- Create: `.gitleaks.toml`
- Create: `scripts/security/scan.py`
- Test: `scripts/security/test_scan.py`

**Interfaces:**
- Produces:
  - `Finding = dataclass(rule: str, file: str, line: int, commit: str)`;
  - `ToolError(Exception)`;
  - `run_gitleaks(args: list[str], cwd: Path) -> list[Finding]`, yang menambahkan `--redact --no-banner --report-format json --report-path <tmp>` dan melempar `ToolError` bila exit selain 0/1 atau laporan tidak bisa diurai;
  - `scan_secrets(repo: Path, config: Path) -> list[Finding]` (riwayat + `--staged`);
  - `scan_build(bundle: Path, config: Path, min_len: int = 8) -> list[Finding]`;
  - `main(argv: list[str], out=sys.stdout, err=sys.stderr) -> int`.

- [ ] **Step 1: Tulis test yang gagal.** Helper `repo_sementara()` membuat repo git kosong dan menyalin `.gitleaks.toml`. `token_palsu()` merakit `"ghp" + "_" + 36 karakter alfanumerik acak`. Test:
  - `test_riwayat_mendeteksi_token_palsu`: commit `a.txt` berisi token → `scan_secrets` menemukan 1 temuan aturan `github-pat`, berkas `a.txt`.
  - `test_staged_mendeteksi_token_palsu`: token hanya di-stage → terdeteksi.
  - `test_anotasi_tipe_diabaikan`: deklarasi `let` beranotasi tipe `P256.Signing.PrivateKey` di `K.swift` (dirakit di test) → 0 temuan.
  - `test_kunci_acak_di_swift_tetap_terdeteksi`: `let api_key = "<40 hex acak>"` di `K.swift` → ≥ 1 temuan.
  - `test_vektor_hanya_diabaikan_di_path_allowlist`: salinan `anp1-v1.json` di path allowlist → 0 temuan; isi yang sama di `lain/anp1-v1.json` → ≥ 1 temuan (`test_vektor_di_path_lain_terdeteksi`).
  - `test_build_biner_terdeteksi_tanpa_nilai`: `App.app/App` biner (byte acak + token + byte acak) → temuan dengan `file == "App"`; teks laporan `main` tidak memuat token.
  - `test_laporan_tanpa_nilai_secret`: keluaran `main(["secrets", ...])` tidak memuat token.
  - `test_gitleaks_tidak_ada_exit_2`: PATH tanpa gitleaks → `main` mengembalikan 2.
- [ ] **Step 2: Jalankan dan lihat gagal.** Run: `python3 -m unittest discover -s scripts/security -v`. Expected: ImportError/AttributeError (`scan` belum ada).
- [ ] **Step 3: Implementasi.**
  - `.gitleaks.toml`: `[extend] useDefault = true`, dengan dua `[[allowlists]]` beralasan (`description`):
    - `regexTarget = "secret"`, `regexes = ['''^P256\.Signing\.PrivateKey$''']`;
    - `paths = ['''^Packages/Tests/ANCryptoTests/Resources/anp1-v1\.json$''']`.
  - `scan.py`: subperintah `secrets`, `build <path>`, `deps` (Task 2), tanpa subperintah = `secrets` + `deps`, dan `--build <path>`.
  - Ekstraksi build: untuk setiap berkas, ambil run byte cetak `[\x20-\x7e]{min_len,}`, tulis ke `<tmp>/<rel>.txt`, lalu `gitleaks dir <tmp>`, dan petakan path kembali (buang `.txt`).
- [ ] **Step 4: Jalankan dan lihat lulus.** Run yang sama. Expected: semua test Task 1 OK.
- [ ] **Step 5: Mutasi.** Allowlist path dilebarkan ke `^Packages/`, `--redact` dihapus, `min_len` 1000, `ToolError` ditelan menjadi daftar kosong → masing-masing harus menggagalkan test.
- [ ] **Step 6: Commit** `feat(security): konfigurasi gitleaks dan pemindaian secret riwayat, staged, build (TC-SEC-11)`.

### Task 2: Pemindaian dependensi

**Files:**
- Modify: `scripts/security/scan.py`
- Test: `scripts/security/test_scan.py`

**Interfaces:**
- Consumes: `ToolError`, `main` dari Task 1.
- Produces:
  - `GoVuln = dataclass(osv: str, module: str, fixed: str, called: bool)`;
  - `parse_govulncheck(stream: str) -> list[GoVuln]`, yang mengurai aliran objek JSON dengan `JSONDecoder.raw_decode`; `called` bernilai true bila ada frame jejak dengan `function`;
  - `run_govulncheck(backend: Path) -> str`, dengan konstanta `GOVULNCHECK = "golang.org/x/vuln/cmd/govulncheck@v1.9.0"`;
  - `swift_remote_packages(package_swift: Path, pbxproj: Path) -> list[str]`;
  - `python_advisories(requirements: list[Path], query) -> tuple[list[str], list[str]]` (rentan, dilewati). `query(payload: dict) -> dict` diinjeksi; bawaannya POST `https://api.osv.dev/v1/query` dengan timeout 20 dtk.

- [ ] **Step 1: Tulis test yang gagal:**
  - `test_govulncheck_terpanggil_gagal`: dua objek JSON (`config`, lalu `finding` dengan `trace[0].function`) → 1 `GoVuln(called=True)`, dan `main deps` (dengan runner diinjeksi) → 1.
  - `test_govulncheck_modul_saja_info`: finding tanpa `function` → `called=False`, exit 0, dan pesan berisi "informasi".
  - `test_govulncheck_json_rusak_exit_2`.
  - `test_paket_swift_remote_gagal`: pbxproj berisi `XCRemoteSwiftPackageReference` → daftar tidak kosong, exit 1.
  - `test_osv_vuln_gagal`, `test_osv_kosong_lulus`, `test_osv_jaringan_gagal_exit_2` (`query` melempar `OSError`), `test_paket_tidak_terpasang_info`.
- [ ] **Step 2: Jalankan dan lihat gagal.** Run: `python3 -m unittest discover -s scripts/security -v`. Expected: AttributeError untuk fungsi Task 2.
- [ ] **Step 3: Implementasi** sesuai Interfaces. `main` menerima runner dan `query` yang bisa diinjeksi lewat parameter kata kunci untuk test.
- [ ] **Step 4: Jalankan dan lihat lulus.** Expected: semua test OK.
- [ ] **Step 5: Mutasi.** `called` selalu false, exit 2 menjadi 0 untuk JSON rusak, dan pemeriksaan pbxproj dimatikan → masing-masing tertangkap.
- [ ] **Step 6: Commit** `feat(security): pemindaian dependensi Go, paket Swift, dan advisori Python (TC-SEC-11)`.

### Task 3: Run nyata dan dokumen

**Files:**
- Modify: `docs/QA_SUITE.md` (§11.1, baris TC-SEC-11), `docs/SDD.md` (keamanan + baris versi), `README.md`, `docs/agentmemory/backlog.md`
- Modify bila perlu: `.gitleaks.toml` (allowlist beralasan untuk positif palsu baru)

- [ ] **Step 1: Build Release simulator segar.** Run: `xcodebuild -project Anastrophe.xcodeproj -scheme Anastrophe -configuration Release -sdk iphonesimulator -derivedDataPath build/DerivedDataScan CODE_SIGNING_ALLOWED=NO build`. Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 2: Run pemindaian penuh.** Run: `python3 scripts/security/scan.py --build build/DerivedDataScan/Build/Products/Release-iphonesimulator/Anastrophe.app`. Expected: exit 0. Bila exit 1, putuskan per temuan:
  - positif palsu → allowlist sempit beralasan;
  - kerentanan dependensi → naikkan versi dengan test hijau;
  - secret nyata → hentikan dan eskalasi.
- [ ] **Step 3: Dokumen.**
  - QA §11.1 TC-SEC-11: jumlah commit yang dipindai, temuan sebelum dan sesudah allowlist, hasil govulncheck, paket Swift, dan advisori Python.
  - README: perintah dan arti exit code.
  - SDD: pendekatan pemindaian dan baris versi.
  - Backlog: langkah CI dan hook pre-commit.
- [ ] **Step 4: Verifikasi.** Run: `python3 scripts/docs/check_docs.py .` → `problems: 0`.
- [ ] **Step 5: Commit** `docs: hasil pemindaian secret dan dependensi (QA TC-SEC-11)`.
