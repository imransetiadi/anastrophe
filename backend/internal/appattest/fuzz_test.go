package appattest

import (
	"errors"
	"testing"
	"time"
)

// FuzzVerifyAttestation: masukan apa pun tidak membuat panic, dan setiap galat membungkus ErrInvalid.
func FuzzVerifyAttestation(f *testing.F) {
	s, att, keyID, at := loadAppleSample(f)
	f.Add(att)
	pki := newTestPKI(f)
	f.Add(pki.attestation(f, attOpts{ext: extMap([]byte{4, 0, 0, 0}, "3")}).attestation)
	v, err := NewVerifier(Config{AppID: s.AppID, Now: func() time.Time { return at }})
	if err != nil {
		f.Fatal(err)
	}
	cdh := []byte(s.ClientDataHash)
	f.Fuzz(func(t *testing.T, data []byte) {
		if _, err := v.VerifyAttestation(data, cdh, keyID); err != nil && !errors.Is(err, ErrInvalid) {
			t.Fatalf("galat tanpa ErrInvalid: %v", err)
		}
	})
}

// FuzzVerifyAssertion: sama untuk assertion.
func FuzzVerifyAssertion(f *testing.F) {
	pki := newTestPKI(f)
	key, point := testKey(f)
	data := []byte("data-permintaan")
	f.Add(makeAssertion(f, key, assertOpts{counter: 1, clientData: data}))
	f.Add(makeAssertion(f, key, assertOpts{counter: 2, clientData: data, ext: extMap([]byte{3, 0, 0, 0}, "9")}))
	v := pki.verifier(f, Production)
	f.Fuzz(func(t *testing.T, assertion []byte) {
		if _, err := v.VerifyAssertion(assertion, data, point, 0); err != nil && !errors.Is(err, ErrInvalid) {
			t.Fatalf("galat tanpa ErrInvalid: %v", err)
		}
	})
}
