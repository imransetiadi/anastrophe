"""Test pembungkus pemindaian secret dan dependensi (TC-SEC-11, ADR-0056).

Token palsu dirakit saat runtime, jadi repo sendiri tidak memuat secret literal.
Jalankan: python3 -m unittest discover -s scripts/security -v
"""
import http.client
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
        # Header Mach-O 64-bit: gitleaks dir melewati biner Mach-O, jadi token ini hanya terlihat lewat cermin string.
        macho = b"\xcf\xfa\xed\xfe" + bytes(28)
        self.repo.tulis("App.app/App", macho + os.urandom(256) + b"\x00" + token.encode() + b"\x00" + os.urandom(256))
        self.repo.tulis("App.app/Info.plist", "<plist version=\"1.0\"><dict/></plist>\n")
        self.assertEqual(self.pasangan(scan.scan_build(bundle, CONFIG)), [("github-pat", "App")])
        out, err = io.StringIO(), io.StringIO()
        self.assertEqual(scan.main(["build", str(bundle)], out=out, err=err), 1)
        self.assertNotIn(token, out.getvalue() + err.getvalue())
        self.assertIn("App (string cetak)", out.getvalue())

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

    def test_bukan_repo_git_exit_2(self):
        # Review akhir ADR-0056 (Critical): gitleaks menulis [] dan exit 0 saat git gagal; itu tidak boleh lulus.
        kosong = pathlib.Path(tempfile.mkdtemp(prefix="bukan-repo-"))
        self.addCleanup(shutil.rmtree, kosong, True)
        err = io.StringIO()
        self.assertEqual(scan.main(["secrets", "--repo", str(kosong)], out=io.StringIO(), err=err), 2)
        self.assertIn("repo git", err.getvalue())

    def test_git_menolak_repo_exit_2(self):
        # Kepemilikan berbeda (umum di kontainer CI): git menolak repo, gitleaks diam-diam memindai nol commit.
        self.repo.commit("a.txt", token_palsu() + "\n")
        with mock.patch.dict(os.environ, {"GIT_TEST_ASSUME_DIFFERENT_OWNER": "1"}):
            self.assertEqual(scan.main(["secrets", "--repo", str(self.repo.dir)], out=io.StringIO(), err=io.StringIO()), 2)

    def test_clone_dangkal_exit_2(self):
        # Review akhir (Important): clone --depth 1 hanya memuat commit terakhir; token di commit lama tak terlihat.
        self.repo.commit("README", "awal\n")
        self.repo.commit("a.txt", token_palsu() + "\n")
        self.repo.commit("a.txt", "token sudah dihapus\n")
        dangkal = pathlib.Path(tempfile.mkdtemp(prefix="dangkal-")) / "repo"
        self.addCleanup(shutil.rmtree, dangkal.parent, True)
        subprocess.run(["git", "clone", "-q", "--depth", "1", f"file://{self.repo.dir}", str(dangkal)], check=True, capture_output=True)
        err = io.StringIO()
        self.assertEqual(scan.main(["secrets", "--repo", str(dangkal)], out=io.StringIO(), err=err), 2)
        self.assertIn("dangkal", err.getvalue())

    def test_komentar_gitleaks_allow_tidak_menutupi(self):
        # Review akhir (Important): penekanan hanya lewat allowlist beralasan di .gitleaks.toml.
        self.repo.commit("a.txt", token_palsu() + "  # gitleaks" + ":allow\n")
        self.assertIn(("github-pat", "a.txt"), self.pasangan(scan.scan_secrets(self.repo.dir, CONFIG)))

    def test_gitleaksignore_ditolak(self):
        self.repo.commit("a.txt", token_palsu() + "\n")
        self.repo.tulis(".gitleaksignore", "apa pun\n")
        err = io.StringIO()
        self.assertEqual(scan.main(["secrets", "--repo", str(self.repo.dir)], out=io.StringIO(), err=err), 2)
        self.assertIn(".gitleaksignore", err.getvalue())

    def test_build_p12_terdeteksi(self):
        # Review akhir (Important): aturan berbasis path (pkcs12-file) hilang bila hanya cermin .txt yang dipindai.
        self.repo.tulis("App.app/App", b"\x00" * 64)
        self.repo.tulis("App.app/kunci.p12", os.urandom(512))
        self.assertIn(("pkcs12-file", "kunci.p12"), self.pasangan(scan.scan_build(self.repo.dir / "App.app", CONFIG)))

    def test_build_json_bertab_terdeteksi(self):
        self.repo.tulis("App.app/config.json", '{"key":\t"' + acak(32) + '"}\n')
        temuan = scan.scan_build(self.repo.dir / "App.app", CONFIG)
        self.assertIn("config.json", [f.file for f in temuan])

    def test_build_biner_bertab_terdeteksi(self):
        # Biner Mach-O hanya terlihat lewat cermin; tab di antara kunci dan nilai tidak boleh memutus string cetak.
        isi = b'{"key":\t"' + acak(32).encode() + b'"}'
        self.repo.tulis("App.app/App", b"\xcf\xfa\xed\xfe" + bytes(28) + b"\x00" + isi + b"\x00")
        self.assertIn("App", [f.file for f in scan.scan_build(self.repo.dir / "App.app", CONFIG)])

    def test_build_tanpa_duplikat(self):
        # Berkas teks ditemukan pemindaian langsung dan cermin string; laporan memuatnya sekali.
        self.repo.tulis("App.app/catatan.txt", token_palsu() + "\n")
        self.assertEqual(self.pasangan(scan.scan_build(self.repo.dir / "App.app", CONFIG)), [("github-pat", "catatan.txt")])

    def test_gitleaksignore_di_bundle_ditolak(self):
        self.repo.tulis("App.app/App", b"\x00" * 64)
        self.repo.tulis("App.app/.gitleaksignore", "apa pun\n")
        with self.assertRaises(scan.ToolError):
            scan.scan_build(self.repo.dir / "App.app", CONFIG)

    @unittest.skipIf(os.geteuid() == 0, "root bisa membaca berkas chmod 000")
    def test_build_berkas_tak_terbaca_exit_2(self):
        self.repo.tulis("App.app/App", b"\x00" * 64)
        rahasia = self.repo.tulis("App.app/terkunci.bin", b"isi")
        rahasia.chmod(0)
        self.addCleanup(rahasia.chmod, 0o644)
        self.assertEqual(scan.main(["build", str(self.repo.dir / "App.app")], out=io.StringIO(), err=io.StringIO()), 2)

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

    def test_gitleaks_stderr_dianggap_gagal(self):
        # Perilaku nyata gitleaks 8.30 saat git gagal: galat di stderr, laporan [], exit 0.
        skrip = ('while [ $# -gt 0 ]; do if [ "$1" = --report-path ]; then echo "[]" > "$2"; fi; shift; done\n'
                 'echo "ERR [git] fatal: detected dubious ownership" >&2\nexit 0\n')
        with gitleaks_palsu(self, skrip):
            self.assertEqual(scan.main(["secrets", "--repo", str(ROOT)], out=io.StringIO(), err=io.StringIO()), 2)

    def test_laporan_kosong_atau_tidak_konsisten_exit_2(self):
        kasus = {"laporan kosong": (": > \"$2\"", 0), "exit temuan tanpa temuan": ('echo "[]" > "$2"', 99)}
        for nama, (tulis, kode) in kasus.items():
            with self.subTest(nama):
                skrip = f'while [ $# -gt 0 ]; do if [ "$1" = --report-path ]; then {tulis}; fi; shift; done\nexit {kode}\n'
                with gitleaks_palsu(self, skrip):
                    self.assertEqual(scan.main(["secrets", "--repo", str(ROOT)], out=io.StringIO(), err=io.StringIO()), 2)

    def test_laporan_gitleaks_rusak_exit_2(self):
        # Exit temuan (--exit-code 99) tetapi laporan bukan JSON: tidak boleh dianggap bersih.
        skrip = 'while [ $# -gt 0 ]; do if [ "$1" = --report-path ]; then echo rusak > "$2"; fi; shift; done\nexit 99\n'
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
            scan.GoVuln(osv="GO-2099-0001", module="golang.org/x/contoh", fixed="v0.99.0", level="fungsi")])
        # Urutan sebaliknya: temuan tingkat modul untuk OSV yang sama tidak menurunkan status terpanggil, dan modul
        # serta versi perbaikan yang dilaporkan tetap milik temuan terpanggil (review akhir ADR-0056).
        terbalik = aliran_govulncheck(TERPANGGIL, MODUL_SAJA | {"osv": "GO-2099-0001"})
        hasil = scan.parse_govulncheck(terbalik)[0]
        self.assertEqual((hasil.called, hasil.module, hasil.fixed), (True, "golang.org/x/contoh", "v0.99.0"))
        kode, out, _ = self.jalankan(RepoDependensi(self), stream=stream)
        self.assertEqual(kode, 1)
        self.assertIn("GO-2099-0001", out)

    def test_govulncheck_modul_saja_info(self):
        stream = aliran_govulncheck(MODUL_SAJA)
        self.assertEqual(scan.parse_govulncheck(stream), [
            scan.GoVuln(osv="GO-2099-0002", module="golang.org/x/lain", fixed="v1.2.3", level="modul")])
        kode, out, _ = self.jalankan(RepoDependensi(self), stream=stream)
        self.assertEqual(kode, 0)
        self.assertIn("informasi", out)
        self.assertIn("GO-2099-0002", out)
        # Tingkat modul berarti modul ada di graf tetapi paketnya tidak diimpor; tingkat paket berarti diimpor.
        self.assertIn("di graf modul, paket tidak diimpor", out)
        paket = {"osv": "GO-2099-0003", "fixed_version": "v2.0.0", "trace": [
            {"module": "golang.org/x/paket", "version": "v1.0.0", "package": "golang.org/x/paket/p"}]}
        _, out_paket, _ = self.jalankan(RepoDependensi(self), stream=aliran_govulncheck(paket))
        self.assertIn("diimpor, fungsi rentan tidak terpanggil", out_paket)

    def test_govulncheck_json_rusak_exit_2(self):
        for stream in ("{rusak", "", '{"progress": {"message": "tanpa config"}}'):
            with self.subTest(stream=stream):
                kode, _, err = self.jalankan(RepoDependensi(self), stream=stream)
                self.assertEqual(kode, 2)
                self.assertIn("govulncheck", err)

    def test_paket_swift_remote_gagal(self):
        repo = RepoDependensi(self, pbxproj="/* XCRemoteSwiftPackageReference \"contoh\" */\n")
        self.assertTrue(scan.swift_packages_remote(repo.dir))
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

    def test_osv_halaman_berikutnya_diikuti(self):
        # Review akhir (Important): OSV bisa mengembalikan hanya next_page_token; itu bukan "tanpa advisori".
        kiriman = []

        def query(payload):
            kiriman.append(payload)
            return {"next_page_token": "hal-2"} if len(kiriman) == 1 else {"vulns": [{"id": "GHSA-uji-0002"}]}
        kode, out, _ = self.jalankan(RepoDependensi(self), query=query)
        self.assertEqual(kode, 1)
        self.assertIn("GHSA-uji-0002", out)
        self.assertEqual(kiriman[1], {"package": {"name": "contoh", "ecosystem": "PyPI"}, "version": "1.0.0", "page_token": "hal-2"})

    def test_osv_halaman_tanpa_akhir_exit_2(self):
        kode, _, err = self.jalankan(RepoDependensi(self), query=lambda payload: {"next_page_token": "lagi"})
        self.assertEqual(kode, 2)
        self.assertIn("OSV", err)

    def test_osv_respons_terpotong_exit_2(self):
        def terpotong(payload):
            raise http.client.IncompleteRead(b"")
        kode, _, err = self.jalankan(RepoDependensi(self), query=terpotong)
        self.assertEqual(kode, 2)
        self.assertIn("OSV", err)

    @unittest.skipIf(os.geteuid() == 0, "root bisa membaca berkas chmod 000")
    def test_requirements_tak_terbaca_exit_2(self):
        repo = RepoDependensi(self)
        req = repo.dir / "scripts/alat/requirements.txt"
        req.chmod(0)
        self.addCleanup(req.chmod, 0o644)
        self.assertEqual(self.jalankan(repo)[0], 2)

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

    def test_requirements_mengikuti_dash_r(self):
        # Minor review akhir ADR-0056: baris "-r lain.txt" sebelumnya dibuang sebagai opsi, bukan diikuti,
        # jadi paket di berkas yang di-include lewat -r tidak pernah diperiksa OSV.
        repo = RepoDependensi(self)
        req = repo.dir / "scripts/alat/requirements.txt"
        req.write_text("-r dasar.txt\nekstra==2.*\n")
        (repo.dir / "scripts/alat/dasar.txt").write_text("contoh==1.*\n")
        names = scan._requirement_names(req)
        self.assertEqual(sorted(names), ["contoh", "ekstra"])
        # -r berantai (dasar.txt sendiri meng-include lagi) juga diikuti, dan siklus tidak membuat tak terhingga.
        (repo.dir / "scripts/alat/dasar.txt").write_text("-r dasar.txt\ncontoh==1.*\n")
        self.assertEqual(sorted(scan._requirement_names(req)), ["contoh", "ekstra"])

    def test_package_swift_lain_ikut_diperiksa(self):
        # Minor review akhir ADR-0056: hanya Packages/Package.swift yang diperiksa, jadi paket Swift lokal lain
        # dengan dependensi remote (mis. target lab terpisah) lolos tanpa terdeteksi.
        repo = RepoDependensi(self)
        (repo.dir / "Alat").mkdir()
        (repo.dir / "Alat/Package.swift").write_text(
            "let package = Package(dependencies: [.package(url: \"https://contoh.invalid/x\", from: \"1.0.0\")])\n")
        remote = scan.swift_packages_remote(repo.dir)
        self.assertTrue(any("Alat/Package.swift" in r for r in remote))
        kode, out, _ = self.jalankan(repo)
        self.assertEqual(kode, 1)
        self.assertIn("Alat/Package.swift", out)

    def test_satu_pemeriksaan_gagal_tidak_menghentikan_sisanya(self):
        # Minor review akhir ADR-0056: sebelumnya satu ToolError di bagian mana pun (mis. secrets) langsung
        # exit 2 tanpa menjalankan bagian lain (deps), menyembunyikan temuan nyata yang seharusnya tetap
        # dilaporkan. Setiap bagian (secrets, deps, build) wajib berjalan dan melaporkan hasilnya sendiri.
        repo = RepoDependensi(self, pbxproj="/* XCRemoteSwiftPackageReference \"contoh\" */\n")
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(scan, "scan_secrets", side_effect=scan.ToolError("gitleaks tidak ditemukan")):
            kode = scan.main(["--repo", str(repo.dir)], out=out, err=err,
                             govulncheck=lambda backend: aliran_govulncheck(), osv_query=lambda payload: {},
                             pip_version=versi_contoh)
        self.assertEqual(kode, 2)
        self.assertIn("gitleaks tidak ditemukan", err.getvalue())
        # deps tetap jalan dan temuannya tetap dilaporkan walau secrets gagal.
        out_value = out.getvalue()
        self.assertIn("govulncheck", out_value)
        self.assertIn("XCRemoteSwiftPackageReference", out_value)

    def test_osv_alias_tidak_dicetak_dobel(self):
        # Minor review akhir ADR-0056: satu kerentanan bisa dikembalikan OSV sebagai dua id (mis. GHSA dan
        # PYSEC) yang saling menjadi alias; tanpa pengelompokan, keduanya tercetak sebagai dua advisori.
        resp = {"vulns": [
            {"id": "GHSA-uji-0001", "aliases": ["PYSEC-2099-1"]},
            {"id": "PYSEC-2099-1", "aliases": ["GHSA-uji-0001"]},
        ]}
        kode, out, _ = self.jalankan(RepoDependensi(self), query=lambda payload: resp)
        self.assertEqual(kode, 1)
        self.assertEqual(out.count("GHSA-uji-0001") + out.count("PYSEC-2099-1"), 1)

    def test_osv_alias_berbeda_tetap_dua(self):
        resp = {"vulns": [{"id": "GHSA-uji-0002"}, {"id": "GHSA-uji-0003"}]}
        kode, out, _ = self.jalankan(RepoDependensi(self), query=lambda payload: resp)
        self.assertEqual(kode, 1)
        self.assertIn("GHSA-uji-0002", out)
        self.assertIn("GHSA-uji-0003", out)


if __name__ == "__main__":
    unittest.main()
