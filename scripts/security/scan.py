#!/usr/bin/env python3
"""Pemindaian secret dan dependensi Anastrophe (TC-SEC-11, ADR-0056).

    python3 scripts/security/scan.py                    # secret (riwayat + staged)
    python3 scripts/security/scan.py --build <App.app>  # ditambah produk build
    python3 scripts/security/scan.py secrets | build <App.app>

Exit 0 bersih, 1 ada temuan, 2 alat tidak ada atau gagal, atau keluarannya tidak bisa diurai.
Nilai secret tidak pernah dicetak: gitleaks selalu dijalankan dengan --redact, dan laporan hanya memuat
aturan, berkas, baris, serta commit.
"""
import argparse
import dataclasses
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONFIG = ROOT / ".gitleaks.toml"
MIN_GITLEAKS = (8, 30)


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


def _report(title, findings, out):
    print(f"{title}: {len(findings)} temuan", file=out)
    for f in findings:
        where = f"commit {f.commit}" if f.commit else "di luar commit"
        print(f"  {f.rule}  {f.file}:{f.line}  ({where})", file=out)


def main(argv=None, out=sys.stdout, err=sys.stderr):
    parser = argparse.ArgumentParser(prog="scan.py", description="Pemindaian secret dan dependensi (TC-SEC-11).")
    parser.add_argument("perintah", nargs="?", choices=["secrets", "build"], help="tanpa perintah: secrets")
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
