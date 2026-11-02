package appattest

import (
	"bytes"
	"crypto/sha256"
	"errors"
	"testing"
)

// FuzzParseAuthData menguji decoder CBOR dan pengurai authData langsung. Lewat VerifyAttestation, authData yang
// dimutasi selalu gagal di cek nonce lebih dulu (review akhir ADR-0052).
func FuzzParseAuthData(f *testing.F) {
	rp := sha256.Sum256([]byte(testAppID))
	cred := bytes.Repeat([]byte{7}, 32)
	f.Add(attAuthData(rp[:], 0, aaguidProduction, cred, testCOSEKey(), extMap([]byte{4, 0, 0, 0}, "7")))
	f.Add(append(header(rp[:], 0xc0, 3), extMap([]byte{3, 0, 0, 0}, "9")...))
	f.Fuzz(func(t *testing.T, data []byte) {
		for _, parse := range []func([]byte) (authData, error){parseAttestationAuthData, parseAssertionAuthData} {
			if _, err := parse(data); err != nil && !errors.Is(err, ErrInvalid) {
				t.Fatalf("galat tanpa ErrInvalid: %v", err)
			}
		}
		_, _ = decodeCBOR(data)
	})
}
