package appattest

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"os"
	"testing"
	"time"
)

type appleSample struct {
	AppID          string `json:"appId"`
	KeyID          string `json:"keyId"`
	ClientDataHash string `json:"clientDataHash"`
	CheckTime      string `json:"checkTime"`
	Attestation    string `json:"attestation"`
	Expected       struct {
		ValidationCategory uint32 `json:"validationCategory"`
		BundleVersion      string `json:"bundleVersion"`
	} `json:"expected"`
}

func loadAppleSample(t testing.TB) (appleSample, []byte, []byte, time.Time) {
	t.Helper()
	raw, err := os.ReadFile("testdata/apple-sample-attestation-2026.json")
	if err != nil {
		t.Fatal(err)
	}
	var s appleSample
	if err := json.Unmarshal(raw, &s); err != nil {
		t.Fatal(err)
	}
	att, err := base64.StdEncoding.DecodeString(s.Attestation)
	if err != nil {
		t.Fatal(err)
	}
	keyID, err := base64.StdEncoding.DecodeString(s.KeyID)
	if err != nil {
		t.Fatal(err)
	}
	at, err := time.Parse(time.RFC3339, s.CheckTime)
	if err != nil {
		t.Fatal(err)
	}
	return s, att, keyID, at
}

func TestRootAppleTertanam(t *testing.T) {
	block, _ := pem.Decode(appleRootPEM)
	if block == nil {
		t.Fatal("PEM root tidak terbaca")
	}
	sum := sha256.Sum256(block.Bytes)
	if got := hex.EncodeToString(sum[:]); got != "1cb9823ba28ba6ad2d33a006941de2ae4f513ef1d4e831b9f7e0fa7b6242c932" {
		t.Fatalf("sidik jari root = %s", got)
	}
}

func TestNewVerifierMenolakAppIDRusak(t *testing.T) {
	for _, id := range []string{"", "1234.com.x", "1234567890", "1234567890.com/x", "1234567890.", "abcdefghij.com.x"} {
		if _, err := NewVerifier(Config{AppID: id}); err == nil {
			t.Errorf("App ID %q diterima", id)
		}
	}
	if _, err := NewVerifier(Config{AppID: "1234567890.com.example.myapp", Environment: Environment(9)}); err == nil {
		t.Error("lingkungan tak dikenal diterima")
	}
}

func TestContohAppleLulus(t *testing.T) {
	s, att, keyID, at := loadAppleSample(t)
	v, err := NewVerifier(Config{AppID: s.AppID, Environment: Production, Now: func() time.Time { return at }})
	if err != nil {
		t.Fatal(err)
	}
	got, err := v.VerifyAttestation(att, []byte(s.ClientDataHash), keyID)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(got.PublicKey)
	if len(got.PublicKey) != 65 || !bytes.Equal(sum[:], keyID) || !bytes.Equal(got.KeyID, keyID) || len(got.Receipt) == 0 {
		t.Fatalf("hasil: kunci %d byte, receipt %d byte", len(got.PublicKey), len(got.Receipt))
	}
	if got.ValidationCategory == nil || *got.ValidationCategory != s.Expected.ValidationCategory || got.BundleVersion == nil || *got.BundleVersion != s.Expected.BundleVersion {
		t.Fatalf("ekstensi = %v %v", got.ValidationCategory, got.BundleVersion)
	}
}

// rebuildAppleSample mengganti x5c contoh Apple (test penyusunan rantai).
func rebuildAppleSample(t *testing.T, att []byte, x5c func([]any) []any) []byte {
	t.Helper()
	v, err := decodeCBOR(att)
	if err != nil {
		t.Fatal(err)
	}
	m := v.(map[any]any)
	st := m["attStmt"].(map[any]any)
	return enc(cmap{{"fmt", m["fmt"]}, {"attStmt", cmap{{"x5c", x5c(st["x5c"].([]any))}, {"receipt", st["receipt"]}}}, {"authData", m["authData"]}})
}

func TestContohAppleDitolak(t *testing.T) {
	s, att, keyID, at := loadAppleSample(t)
	challenge := []byte(s.ClientDataHash)
	hashed := sha256.Sum256(challenge)
	tampered := append([]byte{}, att...)
	tampered[len(tampered)-226+40] ^= 0x01 // byte aaguid di authData (item terakhir objek)
	otherKey := append([]byte{}, keyID...)
	otherKey[0] ^= 0xff
	pki := newTestPKI(t)
	cases := []struct {
		name          string
		cfg           Config
		att, cdh, key []byte
		reason        string
	}{
		{"app_id_lain", Config{AppID: "1234567890.com.example.other"}, att, challenge, keyID, "rp_id"},
		{"development", Config{AppID: s.AppID, Environment: Development}, att, challenge, keyID, "aaguid"},
		{"key_id_lain", Config{AppID: s.AppID}, att, challenge, otherKey, "key_id"},
		{"clientDataHash_sha256", Config{AppID: s.AppID}, att, hashed[:], keyID, "nonce"},
		{"kedaluwarsa", Config{AppID: s.AppID, Now: func() time.Time { return time.Date(2026, 11, 2, 0, 0, 0, 0, time.UTC) }}, att, challenge, keyID, "chain"},
		{"pool_root_uji", Config{AppID: s.AppID, Roots: pki.pool}, att, challenge, keyID, "chain"},
		{"authData_diubah", Config{AppID: s.AppID}, tampered, challenge, keyID, "nonce"},
		{"tanpa_intermediate", Config{AppID: s.AppID}, rebuildAppleSample(t, att, func(x []any) []any { return x[:1] }), challenge, keyID, "chain"},
		{"x5c_tertukar", Config{AppID: s.AppID}, rebuildAppleSample(t, att, func(x []any) []any { return []any{x[1], x[0]} }), challenge, keyID, "chain"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if c.cfg.Now == nil {
				c.cfg.Now = func() time.Time { return at }
			}
			v, err := NewVerifier(c.cfg)
			if err != nil {
				t.Fatal(err)
			}
			_, err = v.VerifyAttestation(c.att, c.cdh, c.key)
			if err == nil {
				t.Fatal("diterima")
			}
			if r := reasonOf(t, err); r != c.reason {
				t.Fatalf("alasan = %q (%v), ingin %q", r, err, c.reason)
			}
		})
	}
}

func TestAttestationMelebihiBatas(t *testing.T) {
	v, err := NewVerifier(Config{AppID: testAppID})
	if err != nil {
		t.Fatal(err)
	}
	_, err = v.VerifyAttestation(make([]byte, MaxAttestationSize+1), make([]byte, 32), make([]byte, 32))
	if err == nil || reasonOf(t, err) != "format" {
		t.Fatalf("galat = %v", err)
	}
}

// TestClientDataHashKosongDitolak (minor review akhir ADR-0052): VerifyAttestation sebelumnya menerima
// clientDataHash kosong tanpa galat format eksplisit, dan hanya gagal kebetulan di langkah nonce. Pemanggil
// yang lupa menghitung SHA256(challenge) wajib dapat galat yang jelas, bukan kegagalan nonce yang ambigu
// dengan serangan replay nonce.
func TestClientDataHashKosongDitolak(t *testing.T) {
	s, att, keyID, at := loadAppleSample(t)
	v, err := NewVerifier(Config{AppID: s.AppID, Environment: Production, Now: func() time.Time { return at }})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := v.VerifyAttestation(att, nil, keyID); err == nil || reasonOf(t, err) != "format" {
		t.Fatalf("galat = %v, ingin alasan format", err)
	}
	if _, err := v.VerifyAttestation(att, []byte{}, keyID); err == nil || reasonOf(t, err) != "format" {
		t.Fatalf("galat = %v, ingin alasan format", err)
	}
}

// TestVerifierNilValueTidakPanik (minor review akhir ADR-0052): nilai nol Verifier (dibuat tanpa NewVerifier,
// mis. `var v appattest.Verifier` dari paket lain) sebelumnya panik di v.now() karena fungsi jam nil. Verifier
// yang tidak lewat NewVerifier harus mengembalikan galat jelas, bukan panik.
func TestVerifierNilValueTidakPanik(t *testing.T) {
	var v Verifier
	s, att, keyID, _ := loadAppleSample(t)
	if _, err := v.VerifyAttestation(att, []byte(s.ClientDataHash), keyID); err == nil {
		t.Fatal("nilai nol Verifier menerima attestation")
	}
	if _, err := v.VerifyAssertion(make([]byte, 4), make([]byte, 4), make([]byte, 65), 0); err == nil {
		t.Fatal("nilai nol Verifier menerima assertion")
	}
}
