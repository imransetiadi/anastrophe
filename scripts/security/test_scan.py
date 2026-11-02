"""Test pembungkus pemindaian secret dan dependensi (TC-SEC-11, ADR-0056).

Token palsu dirakit saat runtime, jadi repo sendiri tidak memuat secret literal.
Jalankan: python3 -m unittest discover -s scripts/security -v
"""
import io
import os
import pathlib
import random
import shutil
import string
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import scan  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONFIG = ROOT / ".gitleaks.toml"
VEKTOR = "Packages/Tests/ANCryptoTests/Resources/anp1-v1.json"
ALFANUMERIK = string.ascii_letters + string.digits


def acak(n):
    return "".join(random.SystemRandom().choice(ALFANUMERIK) for _ in range(n))


def token_palsu():
    # Pola aturan bawaan github-pat, dirakit agar tidak ada token literal di berkas ini.
    return "ghp" + "_" + acak(36)


class RepoSementara:
    def __init__(self):
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="scan-uji-"))
        for args in (["init", "-q"], ["config", "user.email", "uji@contoh.invalid"], ["config", "user.name", "Uji"],
                     ["config", "commit.gpgsign", "false"]):
            self.git(*args)

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.dir, check=True, capture_output=True)

    def tulis(self, rel, isi):
        path = self.dir / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(isi, bytes):
            path.write_bytes(isi)
        else:
            path.write_text(isi)
        return path

    def commit(self, rel, isi):
        self.tulis(rel, isi)
        self.git("add", rel)
        self.git("commit", "-q", "-m", "uji")

    def hapus(self):
        shutil.rmtree(self.dir, ignore_errors=True)


@unittest.skipUnless(shutil.which("gitleaks"), "gitleaks tidak terpasang")
class PemindaianSecret(unittest.TestCase):
    def setUp(self):
        self.repo = RepoSementara()
        self.addCleanup(self.repo.hapus)

    def pasangan(self, temuan):
        return [(f.rule, f.file) for f in temuan]

    def test_riwayat_mendeteksi_token_palsu(self):
        self.repo.commit("a.txt", token_palsu() + "\n")
        temuan = scan.scan_secrets(self.repo.dir, CONFIG)
        self.assertEqual(self.pasangan(temuan), [("github-pat", "a.txt")])
        self.assertEqual(len(temuan[0].commit), 7)

    def test_staged_mendeteksi_token_palsu(self):
        self.repo.commit("README", "awal\n")
        self.repo.tulis("b.txt", token_palsu() + "\n")
        self.repo.git("add", "b.txt")
        self.assertIn(("github-pat", "b.txt"), self.pasangan(scan.scan_secrets(self.repo.dir, CONFIG)))

    def test_anotasi_tipe_diabaikan(self):
        self.repo.commit("K.swift", "struct K {\n    let " + "key" + ": P256.Signing.PrivateKey\n}\n")
        self.assertEqual(scan.scan_secrets(self.repo.dir, CONFIG), [])

    def test_kunci_acak_di_swift_tetap_terdeteksi(self):
        # Review Focus 1: allowlist anotasi tipe tidak boleh menutupi nilai acak di berkas Swift.
        self.repo.commit("K.swift", "let api_" + "key = \"" + acak(32) + "\"\n")
        self.assertTrue(scan.scan_secrets(self.repo.dir, CONFIG))

    def test_vektor_hanya_diabaikan_di_path_allowlist(self):
        self.repo.commit(VEKTOR, (ROOT / VEKTOR).read_text())
        self.assertEqual(scan.scan_secrets(self.repo.dir, CONFIG), [])

    def test_vektor_di_path_lain_terdeteksi(self):
        # Allowlist hanya untuk satu berkas: nama sama di direktori lain atau berkas lain di direktori yang sama
        # tetap dipindai.
        for rel in ("lain/anp1-v1.json", "Packages/Tests/ANCryptoTests/Resources/anp1-v2.json"):
            with self.subTest(rel=rel):
                repo = RepoSementara()
                self.addCleanup(repo.hapus)
                repo.commit(rel, (ROOT / VEKTOR).read_text())
                self.assertTrue(scan.scan_secrets(repo.dir, CONFIG))

    def test_laporan_gitleaks_teredaksi_di_disk(self):
        # Review Focus 2: laporan JSON gitleaks di direktori sementara pun tidak memuat nilai secret.
        token = token_palsu()
        self.repo.commit("a.txt", token + "\n")
        simpan = pathlib.Path(tempfile.mkdtemp(prefix="laporan-"))
        self.addCleanup(shutil.rmtree, simpan, True)
        dirs = iter([simpan / "riwayat", simpan / "staged"])

        class Tetap:
            def __enter__(self):
                d = next(dirs)
                d.mkdir()
                return str(d)

            def __exit__(self, *exc):
                return False

        with mock.patch.object(scan.tempfile, "TemporaryDirectory", Tetap):
            self.assertTrue(scan.scan_secrets(self.repo.dir, CONFIG))
        isi = (simpan / "riwayat" / "laporan.json").read_text()
        self.assertIn("github-pat", isi)
        self.assertNotIn(token, isi)

    def test_path_relatif_diselesaikan(self):
        self.repo.commit("a.txt", token_palsu() + "\n")
        # cwd = induk repo (lebih dangkal satu tingkat): path --config relatif yang tidak diselesaikan lalu ditafsirkan
        # dari dalam repo akan meleset. resolve(): di macOS /var adalah symlink ke /private/var.
        kerja = self.repo.dir.resolve().parent
        lama = os.getcwd()
        os.chdir(kerja)
        self.addCleanup(os.chdir, lama)
        args = ["secrets", "--repo", os.path.relpath(self.repo.dir.resolve(), kerja), "--config", os.path.relpath(CONFIG, kerja)]
        self.assertEqual(scan.main(args, out=io.StringIO(), err=io.StringIO()), 1)

    def test_build_biner_terdeteksi_tanpa_nilai(self):
        token = token_palsu()
        bundle = self.repo.dir / "App.app"
        self.repo.tulis("App.app/App", os.urandom(256) + b"\x00" + token.encode() + b"\x00" + os.urandom(256))
        self.repo.tulis("App.app/Info.plist", "<plist version=\"1.0\"><dict/></plist>\n")
        self.assertEqual(self.pasangan(scan.scan_build(bundle, CONFIG)), [("github-pat", "App")])
        out, err = io.StringIO(), io.StringIO()
        self.assertEqual(scan.main(["build", str(bundle)], out=out, err=err), 1)
        self.assertNotIn(token, out.getvalue() + err.getvalue())

    def test_laporan_tanpa_nilai_secret(self):
        token = token_palsu()
        self.repo.commit("a.txt", token + "\n")
        out, err = io.StringIO(), io.StringIO()
        self.assertEqual(scan.main(["secrets", "--repo", str(self.repo.dir)], out=out, err=err), 1)
        teks = out.getvalue() + err.getvalue()
        self.assertIn("github-pat", teks)
        self.assertIn("a.txt", teks)
        self.assertNotIn(token, teks)
        self.assertNotIn(token[4:20], teks)

    def test_repo_bersih_exit_0(self):
        self.repo.commit("README", "tanpa rahasia\n")
        out, err = io.StringIO(), io.StringIO()
        self.assertEqual(scan.main(["secrets", "--repo", str(self.repo.dir)], out=out, err=err), 0)


def gitleaks_palsu(test, skrip_pindai):
    """PATH berisi gitleaks palsu: 'version' menjawab 8.30.1, perintah lain menjalankan skrip_pindai."""
    bindir = pathlib.Path(tempfile.mkdtemp(prefix="gitleaks-palsu-"))
    test.addCleanup(shutil.rmtree, bindir, True)
    palsu = bindir / "gitleaks"
    palsu.write_text("#!/bin/sh\nif [ \"$1\" = version ]; then echo 8.30.1; exit 0; fi\n" + skrip_pindai)
    palsu.chmod(0o755)
    return mock.patch.dict(os.environ, {"PATH": f"{bindir}:/usr/bin:/bin"})


class AlatGitleaks(unittest.TestCase):
    def test_gitleaks_gagal_exit_2(self):
        err = io.StringIO()
        with gitleaks_palsu(self, "exit 2\n"):
            self.assertEqual(scan.main(["secrets", "--repo", str(ROOT)], out=io.StringIO(), err=err), 2)
        self.assertIn("kode 2", err.getvalue())

    def test_laporan_gitleaks_rusak_exit_2(self):
        # Exit 1 (ada temuan) tetapi laporan bukan JSON: tidak boleh dianggap bersih.
        skrip = 'while [ $# -gt 0 ]; do if [ "$1" = --report-path ]; then echo rusak > "$2"; fi; shift; done\nexit 1\n'
        err = io.StringIO()
        with gitleaks_palsu(self, skrip):
            self.assertEqual(scan.main(["secrets", "--repo", str(ROOT)], out=io.StringIO(), err=err), 2)
        self.assertIn("tidak bisa diurai", err.getvalue())

    def test_gitleaks_tidak_ada_exit_2(self):
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, {"PATH": "/nonexistent"}):
            self.assertEqual(scan.main(["secrets", "--repo", str(ROOT)], out=out, err=err), 2)
        self.assertIn("gitleaks", err.getvalue())

    def test_gitleaks_versi_lama_exit_2(self):
        bindir = pathlib.Path(tempfile.mkdtemp(prefix="gitleaks-lama-"))
        self.addCleanup(shutil.rmtree, bindir, True)
        palsu = bindir / "gitleaks"
        palsu.write_text("#!/bin/sh\necho 8.18.0\n")
        palsu.chmod(0o755)
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, {"PATH": str(bindir)}):
            self.assertEqual(scan.main(["secrets", "--repo", str(ROOT)], out=out, err=err), 2)
        self.assertIn("8.30", err.getvalue())


def aliran_govulncheck(*findings):
    """Aliran objek JSON seperti keluaran govulncheck -format json (beberapa objek berurutan, terformat)."""
    import json
    objek = [{"config": {"protocol_version": "v1.0.0", "scanner_name": "govulncheck", "scan_level": "symbol"}}]
    objek += [{"finding": f} for f in findings]
    return "\n".join(json.dumps(o, indent=2) for o in objek) + "\n"


TERPANGGIL = {"osv": "GO-2099-0001", "fixed_version": "v0.99.0", "trace": [
    {"module": "golang.org/x/contoh", "version": "v0.1.0", "package": "golang.org/x/contoh/p", "function": "Rentan"},
    {"module": "github.com/imransetiadi/anastrophe/backend", "package": "x", "function": "Pemanggil"}]}
MODUL_SAJA = {"osv": "GO-2099-0002", "fixed_version": "v1.2.3", "trace": [{"module": "golang.org/x/lain", "version": "v1.0.0"}]}


class RepoDependensi:
    """Repo palsu dengan berkas yang dibaca pemeriksaan dependensi."""

    def __init__(self, test, pbxproj="// tanpa paket remote\n", requirements="contoh==1.*\n"):
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="deps-uji-"))
        test.addCleanup(shutil.rmtree, self.dir, True)
        (self.dir / "backend").mkdir()
        (self.dir / "Packages").mkdir()
        (self.dir / "Packages/Package.swift").write_text("let package = Package(name: \"AnastropheKit\")\n")
        (self.dir / "Anastrophe.xcodeproj").mkdir()
        (self.dir / "Anastrophe.xcodeproj/project.pbxproj").write_text(pbxproj)
        (self.dir / "scripts/alat").mkdir(parents=True)
        (self.dir / "scripts/alat/requirements.txt").write_text(requirements)


def versi_contoh(nama):
    if nama == "contoh":
        return "1.0.0"
    raise scan.importlib.metadata.PackageNotFoundError(nama)


class PemindaianDependensi(unittest.TestCase):
    def jalankan(self, repo, stream=None, query=None, versi=versi_contoh):
        out, err = io.StringIO(), io.StringIO()
        kode = scan.main(["deps", "--repo", str(repo.dir)], out=out, err=err,
                         govulncheck=lambda backend: aliran_govulncheck() if stream is None else stream,
                         osv_query=query or (lambda payload: {}), pip_version=versi)
        return kode, out.getvalue(), err.getvalue()

    def test_govulncheck_terpanggil_gagal(self):
        # Review Focus 4: aliran beberapa objek JSON; temuan yang jejaknya sampai fungsi menggagalkan run.
        stream = aliran_govulncheck(MODUL_SAJA | {"osv": "GO-2099-0001"}, TERPANGGIL)
        self.assertEqual(scan.parse_govulncheck(stream), [
            scan.GoVuln(osv="GO-2099-0001", module="golang.org/x/contoh", fixed="v0.99.0", called=True)])
        # Urutan sebaliknya: temuan tingkat modul untuk OSV yang sama tidak menurunkan status terpanggil.
        terbalik = aliran_govulncheck(TERPANGGIL, MODUL_SAJA | {"osv": "GO-2099-0001"})
        self.assertTrue(scan.parse_govulncheck(terbalik)[0].called)
        kode, out, _ = self.jalankan(RepoDependensi(self), stream=stream)
        self.assertEqual(kode, 1)
        self.assertIn("GO-2099-0001", out)

    def test_govulncheck_modul_saja_info(self):
        stream = aliran_govulncheck(MODUL_SAJA)
        self.assertEqual(scan.parse_govulncheck(stream), [
            scan.GoVuln(osv="GO-2099-0002", module="golang.org/x/lain", fixed="v1.2.3", called=False)])
        kode, out, _ = self.jalankan(RepoDependensi(self), stream=stream)
        self.assertEqual(kode, 0)
        self.assertIn("informasi", out)
        self.assertIn("GO-2099-0002", out)

    def test_govulncheck_json_rusak_exit_2(self):
        for stream in ("{rusak", "", '{"progress": {"message": "tanpa config"}}'):
            with self.subTest(stream=stream):
                kode, _, err = self.jalankan(RepoDependensi(self), stream=stream)
                self.assertEqual(kode, 2)
                self.assertIn("govulncheck", err)

    def test_paket_swift_remote_gagal(self):
        repo = RepoDependensi(self, pbxproj="/* XCRemoteSwiftPackageReference \"contoh\" */\n")
        self.assertTrue(scan.swift_remote_packages(repo.dir / "Packages/Package.swift",
                                                   repo.dir / "Anastrophe.xcodeproj/project.pbxproj"))
        kode, out, _ = self.jalankan(repo)
        self.assertEqual(kode, 1)
        self.assertIn("XCRemoteSwiftPackageReference", out)

    def test_tanpa_temuan_lulus(self):
        kode, out, err = self.jalankan(RepoDependensi(self))
        self.assertEqual((kode, err), (0, ""))
        self.assertIn("govulncheck", out)

    def test_osv_vuln_gagal(self):
        kode, out, _ = self.jalankan(RepoDependensi(self), query=lambda payload: {"vulns": [{"id": "GHSA-uji-0001"}]})
        self.assertEqual(kode, 1)
        self.assertIn("GHSA-uji-0001", out)

    def test_osv_hanya_menerima_nama_dan_versi(self):
        kiriman = []
        self.jalankan(RepoDependensi(self), query=lambda payload: kiriman.append(payload) or {})
        self.assertEqual(kiriman, [{"package": {"name": "contoh", "ecosystem": "PyPI"}, "version": "1.0.0"}])

    def test_osv_jaringan_gagal_exit_2(self):
        def gagal(payload):
            raise OSError("jaringan putus")
        kode, _, err = self.jalankan(RepoDependensi(self), query=gagal)
        self.assertEqual(kode, 2)
        self.assertIn("OSV", err)

    def test_tanpa_perintah_menjalankan_deps(self):
        out = io.StringIO()
        with mock.patch.object(scan, "scan_secrets", return_value=[]):
            kode = scan.main(["--repo", str(RepoDependensi(self).dir)], out=out, err=io.StringIO(),
                             govulncheck=lambda backend: aliran_govulncheck(), osv_query=lambda payload: {},
                             pip_version=versi_contoh)
        self.assertEqual(kode, 0)
        self.assertIn("secret (riwayat + staged): 0 temuan", out.getvalue())
        self.assertIn("dependensi Go (govulncheck)", out.getvalue())

    def test_paket_tidak_terpasang_info(self):
        repo = RepoDependensi(self, requirements="# alat lab\ntidakada>=2\ncontoh==1.*\n")
        kiriman = []
        kode, out, _ = self.jalankan(repo, query=lambda payload: kiriman.append(payload["package"]["name"]) or {})
        self.assertEqual(kode, 0)
        self.assertEqual(kiriman, ["contoh"])
        self.assertIn("informasi: tidakada", out)


if __name__ == "__main__":
    unittest.main()
