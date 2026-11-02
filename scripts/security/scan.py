#!/usr/bin/env python3
"""Pemindaian secret dan dependensi Anastrophe (TC-SEC-11, ADR-0056).

    python3 scripts/security/scan.py                    # secret (riwayat + staged) dan dependensi
    python3 scripts/security/scan.py --build <App.app>  # ditambah produk build
    python3 scripts/security/scan.py secrets | deps | build <App.app>

Exit 0 bersih, 1 ada temuan, 2 alat tidak ada atau gagal, jaringan gagal, atau keluaran tidak bisa diurai.
Nilai secret tidak pernah dicetak: gitleaks selalu dijalankan dengan --redact, dan laporan hanya memuat
aturan, berkas, baris, serta commit. Ke OSV hanya dikirim nama paket dan versi.
"""
import argparse
import dataclasses
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
    """Menjalankan gitleaks dengan --redact dan laporan JSON; exit selain 0/1 atau laporan rusak → ToolError."""
    exe = _gitleaks()
    with tempfile.TemporaryDirectory() as tmp:
        report = pathlib.Path(tmp) / "laporan.json"
        cmd = [exe, *args, "--redact", "--no-banner", "--log-level", "error",
               "--report-format", "json", "--report-path", str(report)]
        try:
            proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=900)
        except (OSError, subprocess.SubprocessError) as e:
            raise ToolError(f"gitleaks gagal dijalankan: {e}") from None
        if proc.returncode not in (0, 1):
            # Keluaran gitleaks tidak diteruskan: pesan galatnya bisa memuat potongan isi berkas.
            raise ToolError(f"gitleaks keluar dengan kode {proc.returncode}")
        try:
            data = json.loads(report.read_text() or "[]")
            return [Finding(d["RuleID"], d["File"], int(d["StartLine"]), (d.get("Commit") or "")[:7]) for d in data]
        except (OSError, ValueError, KeyError, TypeError):
            raise ToolError("laporan gitleaks tidak bisa diurai") from None


def scan_secrets(repo, config=CONFIG):
    """Seluruh riwayat git ditambah perubahan yang di-stage."""
    repo = pathlib.Path(repo)
    history = run_gitleaks(["git", "--config", str(config), "."], cwd=repo)
    staged = run_gitleaks(["git", "--staged", "--config", str(config), "."], cwd=repo)
    return history + staged


def scan_build(bundle, config=CONFIG, min_len=8):
    """Produk build: string cetak dari setiap berkas (termasuk biner) ditulis ke cermin sementara lalu dipindai."""
    bundle = pathlib.Path(bundle)
    if not bundle.is_dir():
        raise ToolError(f"produk build tidak ditemukan: {bundle}")
    printable = re.compile(rb"[\x20-\x7e]{%d,}" % min_len)
    with tempfile.TemporaryDirectory() as tmp:
        mirror = pathlib.Path(tmp)
        for path in sorted(p for p in bundle.rglob("*") if p.is_file() and not p.is_symlink()):
            runs = printable.findall(path.read_bytes())
            if runs:
                target = mirror / (str(path.relative_to(bundle)) + ".txt")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"\n".join(runs) + b"\n")
        found = run_gitleaks(["dir", "--config", str(config), "."], cwd=mirror)
    return [dataclasses.replace(f, file=f.file.removeprefix("./").removesuffix(".txt")) for f in found]


@dataclasses.dataclass(frozen=True)
class GoVuln:
    osv: str
    module: str
    fixed: str
    called: bool  # ada frame jejak yang sampai ke fungsi: kode rentan benar-benar terpanggil


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
            called = any(frame.get("function") for frame in trace)
            prev = vulns.get(finding["osv"])
            vulns[finding["osv"]] = GoVuln(finding["osv"], trace[0]["module"] if trace else "?",
                                           finding.get("fixed_version") or "", called or bool(prev and prev.called))
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


def swift_remote_packages(package_swift, pbxproj):
    """App iOS harus tetap tanpa paket pihak ketiga sampai ada pemindai untuk ekosistem Swift."""
    try:
        found = []
        if ".package(" in pathlib.Path(package_swift).read_text():
            found.append(f"{package_swift}: dependensi .package(")
        if "XCRemoteSwiftPackageReference" in pathlib.Path(pbxproj).read_text():
            found.append(f"{pbxproj}: XCRemoteSwiftPackageReference")
        return found
    except OSError as e:
        raise ToolError(f"berkas proyek Swift tidak terbaca: {e}") from None


def osv_query(payload):
    request = urllib.request.Request(OSV_URL, data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(request, timeout=20) as resp:
        return json.loads(resp.read().decode())


def _requirement_names(path):
    names = []
    for line in pathlib.Path(path).read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line and not line.startswith("-"):
            names.append(re.split(r"[=<>!~\[;\s@]", line, maxsplit=1)[0])
    return names


def python_advisories(requirements, query=osv_query, version_of=importlib.metadata.version):
    """Advisori OSV untuk versi yang terpasang; paket yang tidak terpasang dilewati sebagai informasi."""
    vulnerable, skipped = [], []
    for req in requirements:
        for name in _requirement_names(req):
            try:
                version = version_of(name)
            except importlib.metadata.PackageNotFoundError:
                skipped.append(f"{name} (tidak terpasang)")
                continue
            try:
                resp = query({"package": {"name": name, "ecosystem": "PyPI"}, "version": version})
                ids = [v["id"] for v in resp.get("vulns") or []]
            except (OSError, ValueError, KeyError, TypeError, AttributeError) as e:
                raise ToolError(f"kueri OSV untuk {name} gagal: {e}") from None
            # Halaman berikutnya tidak diambil: halaman pertama yang berisi advisori sudah cukup untuk gagal.
            vulnerable += [f"{name} {version}: {i}" for i in ids]
    return vulnerable, skipped


def scan_deps(repo, out, govulncheck=run_govulncheck, query=osv_query, version_of=importlib.metadata.version):
    """Mengembalikan True bila ada temuan dependensi."""
    vulns = parse_govulncheck(govulncheck(repo / "backend"))
    called = [v for v in vulns if v.called]
    print(f"dependensi Go (govulncheck): {len(called)} kerentanan terpanggil", file=out)
    for v in vulns:
        prefix = "  " if v.called else "  informasi: "
        status = "terpanggil" if v.called else "diimpor tetapi tidak terpanggil"
        print(f"{prefix}{v.osv}  {v.module}  {status}; perbaikan: {v.fixed or 'belum ada'}", file=out)
    remote = swift_remote_packages(repo / "Packages/Package.swift", repo / "Anastrophe.xcodeproj/project.pbxproj")
    print(f"paket Swift remote: {len(remote)}", file=out)
    for r in remote:
        print(f"  {r}", file=out)
    vulnerable, skipped = python_advisories(sorted(repo.glob("scripts/*/requirements.txt")), query, version_of)
    print(f"dependensi Python (OSV): {len(vulnerable)} advisori", file=out)
    for v in vulnerable:
        print(f"  {v}", file=out)
    for s in skipped:
        print(f"  informasi: {s} dilewati", file=out)
    return bool(called or remote or vulnerable)


def _report(title, findings, out):
    print(f"{title}: {len(findings)} temuan", file=out)
    for f in findings:
        where = f"commit {f.commit}" if f.commit else "di luar commit"
        print(f"  {f.rule}  {f.file}:{f.line}  ({where})", file=out)


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
    found = False
    try:
        if args.perintah in (None, "secrets"):
            secrets = scan_secrets(repo, config)
            _report("secret (riwayat + staged)", secrets, out)
            found |= bool(secrets)
        if args.perintah in (None, "deps"):
            found |= scan_deps(repo, out, govulncheck, osv_query, pip_version)
        if bundle is not None:
            built = scan_build(bundle, config)
            _report(f"secret (produk build {bundle.name})", built, out)
            found |= bool(built)
    except ToolError as e:
        print(f"scan.py: {e}", file=err)
        return 2
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
