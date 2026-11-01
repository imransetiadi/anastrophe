package certs

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

func newSigner(t *testing.T) *SoftwareSigner {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return NewSoftwareSigner(key)
}

func sampleRequest(t *testing.T) Request {
	t.Helper()
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	pub, err := key.PublicKey.ECDH()
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1_794_000_000, 0).UTC()
	return Request{
		CredentialID: bytes.Repeat([]byte{0xC1}, 16),
		SiteID:       []byte{1, 2, 3, 4, 5, 6, 7, 8},
		PublicKey:    pub.Bytes(),
		Zones:        0b101,
		Channel:      "ble",
		NotBefore:    now,
		NotAfter:     now.Add(7 * 24 * time.Hour),
	}
}

func TestTerbitLaluVerifikasi(t *testing.T) {
	signer, req := newSigner(t), sampleRequest(t)
	cert, err := Issue(signer, req)
	if err != nil {
		t.Fatal(err)
	}
	got, err := Verify(cert, signer.Public())
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got.CredentialID, req.CredentialID) || !bytes.Equal(got.SiteID, req.SiteID) || !bytes.Equal(got.PublicKey, req.PublicKey) ||
		got.Zones != req.Zones || got.Channel != req.Channel || !got.NotBefore.Equal(req.NotBefore) || !got.NotAfter.Equal(req.NotAfter) {
		t.Fatalf("payload berbeda: %+v", got)
	}
}

func TestUkuranMaksimal200(t *testing.T) {
	cert, err := Issue(newSigner(t), sampleRequest(t))
	if err != nil {
		t.Fatal(err)
	}
	if len(cert) > 200 {
		t.Fatalf("sertifikat %d B > 200 B (SDD §7.3)", len(cert))
	}
}

func TestSertifikatDimodifikasiDitolak(t *testing.T) {
	signer := newSigner(t)
	cert, _ := Issue(signer, sampleRequest(t))
	for _, i := range []int{20, len(cert) - 1} {
		tampered := append([]byte(nil), cert...)
		tampered[i] ^= 0x01
		if _, err := Verify(tampered, signer.Public()); err == nil {
			t.Fatalf("byte %d diubah tetapi diterima", i)
		}
	}
	if _, err := Verify(cert, newSigner(t).Public()); err == nil {
		t.Fatal("diterima dengan kunci CA lain")
	}
}

func TestKanalTakDikenalDitolak(t *testing.T) {
	req := sampleRequest(t)
	req.Channel = "wallet"
	if _, err := Issue(newSigner(t), req); err == nil {
		t.Fatal("kanal tak didukung diterbitkan")
	}
}

// Review Focus 1: format tanda tangan COSE (raw r‖s) harus cocok dengan implementasi Python.
func TestSertifikatLintasImplementasi(t *testing.T) {
	python, err := exec.LookPath("python3")
	if err != nil || exec.Command(python, "-I", "-c", "import cryptography").Run() != nil {
		t.Skip("python3 + cryptography tidak tersedia")
	}
	scripts, _ := filepath.Abs("../../../scripts/anp1")
	dir := t.TempDir()

	// Go → Python
	signer, req := newSigner(t), sampleRequest(t)
	cert, err := Issue(signer, req)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKIXPublicKey(signer.Public())
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "ca.pem"), pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der}), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "cert.bin"), cert, 0o600); err != nil {
		t.Fatal(err)
	}
	check := `import json, sys
sys.path.insert(0, sys.argv[1])
import lab_ca
from cryptography.hazmat.primitives import serialization
ca = serialization.load_pem_public_key(open(sys.argv[2] + "/ca.pem", "rb").read())
payload = lab_ca.verify_certificate(open(sys.argv[2] + "/cert.bin", "rb").read(), ca)
print(json.dumps({"cred_id": payload[1].hex(), "channel": payload[5], "not_after": payload[7]}))`
	out, err := exec.Command(python, "-I", "-c", check, scripts, dir).CombinedOutput()
	if err != nil {
		t.Fatalf("Python menolak sertifikat Go: %v\n%s", err, out)
	}
	var fromPython struct {
		CredID   string `json:"cred_id"`
		Channel  int    `json:"channel"`
		NotAfter int64  `json:"not_after"`
	}
	if err := json.Unmarshal(out, &fromPython); err != nil {
		t.Fatal(err)
	}
	if fromPython.CredID != hex.EncodeToString(req.CredentialID) || fromPython.Channel != 2 || fromPython.NotAfter != req.NotAfter.Unix() {
		t.Fatalf("payload dibaca Python berbeda: %+v", fromPython)
	}

	// Python → Go
	lab := filepath.Join(dir, "lab")
	if out, err := exec.Command(python, "-I", filepath.Join(scripts, "lab_ca.py"), "--lab-dir", lab, "init", "--site-id", "0102030405060708").CombinedOutput(); err != nil {
		t.Fatalf("lab_ca init: %v\n%s", err, out)
	}
	issued, err := exec.Command(python, "-I", filepath.Join(scripts, "lab_ca.py"), "--lab-dir", lab, "issue", "--cred-id", hex.EncodeToString(req.CredentialID), "--pubkey", hex.EncodeToString(req.PublicKey)).Output()
	if err != nil {
		t.Fatal(err)
	}
	var credential struct {
		Certificate string `json:"certificate"`
	}
	if err := json.Unmarshal(issued, &credential); err != nil {
		t.Fatal(err)
	}
	pythonCert, err := base64.StdEncoding.DecodeString(credential.Certificate)
	if err != nil {
		t.Fatal(err)
	}
	var site struct {
		CAPrivatePEM string `json:"ca_private_pem"`
	}
	raw, err := os.ReadFile(filepath.Join(lab, "site.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(raw, &site); err != nil {
		t.Fatal(err)
	}
	block, _ := pem.Decode([]byte(site.CAPrivatePEM))
	if block == nil {
		t.Fatal("site.json tidak berisi PEM kunci CA")
	}
	caKey, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	got, err := Verify(pythonCert, &caKey.(*ecdsa.PrivateKey).PublicKey)
	if err != nil {
		t.Fatalf("Go menolak sertifikat Python: %v", err)
	}
	if !bytes.Equal(got.CredentialID, req.CredentialID) || got.Channel != "ble" || !bytes.Equal(got.PublicKey, req.PublicKey) {
		t.Fatalf("payload Python dibaca Go berbeda: %+v", got)
	}
}
