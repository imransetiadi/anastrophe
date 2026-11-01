package certs

import (
	"bytes"
	"testing"
)

// Minor 3 review backend: decoder harus menolak bentuk yang tidak kanonik atau ambigu.
func TestCBORMenolakBentukTidakKanonik(t *testing.T) {
	cases := map[string][]byte{
		"uint tidak minimal (5 sebagai 0x18 0x05)": {0x18, 0x05},
		"uint16 tidak minimal (0xFF dalam 2 byte)": {0x19, 0x00, 0xFF},
		"negatif overflow (-1-0xFFFF...FE)":        {0x3b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe},
		"kunci map di luar int64":                  {0xa1, 0x1b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00},
		"kunci map ganda":                          {0xa2, 0x01, 0x00, 0x01, 0x01},
		"teks bukan UTF-8":                         {0x62, 0xff, 0xfe},
	}
	for name, raw := range cases {
		if _, err := decode(raw); err == nil {
			t.Errorf("%s: diterima", name)
		}
	}
	if v, err := decode([]byte{0x18, 0x18}); err != nil || v != uint64(24) {
		t.Fatalf("uint 24 minimal harus diterima: %v %v", v, err)
	}
}

func signedVariant(t *testing.T, s *SoftwareSigner, payload map[int64]any, unprotected any) []byte {
	t.Helper()
	body, err := encode(payload)
	if err != nil {
		t.Fatal(err)
	}
	protected, _ := encode(protectedHeader)
	toSign, _ := sigStructure(protected, body)
	sig, err := s.Sign(toSign)
	if err != nil {
		t.Fatal(err)
	}
	cert, err := encode(tagged{tag: coseSign1Tag, value: []any{protected, unprotected, body, sig}})
	if err != nil {
		t.Fatal(err)
	}
	return cert
}

func validPayload(t *testing.T) map[int64]any {
	r := sampleRequest(t)
	return map[int64]any{1: r.CredentialID, 2: r.SiteID, 3: r.PublicKey, 4: r.Zones, 5: uint64(2), 6: uint64(r.NotBefore.Unix()), 7: uint64(r.NotAfter.Unix())}
}

func TestVerifyMenolakHeaderTakTerlindung(t *testing.T) {
	s := newSigner(t)
	if _, err := Verify(signedVariant(t, s, validPayload(t), map[int64]any{}), s.Public()); err != nil {
		t.Fatalf("varian sah ditolak: %v", err)
	}
	for name, unprotected := range map[string]any{
		"kid di header tak terlindung": map[int64]any{4: []byte("evil-kid")},
		"alg ganda":                    map[int64]any{1: int64(-35)},
		"bukan map":                    []byte{},
	} {
		if _, err := Verify(signedVariant(t, s, validPayload(t), unprotected), s.Public()); err == nil {
			t.Errorf("%s: diterima", name)
		}
	}
}

func TestVerifyMenolakSkemaPayloadLain(t *testing.T) {
	s := newSigner(t)
	extra := validPayload(t)
	extra[8] = bytes.Repeat([]byte{0xAA}, 40) // kunci tak dikenal sekaligus > 200 B
	if _, err := Verify(signedVariant(t, s, extra, map[int64]any{}), s.Public()); err == nil {
		t.Error("payload dengan kunci tambahan / > 200 B diterima")
	}
	short := validPayload(t)
	short[1] = []byte{1, 2, 3}
	if _, err := Verify(signedVariant(t, s, short, map[int64]any{}), s.Public()); err == nil {
		t.Error("cred_id bukan 16 B diterima")
	}
}
