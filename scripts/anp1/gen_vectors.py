#!/usr/bin/env python3
"""Test vector ANP/1 v1 (TC-PROTO-01, SDD §7.6/§7.11).

Implementasi independen dari kode Swift: hanya memakai pustaka `cryptography`.
Skalar privat diturunkan dari label tetap dan ECDSA memakai RFC 6979, sehingga
menjalankan ulang skrip selalu menghasilkan JSON yang identik.

Pemakaian: python3 scripts/anp1/gen_vectors.py > Packages/Tests/ANCryptoTests/Resources/anp1-v1.json
"""
import hashlib
import json

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

P256_ORDER = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
ECDSA = ec.ECDSA(hashes.SHA256(), deterministic_signing=True)


def scalar(label: str) -> bytes:
    """Skalar P-256 deterministik dalam [1, n-1] dari sebuah label."""
    value = int.from_bytes(hashlib.sha256(f"anp1-v1/{label}".encode()).digest(), "big") % (P256_ORDER - 1) + 1
    return value.to_bytes(32, "big")


def private_key(raw: bytes) -> ec.EllipticCurvePrivateKey:
    return ec.derive_private_key(int.from_bytes(raw, "big"), ec.SECP256R1())


def x963(key: ec.EllipticCurvePrivateKey) -> bytes:
    return key.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)


def raw_signature(key: ec.EllipticCurvePrivateKey, message: bytes) -> bytes:
    r, s = decode_dss_signature(key.sign(message, ECDSA))
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")


def tlv(tag: int, value: bytes) -> bytes:
    assert len(value) < 0x80
    return bytes([tag, len(value)]) + value


def nonce(iv_base: bytes, seq: int) -> bytes:
    return iv_base[:4] + (int.from_bytes(iv_base[4:], "big") ^ seq).to_bytes(8, "big")


def apdu(header: bytes, data: bytes = b"") -> bytes:
    return header + (bytes([len(data)]) + data if data else b"")


def main() -> None:
    group_priv, reader_eph_priv = scalar("group"), scalar("reader-ephemeral")
    phone_eph_priv, cred_priv = scalar("phone-ephemeral"), scalar("credential")
    group, reader_eph, phone_eph, cred = map(private_key, (group_priv, reader_eph_priv, phone_eph_priv, cred_priv))

    group_id = bytes.fromhex("A1A2A3A4A5A6A7A8")
    txn_id = bytes(range(16))
    cred_id = bytes(range(0xC0, 0xD0))
    counter = 7
    certificate = bytes((i * 7 + 3) & 0xFF for i in range(150))
    aid = bytes.fromhex("F0414E415354524F01")

    transcript = b"ANP1" + bytes([1]) + group_id + x963(reader_eph) + x963(phone_eph) + txn_id
    sig_r = raw_signature(group, b"ANP1-R" + transcript)
    counter_be = counter.to_bytes(4, "big")
    sig_p = raw_signature(cred, b"ANP1-P" + transcript + cred_id + counter_be)

    shared = phone_eph.exchange(ec.ECDH(), reader_eph.public_key())
    okm = HKDF(algorithm=hashes.SHA256(), length=44, salt=txn_id, info=b"ANP1-KEYS" + group_id).derive(shared)
    k_pr, k_rp, iv_base = okm[:16], okm[16:32], okm[32:]

    cert_hash = hashlib.sha256(certificate).digest()[:8]
    auth1_plaintext = tlv(0xE1, cred_id) + tlv(0xE2, counter_be) + tlv(0xE3, cert_hash) + tlv(0xE4, sig_p)
    auth1_ciphertext = AESGCM(k_pr).encrypt(nonce(iv_base, 0), auth1_plaintext, bytes.fromhex("80120000"))
    cert_ciphertext = AESGCM(k_pr).encrypt(nonce(iv_base, 1), certificate, bytes.fromhex("80140000"))
    result_plaintext = tlv(0xF1, b"\x00") + tlv(0xF2, b"\x00")
    result_ciphertext = AESGCM(k_rp).encrypt(nonce(iv_base, 0), result_plaintext, bytes.fromhex("80160000"))

    auth0_data = tlv(0xC1, group_id) + tlv(0xC2, x963(reader_eph)) + tlv(0xC3, txn_id)
    apdus = {
        "select_command": apdu(bytes.fromhex("00A40400"), aid),
        "auth0_command": apdu(bytes.fromhex("80100000"), auth0_data),
        "auth0_response": tlv(0xD1, x963(phone_eph)) + b"\x90\x00",
        "auth1_command": apdu(bytes.fromhex("80120000"), tlv(0xC4, sig_r)),
        "auth1_response": auth1_ciphertext + b"\x90\x00",
        "get_cert_command": bytes.fromhex("80140000"),
        "get_cert_response": cert_ciphertext + b"\x90\x00",
        "result_command": apdu(bytes.fromhex("80160000"), result_ciphertext),
    }

    vector = {
        "name": "ANP/1 v1 shared test vector",
        "spec": "docs/SDD.md §7.4–§7.6, §7.11; QA TC-PROTO-01",
        "group_priv": group_priv.hex(),
        "group_id": group_id.hex(),
        "reader_eph_priv": reader_eph_priv.hex(),
        "phone_eph_priv": phone_eph_priv.hex(),
        "cred_priv": cred_priv.hex(),
        "txn_id": txn_id.hex(),
        "cred_id": cred_id.hex(),
        "counter": counter,
        "certificate": certificate.hex(),
        "sig_r": sig_r.hex(),
        "sig_p": sig_p.hex(),
        "expected": {
            "transcript": transcript.hex(),
            "k_pr": k_pr.hex(),
            "k_rp": k_rp.hex(),
            "iv_base": iv_base.hex(),
            "cert_hash": cert_hash.hex(),
            "auth1_plaintext": auth1_plaintext.hex(),
            "auth1_ciphertext": auth1_ciphertext.hex(),
            "cert_ciphertext": cert_ciphertext.hex(),
            "result_plaintext_granted": result_plaintext.hex(),
            "result_ciphertext_granted": result_ciphertext.hex(),
            "apdus": {name: value.hex() for name, value in apdus.items()},
        },
    }
    assert all(len(value) < 255 for value in apdus.values()), "setiap APDU harus < 255 B"
    print(json.dumps(vector, indent=2))


if __name__ == "__main__":
    main()
