package appattest

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"testing"
)

// assertOpts mengubah satu bagian assertion sintetis; nilai nol = bentuk yang benar.
type assertOpts struct {
	appID       string
	counter     uint32
	ext         []byte
	clientData  []byte
	singleHash  bool // menandatangani nonce langsung, tanpa hash kedua
	noSignature bool
}

// makeAssertion meniru generateAssertion: tanda tangan ECDSA atas SHA256(nonce), nonce =
// SHA256(authenticatorData ‖ SHA256(clientData)) (O-AA02, O-AA06).
func makeAssertion(t testing.TB, key *ecdsa.PrivateKey, o assertOpts) []byte {
	t.Helper()
	appID := o.appID
	if appID == "" {
		appID = testAppID
	}
	auth := append(header(sha([]byte(appID)), 0xc0, o.counter), o.ext...)
	nonce := sha(append(append([]byte{}, auth...), sha(o.clientData)...))
	digest := sha(nonce)
	if o.singleHash {
		digest = nonce
	}
	sig, err := ecdsa.SignASN1(rand.Reader, key, digest)
	if err != nil {
		t.Fatal(err)
	}
	m := cmap{{"signature", sig}, {"authenticatorData", auth}}
	if o.noSignature {
		m = m[1:]
	}
	return enc(m)
}

func testKey(t testing.TB) (*ecdsa.PrivateKey, []byte) {
	t.Helper()
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	ek, err := key.PublicKey.ECDH()
	if err != nil {
		t.Fatal(err)
	}
	return key, ek.Bytes()
}

func TestAssertionSintetisLulus(t *testing.T) {
	pki := newTestPKI(t)
	key, point := testKey(t)
	data := []byte(`{"challenge":"abc","request":"enrol"}`)
	got, err := pki.verifier(t, Production).VerifyAssertion(makeAssertion(t, key, assertOpts{counter: 5, clientData: data}), data, point, 4)
	if err != nil || got.Counter != 5 || got.ValidationCategory != nil || got.BundleVersion != nil {
		t.Fatalf("dasar: %+v %v", got, err)
	}
	got, err = pki.verifier(t, Production, 3).VerifyAssertion(makeAssertion(t, key, assertOpts{counter: 6, clientData: data, ext: extMap([]byte{3, 0, 0, 0}, "9")}), data, point, 5)
	if err != nil || got.Counter != 6 || got.ValidationCategory == nil || *got.ValidationCategory != 3 || got.BundleVersion == nil || *got.BundleVersion != "9" {
		t.Fatalf("dengan ekstensi: %+v %v", got, err)
	}
}

func TestAssertionSintetisDitolak(t *testing.T) {
	pki := newTestPKI(t)
	key, point := testKey(t)
	data := []byte("data-permintaan")
	offCurve := append([]byte{4}, bytes.Repeat([]byte{1}, 64)...)
	garbageSig := enc(cmap{{"signature", []byte{0x30, 0x02, 0x01, 0x00}}, {"authenticatorData", header(sha([]byte(testAppID)), 0xc0, 3)}})
	cases := []struct {
		name       string
		assertion  []byte
		clientData []byte
		publicKey  []byte
		previous   uint32
		categories []uint32
		reason     string
	}{
		{"counter_tidak_naik", makeAssertion(t, key, assertOpts{counter: 5, clientData: data}), data, point, 5, nil, "counter"},
		{"counter_pertama_nol", makeAssertion(t, key, assertOpts{counter: 0, clientData: data}), data, point, 0, nil, "counter"},
		{"clientData_lain", makeAssertion(t, key, assertOpts{counter: 1, clientData: data}), []byte("data-lain"), point, 0, nil, "signature"},
		{"app_id_lain", makeAssertion(t, key, assertOpts{counter: 1, clientData: data, appID: "ABCDE12345.com.lain"}), data, point, 0, nil, "rp_id"},
		{"hash_tunggal", makeAssertion(t, key, assertOpts{counter: 1, clientData: data, singleHash: true}), data, point, 0, nil, "signature"},
		{"tanda_tangan_rusak", garbageSig, data, point, 0, nil, "signature"},
		{"kunci_64_byte", makeAssertion(t, key, assertOpts{counter: 1, clientData: data}), data, point[1:], 0, nil, "key"},
		{"titik_di_luar_kurva", makeAssertion(t, key, assertOpts{counter: 1, clientData: data}), data, offCurve, 0, nil, "key"},
		{"melebihi_batas", make([]byte, MaxAssertionSize+1), data, point, 0, nil, "format"},
		{"tanpa_signature", makeAssertion(t, key, assertOpts{counter: 1, clientData: data, noSignature: true}), data, point, 0, nil, "format"},
		{"bukan_map", enc([]any{uint64(1)}), data, point, 0, nil, "format"},
		{"kategori_di_luar_daftar", makeAssertion(t, key, assertOpts{counter: 1, clientData: data, ext: extMap([]byte{3, 0, 0, 0}, nil)}), data, point, 0, []uint32{4}, "category"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := pki.verifier(t, Production, c.categories...).VerifyAssertion(c.assertion, c.clientData, c.publicKey, c.previous)
			if err == nil {
				t.Fatal("diterima")
			}
			if r := reasonOf(t, err); r != c.reason {
				t.Fatalf("alasan = %q (%v), ingin %q", r, err, c.reason)
			}
		})
	}
}
