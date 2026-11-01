"""Test CA lab ANP/1. Jalankan: python3 -I -m unittest discover -s scripts/anp1 -p 'test_*.py'"""
import base64
import datetime
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import lab_ca  # noqa: E402
from cryptography.hazmat.primitives.asymmetric import ec  # noqa: E402

PUBKEY = ec.generate_private_key(ec.SECP256R1()).public_key()


def x963(public_key) -> bytes:
    from cryptography.hazmat.primitives import serialization
    return public_key.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)


class LabCATests(unittest.TestCase):
    def setUp(self):
        self.lab = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.lab, ignore_errors=True)  # direktori berisi kunci CA uji
        self.run_cli("init", "--site-id", "0102030405060708")

    def run_cli(self, *args):
        result = subprocess.run([sys.executable, "-I", str(HERE / "lab_ca.py"), "--lab-dir", str(self.lab), *args], capture_output=True, text=True, check=True)
        return result.stdout

    def issue(self, channel="ble"):
        return json.loads(self.run_cli("issue", "--cred-id", "c1" * 16, "--pubkey", x963(PUBKEY).hex(), "--channel", channel))

    def test_kunci_lab_tidak_tercetak(self):
        site = json.loads((self.lab / "site.json").read_text())
        self.assertEqual(len(bytes.fromhex(site["group_id"])), 8)
        output = self.run_cli("issue", "--cred-id", "c1" * 16, "--pubkey", x963(PUBKEY).hex())
        self.assertNotIn("PRIVATE", output)
        self.assertNotIn("BEGIN", output)

    def test_init_tidak_menimpa_site_yang_ada(self):
        before = (self.lab / "site.json").read_text()
        result = subprocess.run([sys.executable, "-I", str(HERE / "lab_ca.py"), "--lab-dir", str(self.lab), "init", "--site-id", "0102030405060708"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.lab / "site.json").read_text(), before)
        self.assertEqual((self.lab / "site.json").stat().st_mode & 0o777, 0o600)

    def test_sertifikat_maks_200_byte(self):
        certificate = base64.b64decode(self.issue()["certificate"])
        self.assertLessEqual(len(certificate), 200)

    def test_cose_sign1_terverifikasi_dengan_kunci_ca(self):
        certificate = base64.b64decode(self.issue()["certificate"])
        payload = lab_ca.verify_certificate(certificate, lab_ca.load_site(self.lab)["ca_public"])
        self.assertEqual(payload[1], bytes.fromhex("c1" * 16))
        self.assertEqual(payload[2], bytes.fromhex("0102030405060708"))
        self.assertEqual(payload[3], x963(PUBKEY))
        self.assertEqual(payload[5], lab_ca.CHANNEL_CODES["ble"])

    def test_sertifikat_dimodifikasi_ditolak(self):
        certificate = bytearray(base64.b64decode(self.issue()["certificate"]))
        certificate[20] ^= 0x01
        with self.assertRaises(Exception):
            lab_ca.verify_certificate(bytes(certificate), lab_ca.load_site(self.lab)["ca_public"])

    def test_json_provisioned_credential(self):
        issued = self.issue(channel="nfcHCE")
        self.assertEqual(base64.b64decode(issued["credential_id"]), bytes.fromhex("c1" * 16))
        self.assertEqual(issued["channel"], "nfcHCE")
        not_after = datetime.datetime.fromisoformat(issued["not_after"].replace("Z", "+00:00"))
        days = (not_after - datetime.datetime.now(datetime.timezone.utc)).total_seconds() / 86400
        self.assertAlmostEqual(days, 7, delta=0.01)
        site = json.loads((self.lab / "site.json").read_text())
        keys = issued["group_keys"][site["group_id"]]
        self.assertEqual([len(base64.b64decode(k)) for k in keys], [65])

    def test_cbor_round_trip(self):
        value = {1: b"\x00\x01", 2: 23, 3: 24, 4: 65536, 5: -7, 6: "Lab", 7: [1, {8: b""}]}
        self.assertEqual(lab_ca.cbor_decode(lab_ca.cbor_encode(value)), value)


if __name__ == "__main__":
    unittest.main()
