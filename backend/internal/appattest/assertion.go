package appattest

import (
	"bytes"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"errors"
	"math/big"
)

// MaxAssertionSize membatasi objek assertion sebelum diurai (assertion iOS 27 ±160 byte, O-AA06).
const MaxAssertionSize = 4 << 10

// Assertion adalah hasil assertion yang lolos verifikasi. Counter disimpan pemanggil sebagai
// previousCounter untuk assertion berikutnya. Ekstensi nil bila tidak ada.
type Assertion struct {
	Counter            uint32
	ValidationCategory *uint32
	BundleVersion      *string
}

// VerifyAssertion menjalankan langkah Apple (O-AA02): RP ID, counter > previousCounter, lalu tanda tangan
// ECDSA P-256 atas digest SHA256(nonce), dengan nonce = SHA256(authenticatorData ‖ SHA256(clientData)).
// Hash ganda ini terbukti dengan assertion iOS 27 nyata (O-AA06). publicKey adalah titik P-256 tak
// terkompresi dari Attestation.PublicKey. Challenge di dalam clientData diperiksa pemanggil.
func (v *Verifier) VerifyAssertion(assertion, clientData, publicKey []byte, previousCounter uint32) (Assertion, error) {
	if len(assertion) > MaxAssertionSize {
		return Assertion{}, invalid("format", errors.New("assertion terlalu besar"))
	}
	obj, err := decodeCBOR(assertion)
	if err != nil {
		return Assertion{}, invalid("format", err)
	}
	m, _ := obj.(map[any]any)
	sig, _ := m["signature"].([]byte)
	auth, _ := m["authenticatorData"].([]byte)
	if len(sig) == 0 || auth == nil {
		return Assertion{}, invalid("format", errors.New("signature atau authenticatorData tidak ada"))
	}
	a, err := parseAssertionAuthData(auth)
	if err != nil {
		return Assertion{}, err
	}
	if !bytes.Equal(a.RPIDHash, v.rpIDHash) {
		return Assertion{}, invalid("rp_id", nil)
	}
	if a.Counter <= previousCounter {
		return Assertion{}, invalid("counter", nil)
	}
	pub, err := p256PublicKey(publicKey)
	if err != nil {
		return Assertion{}, invalid("key", err)
	}
	clientDataHash := sha256.Sum256(clientData)
	h := sha256.New()
	h.Write(auth)
	h.Write(clientDataHash[:])
	digest := sha256.Sum256(h.Sum(nil))
	if !ecdsa.VerifyASN1(pub, digest[:], sig) {
		return Assertion{}, invalid("signature", nil)
	}
	if err := v.checkCategory(a.Category); err != nil {
		return Assertion{}, err
	}
	return Assertion{Counter: a.Counter, ValidationCategory: a.Category, BundleVersion: a.BundleVersion}, nil
}

// p256PublicKey mengubah titik X9.62 tak terkompresi (65 byte) menjadi kunci ECDSA, setelah crypto/ecdh
// memastikan titiknya ada di kurva P-256.
func p256PublicKey(point []byte) (*ecdsa.PublicKey, error) {
	if _, err := ecdh.P256().NewPublicKey(point); err != nil {
		return nil, err
	}
	return &ecdsa.PublicKey{Curve: elliptic.P256(), X: new(big.Int).SetBytes(point[1:33]), Y: new(big.Int).SetBytes(point[33:65])}, nil
}
