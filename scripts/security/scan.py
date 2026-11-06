#!/usr/bin/env python3
"""Pemindaian secret dan dependensi Anastrophe (TC-SEC-11, ADR-0056).

    python3 scripts/security/scan.py                    # secret (riwayat + staged) dan dependensi
    python3 scripts/security/scan.py --build <App.app>  # ditambah produk build
    python3 scripts/security/scan.py secrets | deps | build <App.app>

Exit 0 bersih, 1 ada temuan, 2 alat tidak ada atau gagal, jaringan gagal, atau keluaran tidak bisa diurai.
Nilai secret tidak pernah dicetak: gitleaks selalu dijalankan dengan --redact, dan laporan hanya memuat
aturan, berkas, baris, serta commit. Ke OSV hanya dikirim nama paket dan versi.

Repo harus repo git yang bisa dibaca dan bukan clone dangkal. Penekanan hanya lewat allowlist beralasan di
.gitleaks.toml: komentar gitleaks:allow diabaikan dan .gitleaksignore ditolak.
"""
import argparse
import dataclasses
import http.client
import importlib.metadata
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONFIG = ROOT / ".gitleaks.toml"
MIN_GITLEAKS = (8, 30)
GOVULNCHECK = "golang.org/x/vuln/cmd/govulncheck@v1.9.0"
OSV_URL = "https://api.osv.dev/v1/query"
OSV_MAX_PAGES = 20
# gitleaks memakai exit 1 untuk temuan dan juga untuk galat fatal, jadi temuan diberi kode sendiri.
LEAKS_EXIT = 99


class ToolError(Exception):
    """Alat tidak ada, gagal, atau keluarannya tidak bisa diurai (exit 2)."""


@dataclasses.dataclass(frozen=True)
class Finding:
    rule: str
    file: str
    line: int
    commit: str  # 7 karakter; kosong untuk perubahan yang di-stage dan produk build


def _gitleaks():
    exe = shutil.which("gitleaks")
    if exe is None:
        raise ToolError("gitleaks tidak ditemukan di PATH (butuh versi ≥ 8.30)")
    try:
        version = subprocess.run([exe, "version"], capture_output=True, text=True, timeout=30).stdout.strip()
    except (OSError, subprocess.SubprocessError) as e:
        raise ToolError(f"gitleaks version gagal: {e}") from None
    m = re.search(r"(\d+)\.(\d+)", version)
    if not m or (int(m[1]), int(m[2])) < MIN_GITLEAKS:
        raise ToolError(f"gitleaks {version or '?'} terlalu lama; butuh ≥ 8.30")
    return exe


def run_gitleaks(args, cwd):
    """Menjalankan gitleaks dengan --redact dan laporan JSON. Hasilnya hanya dipercaya bila stderr kosong, laporan
    berisi JSON yang sah, dan exit code sesuai isi laporan; selain itu ToolError."""
    exe = _gitleaks()
    with tempfile.TemporaryDirectory() as tmp:
        report = pathlib.Path(tmp) / "laporan.json"
        cmd = [exe, *args, "--redact", "--no-banner", "--log-level", "error", "--ignore-gitleaks-allow",
               "--exit-code", str(LEAKS_EXIT), "--report-format", "json", "--report-path", str(report)]
        try:
            proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=900)
        except (OSError, subprocess.SubprocessError) as e:
            raise ToolError(f"gitleaks gagal dijalankan: {e}") from None
        # Keluaran gitleaks tidak diteruskan: pesan galatnya bisa memuat potongan isi berkas.
        if proc.returncode not in (0, LEAKS_EXIT):
            raise ToolError(f"gitleaks keluar dengan kode {proc.returncode}")
        if proc.stderr.strip():
            # Run yang bersih tidak menulis apa pun ke stderr pada --log-level error. Saat git gagal (repo ditolak,
            # objek hilang) gitleaks 8.30 tetap exit 0 dengan laporan [], jadi galat apa pun berarti hasil tak lengkap.
            raise ToolError("gitleaks melaporkan galat (konfigurasi, git, atau berkas tak terbaca); hasil tidak lengkap")
        try:
            data = json.loads(report.read_text())
            findings = [Finding(d["RuleID"], d["File"], int(d["StartLine"]), (d.get("Commit") or "")[:7]) for d in data]
        except (OSError, ValueError, KeyError, TypeError):
            raise ToolError("laporan gitleaks tidak bisa diurai") from None
    if (proc.returncode == LEAKS_EXIT) != bool(findings):
        raise ToolError("exit code gitleaks tidak sesuai dengan isi laporannya")
    return findings


def _git(repo, *args):
    git = shutil.which("git")
    if git is None:
        raise ToolError("git tidak ditemukan di PATH")
    try:
        return subprocess.run([git, "-C", str(repo), *args], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as e:
        raise ToolError(f"git gagal dijalankan: {e}") from None


def _check_repo(repo):
    """gitleaks tidak gagal saat git menolak atau tidak menemukan repo, jadi syarat riwayat diperiksa lebih dulu."""
    inside = _git(repo, "rev-parse", "--is-inside-work-tree")
    if inside.returncode != 0 or inside.stdout.strip() != "true":
        raise ToolError(f"{repo} bukan repo git yang bisa dibaca (git menolak atau tidak menemukan repo)")
    if _git(repo, "rev-parse", "--is-shallow-repository").stdout.strip() == "true":
        raise ToolError("repo adalah clone dangkal sehingga riwayatnya tidak lengkap; jalankan git fetch --unshallow")
    top = _git(repo, "rev-parse", "--show-toplevel").stdout.strip()
    for root in {pathlib.Path(repo), *([pathlib.Path(top)] if top else [])}:
        if (root / ".gitleaksignore").exists():
            raise ToolError(f"{root / '.gitleaksignore'} tidak diizinkan; pakai allowlist beralasan di .gitleaks.toml")


def scan_secrets(repo, config=CONFIG):
    """Seluruh riwayat git ditambah perubahan yang di-stage."""
    repo = pathlib.Path(repo)
    _gitleaks()  # alat diperiksa lebih dulu agar pesan galatnya jelas
    _check_repo(repo)
    history = run_gitleaks(["git", "--config", str(config), "."], cwd=repo)
    staged = run_gitleaks(["git", "--staged", "--config", str(config), "."], cwd=repo)
    return history + staged


def scan_build(bundle, config=CONFIG, min_len=8):
    """Produk build dipindai dua cara: gitleaks dir langsung (berkas teks dan aturan berbasis path, mis. .p12) dan
    cermin string cetak setiap berkas (biner Mach-O dilewati gitleaks dir). Temuan dari cermin diberi baris 0."""
    bundle = pathlib.Path(bundle)
    if not bundle.is_dir():
        raise ToolError(f"produk build tidak ditemukan: {bundle}")
    if (bundle / ".gitleaksignore").exists():
        raise ToolError(f"{bundle / '.gitleaksignore'} tidak diizinkan di produk build")
    direct = [dataclasses.replace(f, file=f.file.removeprefix("./"))
              for f in run_gitleaks(["dir", "--config", str(config), "."], cwd=bundle)]
    printable = re.compile(rb"[\t\x20-\x7e]{%d,}" % min_len)
    with tempfile.TemporaryDirectory() as tmp:
        mirror = pathlib.Path(tmp)
        for path in sorted(p for p in bundle.rglob("*") if p.is_file() and not p.is_symlink()):
            try:
                runs = printable.findall(path.read_bytes())
            except OSError as e:
                raise ToolError(f"berkas produk build tidak terbaca: {path.relative_to(bundle)} ({e.strerror})") from None
            if runs:
                target = mirror / (str(path.relative_to(bundle)) + ".txt")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"\n".join(runs) + b"\n")
        mirrored = run_gitleaks(["dir", "--config", str(config), "."], cwd=mirror)
    seen, extra = {(f.rule, f.file) for f in direct}, []
    for f in mirrored:
        f = dataclasses.replace(f, file=f.file.removeprefix("./").removesuffix(".txt"), line=0)
        if (f.rule, f.file) not in seen:
            seen.add((f.rule, f.file))
            extra.append(f)
    return direct + extra


GO_LEVELS = {"modul": 0, "paket": 1, "fungsi": 2}


@dataclasses.dataclass(frozen=True)
class GoVuln:
    osv: str
    module: str
    fixed: str
    level: str  # "fungsi" (kode rentan terpanggil), "paket" (diimpor), atau "modul" (hanya ada di graf modul)

    @property
    def called(self):
        return self.level == "fungsi"


def parse_govulncheck(stream):
    """Mengurai aliran objek JSON govulncheck; tanpa objek config berarti bukan keluaran govulncheck."""
    decoder, i, seen_config, vulns = json.JSONDecoder(), 0, False, {}
    try:
        while True:
            while i < len(stream) and stream[i].isspace():
                i += 1
            if i >= len(stream):
                break
            obj, i = decoder.raw_decode(stream, i)
            seen_config |= "config" in obj
            finding = obj.get("finding")
            if not finding:
                continue
            trace = finding.get("trace") or []
            level = ("fungsi" if any(f.get("function") for f in trace) else
                     "paket" if any(f.get("package") for f in trace) else "modul")
            vuln = GoVuln(finding["osv"], trace[0]["module"] if trace else "?", finding.get("fixed_version") or "", level)
            # Satu OSV bisa muncul di beberapa tingkat; modul dan versi perbaikan diambil dari tingkat tertinggi.
            prev = vulns.get(vuln.osv)
            if prev is None or GO_LEVELS[vuln.level] > GO_LEVELS[prev.level]:
                vulns[vuln.osv] = vuln
    except (ValueError, KeyError, TypeError, AttributeError, IndexError):
        raise ToolError("keluaran govulncheck tidak bisa diurai") from None
    if not seen_config:
        raise ToolError("keluaran govulncheck tidak dikenali (tanpa objek config)")
    return list(vulns.values())


def run_govulncheck(backend):
    go = shutil.which("go")
    if go is None:
        raise ToolError("go tidak ditemukan di PATH (dibutuhkan untuk govulncheck)")
    try:
        proc = subprocess.run([go, "run", GOVULNCHECK, "-format", "json", "./..."], cwd=backend,
                              capture_output=True, text=True, timeout=1800)
    except (OSError, subprocess.SubprocessError) as e:
        raise ToolError(f"govulncheck gagal dijalankan: {e}") from None
    if proc.returncode != 0:
        raise ToolError(f"govulncheck keluar dengan kode {proc.returncode}: {proc.stderr.strip()[-300:]}")
    return proc.stdout


# Direktori yang dilewati saat mencari Package.swift: build/checkout, bukan sumber (minor review akhir
# ADR-0056 — sebelumnya hanya Packages/Package.swift yang diperiksa, jadi paket Swift lokal lain dengan
# dependensi remote lolos tanpa terdeteksi).
_SWIFT_SCAN_EXCLUDE = {".build", "build", "DerivedData", ".git", "worktrees"}


def swift_packages_remote(repo):
    """App iOS harus tetap tanpa paket pihak ketiga sampai ada pemindai untuk ekosistem Swift. Semua
    `Package.swift` di repo diperiksa, bukan hanya satu path tetap."""
    repo = pathlib.Path(repo)
    found = []
    try:
        pbxproj = repo / "Anastrophe.xcodeproj/project.pbxproj"
        if pbxproj.exists() and "XCRemoteSwiftPackageReference" in pbxproj.read_text():
            found.append(f"{pbxproj.relative_to(repo)}: XCRemoteSwiftPackageReference")
        for pkg in sorted(repo.rglob("Package.swift")):
            rel = pkg.relative_to(repo)
            if _SWIFT_SCAN_EXCLUDE & set(rel.parts):
                continue
            if ".package(" in pkg.read_text():
                found.append(f"{rel}: dependensi .package(")
        return found
    except OSError as e:
        raise ToolError(f"berkas proyek Swift tidak terbaca: {e}") from None


def osv_query(payload):
    request = urllib.request.Request(OSV_URL, data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(request, timeout=20) as resp:
        return json.loads(resp.read().decode())


def _requirement_names(path, _seen=None):
    """Nama paket dari requirements.txt. Baris `-r lain.txt` / `--requirement lain.txt` diikuti rekursif,
    relatif terhadap direktori berkas yang memuatnya (minor review akhir ADR-0056); tanpa ini, paket di
    berkas yang di-include tidak pernah diperiksa OSV. _seen mencegah siklus -r yang saling mengarah."""
    path = pathlib.Path(path)
    seen = _seen if _seen is not None else set()
    resolved = path.resolve()
    if resolved in seen:
        return []
    seen.add(resolved)
    names = []
    for line in path.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        m = re.match(r"-{1,2}r(?:equirement)?[\s=]+(.+)$", line)
        if m:
            names += _requirement_names(path.parent / m[1].strip(), seen)
            continue
        if line.startswith("-"):
            continue
        names.append(re.split(r"[=<>!~\[;\s@]", line, maxsplit=1)[0])
    return names


def python_advisories(requirements, query=osv_query, version_of=importlib.metadata.version):
    """Advisori OSV untuk versi yang terpasang; paket yang tidak terpasang dilewati sebagai informasi."""
    vulnerable, skipped = [], []
    for req in requirements:
        try:
            names = _requirement_names(req)
        except OSError as e:
            raise ToolError(f"{req} tidak terbaca ({e.strerror})") from None
        for name in names:
            try:
                version = version_of(name)
            except importlib.metadata.PackageNotFoundError:
                skipped.append(f"{name} (tidak terpasang)")
                continue
            payload = {"package": {"name": name, "ecosystem": "PyPI"}, "version": version}
            raw = []
            # OSV bisa mengembalikan hanya next_page_token tanpa hasil; halaman diikuti sampai token habis.
            for _ in range(OSV_MAX_PAGES):
                try:
                    resp = query(payload)
                    raw += resp.get("vulns") or []
                    token = resp.get("next_page_token")
                except (OSError, ValueError, KeyError, TypeError, AttributeError, http.client.HTTPException) as e:
                    raise ToolError(f"kueri OSV untuk {name} gagal: {e}") from None
                if not token:
                    break
                payload = {**payload, "page_token": token}
            else:
                raise ToolError(f"kueri OSV untuk {name} tidak selesai sesudah {OSV_MAX_PAGES} halaman")
            vulnerable += [f"{name} {version}: {vid}" for vid in _dedupe_aliases(raw)]
    return vulnerable, skipped


def _dedupe_aliases(vulns):
    """Mengelompokkan entri OSV yang saling menjadi alias (mis. GHSA dan PYSEC untuk kerentanan yang sama)
    dan mengembalikan satu id per kelompok, agar jumlah advisori tidak berlipat (minor review akhir
    ADR-0056). CVE dipilih sebagai id kanonik bila ada di kelompoknya; selain itu, id yang leksikografis
    terkecil, agar hasilnya deterministik."""
    groups = []
    for v in vulns:
        ids = {v["id"], *(v.get("aliases") or [])}
        for g in groups:
            if g & ids:
                g |= ids
                break
        else:
            groups.append(set(ids))
    return [min(g, key=lambda i: (0 if i.startswith("CVE-") else 1, i)) for g in groups]


def scan_deps(repo, out, govulncheck=run_govulncheck, query=osv_query, version_of=importlib.metadata.version):
    """Mengembalikan True bila ada temuan dependensi. Tiga sub-pemeriksaan (Go, Swift, Python) berjalan
    independen: satu yang gagal tetap melaporkan hasil dua lainnya, bukan menyembunyikannya (minor review
    akhir ADR-0056). Galat dikumpulkan dan dilempar sebagai satu ToolError sesudah semuanya dicoba."""
    found, errors = False, []
    try:
        vulns = parse_govulncheck(govulncheck(repo / "backend"))
        called = [v for v in vulns if v.called]
        print(f"dependensi Go (govulncheck): {len(called)} kerentanan terpanggil", file=out)
        status = {"fungsi": "terpanggil", "paket": "diimpor, fungsi rentan tidak terpanggil",
                  "modul": "di graf modul, paket tidak diimpor"}
        for v in vulns:
            prefix = "  " if v.called else "  informasi: "
            print(f"{prefix}{v.osv}  {v.module}  {status[v.level]}; perbaikan: {v.fixed or 'belum ada'}", file=out)
        found |= bool(called)
    except ToolError as e:
        errors.append(str(e))
    try:
        remote = swift_packages_remote(repo)
        print(f"paket Swift remote: {len(remote)}", file=out)
        for r in remote:
            print(f"  {r}", file=out)
        found |= bool(remote)
    except ToolError as e:
        errors.append(str(e))
    try:
        vulnerable, skipped = python_advisories(sorted(repo.glob("scripts/*/requirements.txt")), query, version_of)
        print(f"dependensi Python (OSV): {len(vulnerable)} advisori", file=out)
        for v in vulnerable:
            print(f"  {v}", file=out)
        for s in skipped:
            print(f"  informasi: {s} dilewati", file=out)
        found |= bool(vulnerable)
    except ToolError as e:
        errors.append(str(e))
    if errors:
        raise ToolError("; ".join(errors))
    return found


def _report(title, findings, out):
    print(f"{title}: {len(findings)} temuan", file=out)
    for f in findings:
        location = f"{f.file} (string cetak)" if f.line == 0 else f"{f.file}:{f.line}"
        where = f"  (commit {f.commit})" if f.commit else ""
        print(f"  {f.rule}  {location}{where}", file=out)


def main(argv=None, out=sys.stdout, err=sys.stderr, *, govulncheck=run_govulncheck, osv_query=osv_query,
         pip_version=importlib.metadata.version):
    parser = argparse.ArgumentParser(prog="scan.py", description="Pemindaian secret dan dependensi (TC-SEC-11).")
    parser.add_argument("perintah", nargs="?", choices=["secrets", "deps", "build"], help="tanpa perintah: secrets dan deps")
    parser.add_argument("path", nargs="?", type=pathlib.Path, help="produk build .app untuk perintah build")
    parser.add_argument("--repo", type=pathlib.Path, default=ROOT, help="repo git yang dipindai (bawaan: repo ini)")
    parser.add_argument("--config", type=pathlib.Path, default=CONFIG, help="konfigurasi gitleaks")
    parser.add_argument("--build", dest="bundle", type=pathlib.Path, help="produk build .app yang ikut dipindai")
    args = parser.parse_args(argv)
    if args.perintah == "build" and args.path is None:
        parser.error("perintah build butuh path produk build")
    bundle = args.path if args.perintah == "build" else args.bundle
    # gitleaks berjalan dengan cwd = repo, jadi path relatif dari pemanggil diselesaikan lebih dulu.
    repo, config = args.repo.resolve(), args.config.resolve()
    # Setiap bagian (secrets, deps, build) berjalan independen: satu yang gagal tidak menghentikan atau
    # menyembunyikan hasil bagian lain (minor review akhir ADR-0056).
    found, errors = False, []
    if args.perintah in (None, "secrets"):
        try:
            secrets = scan_secrets(repo, config)
            _report("secret (riwayat + staged)", secrets, out)
            found |= bool(secrets)
        except ToolError as e:
            errors.append(str(e))
    if args.perintah in (None, "deps"):
        try:
            found |= scan_deps(repo, out, govulncheck, osv_query, pip_version)
        except ToolError as e:
            errors.append(str(e))
    if bundle is not None:
        try:
            built = scan_build(bundle, config)
            _report(f"secret (produk build {bundle.name})", built, out)
            found |= bool(built)
        except ToolError as e:
            errors.append(str(e))
    if errors:
        for e in errors:
            print(f"scan.py: {e}", file=err)
        return 2
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
