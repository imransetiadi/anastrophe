// Package certs menerbitkan dan memverifikasi CredentialCert (SDD §7.3):
// COSE_Sign1 (RFC 9052, ES256, tag 18) atas map CBOR berkunci integer.
package certs

import (
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/anp1"
)

// Signer menandatangani dengan kunci Site CA. Implementasi produksi memakai KMS/HSM
// tanpa mengekspor kunci privat; keluaran wajib raw r‖s 64 B (COSE ES256).
type Signer interface {
	Sign(message []byte) ([]byte, error)
	Public() *ecdsa.PublicKey
}

// SoftwareSigner memegang kunci P-256 di memori — hanya untuk dev, test, dan lab.
type SoftwareSigner struct{ key *ecdsa.PrivateKey }

func NewSoftwareSigner(key *ecdsa.PrivateKey) *SoftwareSigner { return &SoftwareSigner{key: key} }

func (s *SoftwareSigner) Public() *ecdsa.PublicKey { return &s.key.PublicKey }

func (s *SoftwareSigner) Sign(message []byte) ([]byte, error) {
	digest := sha256.Sum256(message)
	r, sv, err := ecdsa.Sign(rand.Reader, s.key, digest[:])
	if err != nil {
		return nil, err
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	sv.FillBytes(sig[32:])
	return sig, nil
}

// Request adalah isi CredentialCert.
type Request struct {
	CredentialID []byte // 16 B
	SiteID       []byte // 8 B
	PublicKey    []byte // x963 65 B
	Zones        uint64 // bitmap
	Channel      string // "nfcHCE" | "ble" | "nfcSE"
	NotBefore    time.Time
	NotAfter     time.Time
}

const coseSign1Tag = 18

// MaxSize menjaga respons GET_CERT tetap < 255 B (SDD §7.3).
const MaxSize = 200

var channelCodes = map[string]uint64{"nfcHCE": 1, "ble": 2, "nfcSE": 3}

var protectedHeader = map[int64]any{1: int64(-7)} // alg: ES256

var ErrInvalid = errors.New("certs: sertifikat tidak valid")

// Issue membangun dan menandatangani CredentialCert.
func Issue(s Signer, r Request) ([]byte, error) {
	code, ok := channelCodes[r.Channel]
	if !ok {
		return nil, errors.New("certs: kanal tidak didukung")
	}
	if len(r.CredentialID) != 16 || len(r.SiteID) != 8 {
		return nil, errors.New("certs: panjang cred_id/site_id salah")
	}
	if _, err := anp1.ParsePublicKey(r.PublicKey); err != nil {
		return nil, err
	}
	payload, err := encode(map[int64]any{
		1: r.CredentialID, 2: r.SiteID, 3: r.PublicKey, 4: r.Zones, 5: code,
		6: uint64(r.NotBefore.Unix()), 7: uint64(r.NotAfter.Unix()),
	})
	if err != nil {
		return nil, err
	}
	protected, _ := encode(protectedHeader)
	toSign, err := sigStructure(protected, payload)
	if err != nil {
		return nil, err
	}
	sig, err := s.Sign(toSign)
	if err != nil {
		return nil, err
	}
	if len(sig) != 64 {
		return nil, errors.New("certs: signer harus mengembalikan r‖s 64 B")
	}
	cert, err := encode(tagged{tag: coseSign1Tag, value: []any{protected, map[int64]any{}, payload, sig}})
	if err != nil {
		return nil, err
	}
	if len(cert) > MaxSize {
		return nil, errors.New("certs: sertifikat melebihi 200 B")
	}
	return cert, nil
}

// Verify memeriksa tanda tangan Site CA lalu mengembalikan isi sertifikat.
func Verify(cert []byte, ca *ecdsa.PublicKey) (Request, error) {
	v, err := decode(cert)
	if err != nil {
		return Request{}, ErrInvalid
	}
	t, ok := v.(tagged)
	if !ok || t.tag != coseSign1Tag {
		return Request{}, ErrInvalid
	}
	parts, ok := t.value.([]any)
	if !ok || len(parts) != 4 {
		return Request{}, ErrInvalid
	}
	protected, ok1 := parts[0].([]byte)
	payload, ok2 := parts[2].([]byte)
	sig, ok3 := parts[3].([]byte)
	if !ok1 || !ok2 || !ok3 {
		return Request{}, ErrInvalid
	}
	if header, err := decode(protected); err != nil || !isES256(header) {
		return Request{}, ErrInvalid
	}
	toSign, err := sigStructure(protected, payload)
	if err != nil || !anp1.VerifyRaw(ca, toSign, sig) {
		return Request{}, ErrInvalid
	}
	body, err := decode(payload)
	if err != nil {
		return Request{}, ErrInvalid
	}
	return parsePayload(body)
}

func sigStructure(protected, payload []byte) ([]byte, error) {
	return encode([]any{"Signature1", protected, []byte{}, payload})
}

func isES256(header any) bool {
	m, ok := header.(map[int64]any)
	return ok && len(m) == 1 && m[1] == int64(-7)
}

func parsePayload(body any) (Request, error) {
	m, ok := body.(map[int64]any)
	if !ok {
		return Request{}, ErrInvalid
	}
	credID, ok1 := m[1].([]byte)
	siteID, ok2 := m[2].([]byte)
	pub, ok3 := m[3].([]byte)
	zones, ok4 := m[4].(uint64)
	code, ok5 := m[5].(uint64)
	nbf, ok6 := m[6].(uint64)
	naf, ok7 := m[7].(uint64)
	if !(ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7) {
		return Request{}, ErrInvalid
	}
	channel := ""
	for name, c := range channelCodes {
		if c == code {
			channel = name
		}
	}
	if channel == "" {
		return Request{}, ErrInvalid
	}
	return Request{
		CredentialID: credID, SiteID: siteID, PublicKey: pub, Zones: zones, Channel: channel,
		NotBefore: time.Unix(int64(nbf), 0).UTC(), NotAfter: time.Unix(int64(naf), 0).UTC(),
	}, nil
}
