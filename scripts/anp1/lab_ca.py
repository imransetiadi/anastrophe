#!/usr/bin/env python3
"""CA lab ANP/1: menerbitkan kredensial uji untuk M1 tanpa backend (rencana R1 Task 9).

HANYA untuk lab. Kunci Site CA dan reader group disimpan di `--lab-dir`
(default `scripts/anp1/.lab/`, di-ignore git) dan tidak pernah dicetak.

  python3 scripts/anp1/lab_ca.py init --site-id 0102030405060708
  python3 scripts/anp1/lab_ca.py issue --cred-id <hex16> --pubkey <hex65> --channel ble

`issue` mencetak JSON `ProvisionedCredential` (Packages/Sources/ANNetworking).
`CredentialCert` = COSE_Sign1 (RFC 9052, ES256) atas payload CBOR (SDD §7.3):
{1: cred_id, 2: site_id, 3: pubkey, 4: zones (bitmap), 5: channel, 6: not_before, 7: not_after}.
"""
import argparse
import base64
import datetime
import json
import os
import pathlib
import struct

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature, encode_dss_signature

DEFAULT_LAB_DIR = pathlib.Path(__file__).resolve().parent / ".lab"
CHANNEL_CODES = {"nfcHCE": 1, "ble": 2, "nfcSE": 3}
COSE_PROTECTED = {1: -7}  # alg: ES256
COSE_SIGN1_TAG = 18

# --- CBOR minimal (RFC 8949): uint, nint, bstr, tstr, array, map, tag ---------


def _head(major: int, value: int) -> bytes:
    if value < 24:
        return bytes([major << 5 | value])
    for info, fmt in ((24, ">B"), (25, ">H"), (26, ">I"), (27, ">Q")):
        if value < 1 << (8 * struct.calcsize(fmt)):
            return bytes([major << 5 | info]) + struct.pack(fmt, value)
    raise ValueError("nilai terlalu besar")


def cbor_encode(value) -> bytes:
    if isinstance(value, bool) or value is None:
        raise TypeError("tidak didukung")
    if isinstance(value, int):
        return _head(0, value) if value >= 0 else _head(1, -1 - value)
    if isinstance(value, bytes):
        return _head(2, len(value)) + value
    if isinstance(value, str):
        data = value.encode()
        return _head(3, len(data)) + data
    if isinstance(value, list):
        return _head(4, len(value)) + b"".join(cbor_encode(v) for v in value)
    if isinstance(value, dict):
        # Kunci int diurutkan agar encoding deterministik.
        return _head(5, len(value)) + b"".join(cbor_encode(k) + cbor_encode(value[k]) for k in sorted(value))
    raise TypeError(f"tidak didukung: {type(value)}")


def cbor_encode_tagged(tag: int, value) -> bytes:
    return _head(6, tag) + cbor_encode(value)


def _decode(data: bytes, i: int):
    major, info = data[i] >> 5, data[i] & 0x1F
    i += 1
    if info < 24:
        arg = info
    else:
        size = {24: 1, 25: 2, 26: 4, 27: 8}[info]
        arg = int.from_bytes(data[i:i + size], "big")
        i += size
    if major == 0:
        return arg, i
    if major == 1:
        return -1 - arg, i
    if major in (2, 3):
        raw = data[i:i + arg]
        if len(raw) != arg:
            raise ValueError("CBOR terpotong")
        return (raw if major == 2 else raw.decode()), i + arg
    if major == 4:
        items = []
        for _ in range(arg):
            item, i = _decode(data, i)
            items.append(item)
        return items, i
    if major == 5:
        result = {}
        for _ in range(arg):
            key, i = _decode(data, i)
            result[key], i = _decode(data, i)
        return result, i
    if major == 6:
        value, i = _decode(data, i)
        return ("tag", arg, value), i
    raise ValueError("CBOR tidak didukung")


def cbor_decode(data: bytes):
    value, end = _decode(data, 0)
    if end != len(data):
        raise ValueError("sisa byte setelah CBOR")
    return value


# --- COSE_Sign1 -----------------------------------------------------------------


def _sig_structure(protected: bytes, payload: bytes) -> bytes:
    return cbor_encode(["Signature1", protected, b"", payload])


def sign_certificate(ca_private: ec.EllipticCurvePrivateKey, payload: dict) -> bytes:
    protected, body = cbor_encode(COSE_PROTECTED), cbor_encode(payload)
    r, s = decode_dss_signature(ca_private.sign(_sig_structure(protected, body), ec.ECDSA(hashes.SHA256())))
    signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return cbor_encode_tagged(COSE_SIGN1_TAG, [protected, {}, body, signature])


def verify_certificate(certificate: bytes, ca_public: ec.EllipticCurvePublicKey) -> dict:
    """Mengembalikan payload bila tanda tangan CA valid; selain itu melempar exception."""
    tag, number, (protected, _unprotected, body, signature) = cbor_decode(certificate)
    if tag != "tag" or number != COSE_SIGN1_TAG or cbor_decode(protected) != COSE_PROTECTED:
        raise ValueError("bukan COSE_Sign1 ES256")
    der = encode_dss_signature(int.from_bytes(signature[:32], "big"), int.from_bytes(signature[32:], "big"))
    ca_public.verify(der, _sig_structure(protected, body), ec.ECDSA(hashes.SHA256()))
    return cbor_decode(body)


# --- Penyimpanan lab ------------------------------------------------------------


def _pem(key: ec.EllipticCurvePrivateKey) -> str:
    return key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()


def _x963(public_key: ec.EllipticCurvePublicKey) -> bytes:
    return public_key.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)


def load_site(lab_dir: pathlib.Path) -> dict:
    site = json.loads((lab_dir / "site.json").read_text())
    ca = serialization.load_pem_private_key(site["ca_private_pem"].encode(), password=None)
    group = serialization.load_pem_private_key(site["group_private_pem"].encode(), password=None)
    return {**site, "ca_private": ca, "ca_public": ca.public_key(), "group_public": group.public_key()}


def cmd_init(args) -> None:
    args.lab_dir.mkdir(parents=True, exist_ok=True)
    path = args.lab_dir / "site.json"
    if path.exists() and not args.force:
        raise SystemExit(f"{path} sudah ada; pakai --force untuk mengganti CA lab (kredensial lama tidak berlaku lagi).")
    site = {
        "site_id": bytes.fromhex(args.site_id).hex(),
        "group_id": os.urandom(8).hex(),
        "ca_private_pem": _pem(ec.generate_private_key(ec.SECP256R1())),
        "group_private_pem": _pem(ec.generate_private_key(ec.SECP256R1())),
    }
    # Izin 0600 sejak file dibuat: kunci CA tidak pernah terbaca pengguna lain.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(json.dumps(site, indent=2))
    os.chmod(path, 0o600)
    print(f"Site lab dibuat di {path} (group_id {site['group_id']}).")


def cmd_issue(args) -> None:
    site = load_site(args.lab_dir)
    cred_id, pubkey = bytes.fromhex(args.cred_id), bytes.fromhex(args.pubkey)
    if len(cred_id) != 16 or len(pubkey) != 65 or pubkey[0] != 0x04:
        raise SystemExit("cred-id harus 16 B dan pubkey x963 65 B")
    ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), pubkey)  # validasi titik kurva
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    not_after = now + datetime.timedelta(days=args.days)
    payload = {
        1: cred_id,
        2: bytes.fromhex(site["site_id"]),
        3: pubkey,
        4: args.zones,
        5: CHANNEL_CODES[args.channel],
        6: int(now.timestamp()),
        7: int(not_after.timestamp()),
    }
    certificate = sign_certificate(site["ca_private"], payload)
    print(json.dumps({
        "credential_id": base64.b64encode(cred_id).decode(),
        "channel": args.channel,
        "certificate": base64.b64encode(certificate).decode(),
        "not_after": not_after.isoformat().replace("+00:00", "Z"),
        "site_name": args.site_name,
        "zones": [args.zone_name],
        "group_keys": {site["group_id"]: [base64.b64encode(_x963(site["group_public"])).decode()]},
    }, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lab-dir", type=pathlib.Path, default=DEFAULT_LAB_DIR)
    sub = parser.add_subparsers(dest="command", required=True)
    init = sub.add_parser("init")
    init.add_argument("--site-id", required=True, help="8 byte hex")
    init.add_argument("--force", action="store_true", help="ganti site.json yang sudah ada")
    init.set_defaults(func=cmd_init)
    issue = sub.add_parser("issue")
    issue.add_argument("--cred-id", required=True, help="16 byte hex, dibuat app (LabProvisioning.begin)")
    issue.add_argument("--pubkey", required=True, help="kunci publik x963 65 byte hex")
    issue.add_argument("--channel", choices=sorted(CHANNEL_CODES), default="ble")
    issue.add_argument("--days", type=int, default=7, help="masa berlaku (ADR-0010)")
    issue.add_argument("--zones", type=int, default=1, help="bitmap zona")
    issue.add_argument("--site-name", default="Gedung Lab")
    issue.add_argument("--zone-name", default="Pintu Lab")
    issue.set_defaults(func=cmd_issue)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
