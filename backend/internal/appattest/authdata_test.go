package appattest

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"testing"
)

var aaguidProduction = append([]byte("appattest"), make([]byte, 7)...)

// testCOSEKey: kunci COSE EC2 P-256 minimal (isi koordinat tidak diperiksa pengurai).
func testCOSEKey() []byte {
	return enc(cmap{{1, 2}, {3, -7}, {-1, 1}, {-2, bytes.Repeat([]byte{1}, 32)}, {-3, bytes.Repeat([]byte{2}, 32)}})
}

func header(rpID []byte, flags byte, counter uint32) []byte {
	b := append(append([]byte{}, rpID...), flags)
	return binary.BigEndian.AppendUint32(b, counter)
}

func attAuthData(rpID []byte, counter uint32, aaguid, credID, cose, ext []byte) []byte {
	b := header(rpID, 0x40, counter)
	b = append(b, aaguid...)
	b = binary.BigEndian.AppendUint16(b, uint16(len(credID)))
	b = append(b, credID...)
	b = append(b, cose...)
	return append(b, ext...)
}

func extMap(category []byte, version any) []byte {
	m := cmap{}
	if version != nil {
		m = append(m, pair{"apple_bundle_version_01", version})
	}
	if category != nil {
		m = append(m, pair{"apple_validation_category_01", category})
	}
	return enc(m)
}

func reasonOf(t *testing.T, err error) string {
	t.Helper()
	if !errors.Is(err, ErrInvalid) {
		t.Fatalf("galat %v tidak membungkus ErrInvalid", err)
	}
	var e *Error
	if !errors.As(err, &e) {
		t.Fatalf("galat %v bukan *Error", err)
	}
	return e.Reason
}

func TestAuthDataAttestationLulus(t *testing.T) {
	rp := sha256.Sum256([]byte("ABCDE12345.com.contoh.app"))
	cred := bytes.Repeat([]byte{7}, 32)
	a, err := parseAttestationAuthData(attAuthData(rp[:], 0, aaguidProduction, cred, testCOSEKey(), extMap([]byte{4, 0, 0, 0}, "7")))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(a.RPIDHash, rp[:]) || a.Counter != 0 || !bytes.Equal(a.AAGUID, aaguidProduction) || !bytes.Equal(a.CredentialID, cred) {
		t.Fatalf("authData = %+v", a)
	}
	if a.Category == nil || *a.Category != 4 || a.BundleVersion == nil || *a.BundleVersion != "7" {
		t.Fatalf("ekstensi = %v %v", a.Category, a.BundleVersion)
	}
	b, err := parseAttestationAuthData(attAuthData(rp[:], 0, aaguidProduction, cred, testCOSEKey(), nil))
	if err != nil || b.Category != nil || b.BundleVersion != nil {
		t.Fatalf("tanpa ekstensi: %+v %v", b, err)
	}
}

func TestAuthDataAssertionLulus(t *testing.T) {
	rp := sha256.Sum256([]byte("ABCDE12345.com.contoh.app"))
	a, err := parseAssertionAuthData(header(rp[:], 0xc0, 9))
	if err != nil || a.Counter != 9 || a.Category != nil || a.BundleVersion != nil {
		t.Fatalf("header saja: %+v %v", a, err)
	}
	b, err := parseAssertionAuthData(append(header(rp[:], 0xc0, 10), extMap([]byte{3, 0, 0, 0}, "9")...))
	if err != nil || b.Counter != 10 || b.Category == nil || *b.Category != 3 || *b.BundleVersion != "9" {
		t.Fatalf("dengan ekstensi: %+v %v", b, err)
	}
}

func TestAuthDataMenolak(t *testing.T) {
	rp := sha256.Sum256([]byte("ABCDE12345.com.contoh.app"))
	cred := bytes.Repeat([]byte{7}, 32)
	cose := testCOSEKey()
	longLen := append(header(rp[:], 0x40, 0), aaguidProduction...)
	longLen = append(longLen, 0xff, 0xff, 1, 2, 3)
	cases := map[string]func() error{
		"attestation_pendek": func() error { _, err := parseAttestationAuthData(make([]byte, 36)); return err },
		"assertion_pendek":   func() error { _, err := parseAssertionAuthData(make([]byte, 36)); return err },
		"tanpa_aaguid":       func() error { _, err := parseAttestationAuthData(header(rp[:], 0x40, 0)); return err },
		"panjang_credential_0xffff": func() error {
			_, err := parseAttestationAuthData(longLen)
			return err
		},
		"cose_bukan_cbor": func() error {
			_, err := parseAttestationAuthData(attAuthData(rp[:], 0, aaguidProduction, cred, []byte{0xff}, nil))
			return err
		},
		"cose_bukan_map": func() error {
			_, err := parseAttestationAuthData(attAuthData(rp[:], 0, aaguidProduction, cred, enc(uint64(1)), nil))
			return err
		},
		"sisa_sesudah_ekstensi": func() error {
			_, err := parseAttestationAuthData(attAuthData(rp[:], 0, aaguidProduction, cred, cose, append(extMap(nil, "1"), 0x00)))
			return err
		},
		"ekstensi_bukan_map": func() error {
			_, err := parseAssertionAuthData(append(header(rp[:], 0xc0, 1), enc([]any{uint64(1)})...))
			return err
		},
		"kategori_bukan_4_byte": func() error {
			_, err := parseAssertionAuthData(append(header(rp[:], 0xc0, 1), extMap([]byte{1, 0, 0}, nil)...))
			return err
		},
		"versi_bukan_teks": func() error {
			_, err := parseAssertionAuthData(append(header(rp[:], 0xc0, 1), extMap(nil, []byte("1"))...))
			return err
		},
	}
	for name, run := range cases {
		t.Run(name, func(t *testing.T) {
			err := run()
			if err == nil {
				t.Fatal("diterima")
			}
			if r := reasonOf(t, err); r != "format" {
				t.Fatalf("alasan = %q, ingin format", r)
			}
		})
	}
}
