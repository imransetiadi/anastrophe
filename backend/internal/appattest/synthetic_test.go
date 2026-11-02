package appattest

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/hex"
	"math/big"
	"testing"
	"time"
)

const testAppID = "ABCDE12345.com.contoh.app"

var (
	testNow      = time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)
	oidNonce     = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 8, 2}
	testValidity = [2]time.Time{time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), time.Date(2027, 1, 1, 0, 0, 0, 0, time.UTC)}
)

// testPKI meniru susunan Apple: root CA → intermediate CA → credCert (leaf), semuanya P-256 buatan test.
type testPKI struct {
	interKey *ecdsa.PrivateKey
	inter    *x509.Certificate
	interDER []byte
	pool     *x509.CertPool
}

func newTestPKI(t testing.TB) *testPKI {
	t.Helper()
	rootKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	rootTmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "Uji Root CA"},
		NotBefore: testValidity[0], NotAfter: testValidity[1],
		IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign,
	}
	rootDER, err := x509.CreateCertificate(rand.Reader, rootTmpl, rootTmpl, &rootKey.PublicKey, rootKey)
	if err != nil {
		t.Fatal(err)
	}
	root, _ := x509.ParseCertificate(rootDER)
	interKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	interTmpl := &x509.Certificate{
		SerialNumber: big.NewInt(2), Subject: pkix.Name{CommonName: "Uji Attestation CA"},
		NotBefore: testValidity[0], NotAfter: testValidity[1],
		IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign,
	}
	interDER, err := x509.CreateCertificate(rand.Reader, interTmpl, root, &interKey.PublicKey, rootKey)
	if err != nil {
		t.Fatal(err)
	}
	inter, _ := x509.ParseCertificate(interDER)
	pool := x509.NewCertPool()
	pool.AddCert(root)
	return &testPKI{interKey: interKey, inter: inter, interDER: interDER, pool: pool}
}

// attOpts mengubah satu bagian attestation sintetis; nilai nol = bentuk yang benar.
type attOpts struct {
	appID     string
	counter   uint32
	aaguid    []byte
	credID    []byte
	ext       []byte
	fmt       string
	noReceipt bool
	curve     elliptic.Curve
	nonceExt  func(nonce []byte) []byte // nil = benar; mengembalikan nil = ekstensi tidak ada
	swapX5C   bool
}

type synthAtt struct {
	attestation    []byte
	keyID          []byte
	clientDataHash []byte
	key            *ecdsa.PrivateKey
	point          []byte
}

func sha(b []byte) []byte { s := sha256.Sum256(b); return s[:] }

func (p *testPKI) attestation(t testing.TB, o attOpts) synthAtt {
	t.Helper()
	curve := o.curve
	if curve == nil {
		curve = elliptic.P256()
	}
	key, _ := ecdsa.GenerateKey(curve, rand.Reader)
	ek, err := key.PublicKey.ECDH()
	if err != nil {
		t.Fatal(err)
	}
	point := ek.Bytes()
	keyID := sha(point)
	appID, aaguid, credID, format := o.appID, o.aaguid, o.credID, o.fmt
	if appID == "" {
		appID = testAppID
	}
	if aaguid == nil {
		aaguid = aaguidProduction
	}
	if credID == nil {
		credID = keyID
	}
	if format == "" {
		format = "apple-appattest"
	}
	size := (curve.Params().BitSize + 7) / 8
	cose := enc(cmap{{1, 2}, {3, -7}, {-1, 1}, {-2, point[1 : 1+size]}, {-3, point[1+size:]}})
	auth := attAuthData(sha([]byte(appID)), o.counter, aaguid, credID, cose, o.ext)
	clientDataHash := sha([]byte("tantangan-uji"))
	nonce := sha(append(append([]byte{}, auth...), clientDataHash...))
	extValue, err := asn1.Marshal(struct {
		Nonce []byte `asn1:"tag:1,explicit"`
	}{nonce})
	if err != nil {
		t.Fatal(err)
	}
	if o.nonceExt != nil {
		extValue = o.nonceExt(nonce)
	}
	leafTmpl := &x509.Certificate{
		SerialNumber: big.NewInt(3), Subject: pkix.Name{CommonName: hex.EncodeToString(keyID)},
		NotBefore: testValidity[0], NotAfter: testValidity[1],
		BasicConstraintsValid: true, KeyUsage: x509.KeyUsageDigitalSignature,
	}
	if extValue != nil {
		leafTmpl.ExtraExtensions = []pkix.Extension{{Id: oidNonce, Value: extValue}}
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leafTmpl, p.inter, &key.PublicKey, p.interKey)
	if err != nil {
		t.Fatal(err)
	}
	x5c := []any{leafDER, p.interDER}
	if o.swapX5C {
		x5c = []any{p.interDER, leafDER}
	}
	receipt := []byte("receipt-uji")
	if o.noReceipt {
		receipt = []byte{}
	}
	obj := enc(cmap{{"fmt", format}, {"attStmt", cmap{{"x5c", x5c}, {"receipt", receipt}}}, {"authData", auth}})
	return synthAtt{attestation: obj, keyID: keyID, clientDataHash: clientDataHash, key: key, point: point}
}

func (p *testPKI) verifier(t testing.TB, env Environment, categories ...uint32) *Verifier {
	t.Helper()
	v, err := NewVerifier(Config{AppID: testAppID, Environment: env, Roots: p.pool, Now: func() time.Time { return testNow }, Categories: categories})
	if err != nil {
		t.Fatal(err)
	}
	return v
}

func TestAttestationSintetisLulus(t *testing.T) {
	pki := newTestPKI(t)
	t.Run("dasar", func(t *testing.T) {
		a := pki.attestation(t, attOpts{ext: extMap([]byte{4, 0, 0, 0}, "3")})
		got, err := pki.verifier(t, Production, 4).VerifyAttestation(a.attestation, a.clientDataHash, a.keyID)
		if err != nil {
			t.Fatal(err)
		}
		if string(got.PublicKey) != string(a.point) || string(got.KeyID) != string(a.keyID) || string(got.Receipt) != "receipt-uji" {
			t.Fatalf("hasil = %+v", got)
		}
		if got.ValidationCategory == nil || *got.ValidationCategory != 4 || got.BundleVersion == nil || *got.BundleVersion != "3" {
			t.Fatalf("ekstensi = %v %v", got.ValidationCategory, got.BundleVersion)
		}
	})
	t.Run("development", func(t *testing.T) {
		a := pki.attestation(t, attOpts{aaguid: []byte("appattestdevelop")})
		if _, err := pki.verifier(t, Development).VerifyAttestation(a.attestation, a.clientDataHash, a.keyID); err != nil {
			t.Fatal(err)
		}
	})
	t.Run("tanpa_ekstensi", func(t *testing.T) {
		// I-17: ekstensi yang tidak ada diterima, juga saat kebijakan kategori dikonfigurasi.
		a := pki.attestation(t, attOpts{})
		got, err := pki.verifier(t, Production, 4).VerifyAttestation(a.attestation, a.clientDataHash, a.keyID)
		if err != nil || got.ValidationCategory != nil || got.BundleVersion != nil {
			t.Fatalf("%+v %v", got, err)
		}
	})
}

func TestAttestationSintetisDitolak(t *testing.T) {
	pki := newTestPKI(t)
	cases := []struct {
		name       string
		opts       attOpts
		categories []uint32
		reason     string
	}{
		{"counter_bukan_nol", attOpts{counter: 1}, nil, "counter"},
		{"credential_id_lain", attOpts{credID: sha([]byte("lain"))}, nil, "credential_id"},
		{"credential_id_31_byte", attOpts{credID: make([]byte, 31)}, nil, "credential_id"},
		{"receipt_kosong", attOpts{noReceipt: true}, nil, "format"},
		{"fmt_lain", attOpts{fmt: "packed"}, nil, "format"},
		{"leaf_p384", attOpts{curve: elliptic.P384()}, nil, "key"},
		{"tanpa_ekstensi_nonce", attOpts{nonceExt: func([]byte) []byte { return nil }}, nil, "nonce"},
		{"ekstensi_nonce_rusak", attOpts{nonceExt: func([]byte) []byte { return []byte{0x30, 0x03, 0x02, 0x01, 0x05} }}, nil, "nonce"},
		{"urutan_x5c_tertukar", attOpts{swapX5C: true}, nil, "chain"},
		{"kategori_di_luar_daftar", attOpts{ext: extMap([]byte{3, 0, 0, 0}, nil)}, []uint32{4}, "category"},
		{"kategori_bukan_4_byte", attOpts{ext: extMap([]byte{3, 0}, nil)}, nil, "format"},
		{"versi_bukan_teks", attOpts{ext: extMap(nil, uint64(1))}, nil, "format"},
		{"aaguid_development_di_production", attOpts{aaguid: []byte("appattestdevelop")}, nil, "aaguid"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			a := pki.attestation(t, c.opts)
			_, err := pki.verifier(t, Production, c.categories...).VerifyAttestation(a.attestation, a.clientDataHash, a.keyID)
			if err == nil {
				t.Fatal("diterima")
			}
			if r := reasonOf(t, err); r != c.reason {
				t.Fatalf("alasan = %q (%v), ingin %q", r, err, c.reason)
			}
		})
	}
}
