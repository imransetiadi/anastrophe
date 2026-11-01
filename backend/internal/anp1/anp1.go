// Package anp1 berisi primitif kriptografi ANP/1 (SDD §7.6) untuk sisi server:
// menerbitkan sertifikat, memverifikasi test vector bersama, dan alat uji reader.
package anp1

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/hkdf"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"math/big"
)

// Version adalah versi protokol yang masuk transcript.
const Version byte = 1

// Transcript: "ANP1" ‖ version ‖ group_id ‖ r_eph_pub ‖ p_eph_pub ‖ txn_id.
func Transcript(groupID, readerEph, phoneEph, txnID []byte) []byte {
	t := append([]byte("ANP1"), Version)
	t = append(t, groupID...)
	t = append(t, readerEph...)
	t = append(t, phoneEph...)
	return append(t, txnID...)
}

// DeriveKeys: HKDF-SHA256(Z, salt = txn_id, info = "ANP1-KEYS" ‖ group_id, L = 44) → K_pr, K_rp, IV_base.
func DeriveKeys(shared, txnID, groupID []byte) (kPR, kRP, ivBase []byte, err error) {
	okm, err := hkdf.Key(sha256.New, shared, txnID, "ANP1-KEYS"+string(groupID), 44)
	if err != nil {
		return nil, nil, nil, err
	}
	return okm[:16], okm[16:32], okm[32:], nil
}

// Nonce: IV_base XOR seq (seq 64-bit big-endian di 8 byte terakhir).
func Nonce(ivBase []byte, seq uint64) []byte {
	n := append([]byte(nil), ivBase...)
	tail := binary.BigEndian.Uint64(n[len(n)-8:]) ^ seq
	binary.BigEndian.PutUint64(n[len(n)-8:], tail)
	return n
}

// Seal: AES-128-GCM dengan AAD = header APDU; keluaran ciphertext ‖ tag.
func Seal(key, nonce, plaintext, aad []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	return gcm.Seal(nil, nonce, plaintext, aad), nil
}

// PhoneMessage: "ANP1-P" ‖ T ‖ cred_id ‖ counter (big-endian).
func PhoneMessage(transcript, credentialID []byte, counter uint32) []byte {
	m := append([]byte("ANP1-P"), transcript...)
	m = append(m, credentialID...)
	return binary.BigEndian.AppendUint32(m, counter)
}

// ParsePublicKey membaca kunci publik P-256 x963 (65 B) dan menolak titik di luar kurva.
func ParsePublicKey(x963 []byte) (*ecdsa.PublicKey, error) {
	if _, err := ecdh.P256().NewPublicKey(x963); err != nil {
		return nil, errors.New("anp1: kunci publik P-256 tidak valid")
	}
	return &ecdsa.PublicKey{
		Curve: elliptic.P256(),
		X:     new(big.Int).SetBytes(x963[1:33]),
		Y:     new(big.Int).SetBytes(x963[33:65]),
	}, nil
}

// VerifyRaw memverifikasi tanda tangan ECDSA P-256/SHA-256 berformat raw r‖s (64 B).
func VerifyRaw(pub *ecdsa.PublicKey, message, sig64 []byte) bool {
	if len(sig64) != 64 {
		return false
	}
	digest := sha256.Sum256(message)
	return ecdsa.Verify(pub, digest[:], new(big.Int).SetBytes(sig64[:32]), new(big.Int).SetBytes(sig64[32:]))
}
