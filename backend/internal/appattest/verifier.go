package appattest

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/x509"
	_ "embed"
	"encoding/asn1"
	"errors"
	"fmt"
	"regexp"
	"slices"
	"time"
)

// Environment adalah lingkungan App Attest kunci (entitlement appattest-environment), yang menentukan aaguid.
type Environment int

const (
	Production Environment = iota
	Development
)

// MaxAttestationSize membatasi objek attestation sebelum diurai (contoh Apple ±6 KiB).
const MaxAttestationSize = 64 << 10

// appleRootPEM: Apple App Attestation Root CA (E38), SHA-256 DER dipin di test.
//
//go:embed apple_app_attestation_root_ca.pem
var appleRootPEM []byte

var (
	appIDPattern = regexp.MustCompile(`^[A-Z0-9]{10}\.[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*$`)
	// oidNonceExtension: ekstensi credCert berisi SEQUENCE { [1] EXPLICIT OCTET STRING nonce } (O-AA01, O-AA04).
	oidNonceExtension = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 8, 2}
	aaguidDevelopment = []byte("appattestdevelop")
	aaguidProductionV = append([]byte("appattest"), make([]byte, 7)...)
)

// Config mengatur Verifier. AppID = "<TeamID>.<BundleID>". Roots nil = root Apple tertanam; Now nil =
// time.Now. Categories kosong = tanpa kebijakan kategori; bila diisi, kategori validasi yang ADA harus
// termasuk daftar ini, sedangkan ekstensi yang tidak ada tetap diterima (I-17).
type Config struct {
	AppID       string
	Environment Environment
	Roots       *x509.CertPool
	Now         func() time.Time
	Categories  []uint32
}

// Verifier memverifikasi attestation dan assertion untuk satu App ID dan lingkungan.
type Verifier struct {
	rpIDHash   []byte
	aaguid     []byte
	roots      *x509.CertPool
	now        func() time.Time
	categories []uint32
}

// NewVerifier memvalidasi konfigurasi dan menyiapkan root.
func NewVerifier(cfg Config) (*Verifier, error) {
	if !appIDPattern.MatchString(cfg.AppID) {
		return nil, fmt.Errorf("appattest: App ID %q bukan <TeamID>.<BundleID>", cfg.AppID)
	}
	v := &Verifier{roots: cfg.Roots, now: cfg.Now, categories: slices.Clone(cfg.Categories)}
	switch cfg.Environment {
	case Production:
		v.aaguid = aaguidProductionV
	case Development:
		v.aaguid = aaguidDevelopment
	default:
		return nil, errors.New("appattest: lingkungan tak dikenal")
	}
	if v.roots == nil {
		v.roots = x509.NewCertPool()
		if !v.roots.AppendCertsFromPEM(appleRootPEM) {
			return nil, errors.New("appattest: root Apple tertanam tidak terbaca")
		}
	}
	if v.now == nil {
		v.now = time.Now
	}
	rp := sha256.Sum256([]byte(cfg.AppID))
	v.rpIDHash = rp[:]
	return v, nil
}

// Attestation adalah hasil attestation yang lolos verifikasi: kunci publik (titik P-256 tak terkompresi,
// 65 byte) untuk memverifikasi assertion, key identifier (SHA256 kunci itu), dan receipt untuk metrik risiko
// (U15). Ekstensi nil bila tidak ada.
type Attestation struct {
	PublicKey          []byte
	KeyID              []byte
	Receipt            []byte
	ValidationCategory *uint32
	BundleVersion      *string
}

// VerifyAttestation menjalankan langkah Apple (O-AA01) berurutan. clientDataHash diberikan pemanggil: app
// Anastrophe akan mengirim SHA256(challenge) ke attestKey (O-AA03); contoh resmi Apple memakai challenge
// mentah (O-AA05), jadi verifier tidak meng-hash challenge sendiri. keyID adalah key identifier dari app.
func (v *Verifier) VerifyAttestation(attestation, clientDataHash, keyID []byte) (Attestation, error) {
	if err := v.ready(); err != nil {
		return Attestation{}, err
	}
	if len(attestation) > MaxAttestationSize {
		return Attestation{}, invalid("format", errors.New("attestation terlalu besar"))
	}
	if len(clientDataHash) == 0 {
		return Attestation{}, invalid("format", errors.New("clientDataHash kosong"))
	}
	obj, err := decodeCBOR(attestation)
	if err != nil {
		return Attestation{}, invalid("format", err)
	}
	m, _ := obj.(map[any]any)
	if f, _ := m["fmt"].(string); f != "apple-appattest" {
		return Attestation{}, invalid("format", errors.New("fmt bukan apple-appattest"))
	}
	stmt, _ := m["attStmt"].(map[any]any)
	x5c, _ := stmt["x5c"].([]any)
	receipt, _ := stmt["receipt"].([]byte)
	auth, _ := m["authData"].([]byte)
	if len(x5c) == 0 || len(receipt) == 0 || auth == nil {
		return Attestation{}, invalid("format", errors.New("attStmt atau authData tidak lengkap"))
	}
	certs := make([]*x509.Certificate, len(x5c))
	for i, raw := range x5c {
		der, ok := raw.([]byte)
		if !ok {
			return Attestation{}, invalid("format", errors.New("x5c bukan byte string"))
		}
		if certs[i], err = x509.ParseCertificate(der); err != nil {
			return Attestation{}, invalid("format", err)
		}
	}

	// Langkah 1: rantai credCert → intermediate → root yang dikonfigurasi. credCert harus sertifikat akhir,
	// bukan CA, agar urutan x5c yang tertukar tidak lolos.
	leaf := certs[0]
	if leaf.IsCA {
		return Attestation{}, invalid("chain", errors.New("credCert adalah CA"))
	}
	intermediates := x509.NewCertPool()
	for _, c := range certs[1:] {
		intermediates.AddCert(c)
	}
	if _, err := leaf.Verify(x509.VerifyOptions{
		Roots: v.roots, Intermediates: intermediates, CurrentTime: v.now(),
		KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	}); err != nil {
		return Attestation{}, invalid("chain", err)
	}
	pub, ok := leaf.PublicKey.(*ecdsa.PublicKey)
	if !ok || pub.Curve != elliptic.P256() {
		return Attestation{}, invalid("key", errors.New("kunci credCert bukan ECDSA P-256"))
	}
	ek, err := pub.ECDH()
	if err != nil {
		return Attestation{}, invalid("key", err)
	}
	point := ek.Bytes() // titik X9.62 tak terkompresi, 65 byte

	// Langkah 2–4: nonce = SHA256(authData ‖ clientDataHash) harus sama dengan isi ekstensi credCert.
	h := sha256.New()
	h.Write(auth)
	h.Write(clientDataHash)
	if embedded, err := nonceExtension(leaf); err != nil || !bytes.Equal(embedded, h.Sum(nil)) {
		return Attestation{}, invalid("nonce", err)
	}

	// Langkah 5: key identifier = SHA256(titik X9.62 tak terkompresi).
	sum := sha256.Sum256(point)
	if !bytes.Equal(sum[:], keyID) {
		return Attestation{}, invalid("key_id", nil)
	}

	// Langkah 6–9 dan ekstensi.
	a, err := parseAttestationAuthData(auth)
	if err != nil {
		return Attestation{}, err
	}
	if !bytes.Equal(a.RPIDHash, v.rpIDHash) {
		return Attestation{}, invalid("rp_id", nil)
	}
	if a.Counter != 0 {
		return Attestation{}, invalid("counter", nil)
	}
	if !bytes.Equal(a.AAGUID, v.aaguid) {
		return Attestation{}, invalid("aaguid", nil)
	}
	if !bytes.Equal(a.CredentialID, keyID) {
		return Attestation{}, invalid("credential_id", nil)
	}
	if err := v.checkCategory(a.Category); err != nil {
		return Attestation{}, err
	}
	return Attestation{
		PublicKey: point, KeyID: sum[:], Receipt: receipt,
		ValidationCategory: a.Category, BundleVersion: a.BundleVersion,
	}, nil
}

// nonceExtension mengambil satu-satunya octet string dari ekstensi OID 1.2.840.113635.100.8.2.
func nonceExtension(cert *x509.Certificate) ([]byte, error) {
	for _, ext := range cert.Extensions {
		if !ext.Id.Equal(oidNonceExtension) {
			continue
		}
		var v struct {
			Nonce []byte `asn1:"tag:1,explicit"`
		}
		rest, err := asn1.Unmarshal(ext.Value, &v)
		if err != nil {
			return nil, err
		}
		if len(rest) != 0 {
			return nil, errors.New("sisa byte di ekstensi nonce")
		}
		return v.Nonce, nil
	}
	return nil, errors.New("ekstensi nonce tidak ada")
}

// ready menolak Verifier nilai nol (mis. `var v Verifier` dari paket lain, tanpa lewat NewVerifier) dengan
// galat jelas. rpIDHash dan now hanya pernah diisi oleh NewVerifier, jadi nil berarti belum diinisialisasi;
// tanpa pengecekan ini, v.now() panik (minor review akhir ADR-0052).
func (v *Verifier) ready() error {
	if v == nil || v.rpIDHash == nil || v.now == nil {
		return invalid("config", errors.New("Verifier belum diinisialisasi lewat NewVerifier"))
	}
	return nil
}

// checkCategory menerapkan Config.Categories pada kategori yang ada (I-17).
func (v *Verifier) checkCategory(category *uint32) error {
	if category == nil || len(v.categories) == 0 || slices.Contains(v.categories, *category) {
		return nil
	}
	return invalid("category", fmt.Errorf("kategori validasi %d tidak diizinkan", *category))
}
