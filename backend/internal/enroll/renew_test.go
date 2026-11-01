package enroll

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/certs"
)

type renewalFixture struct {
	fixture
	enrollmentID string
	credID       []byte
	key          *ecdsa.PrivateKey
	notAfter     time.Time
}

// provisionedForRenewal membuat kartu aktif dengan kunci kredensial yang diketahui test.
func provisionedForRenewal(t *testing.T) renewalFixture {
	t.Helper()
	f := newFixture(t)
	return f.provision(t)
}

func (f fixture) provision(t *testing.T) renewalFixture {
	t.Helper()
	id := f.enroll(t)
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	pub, _ := key.PublicKey.ECDH()
	rec := f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "prov-"+id, map[string]string{
		"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(pub.Bytes()),
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("provisioning: %d %s", rec.Code, rec.Body)
	}
	var out struct {
		CredentialID []byte `json:"credential_id"`
		NotAfter     string `json:"not_after"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	notAfter, _ := time.Parse(time.RFC3339, out.NotAfter)
	return renewalFixture{fixture: f, enrollmentID: id, credID: out.CredentialID, key: key, notAfter: notAfter}
}

func renewalSignature(t *testing.T, key *ecdsa.PrivateKey, credID, nonce []byte) []byte {
	t.Helper()
	digest := sha256.Sum256(append(append([]byte("ANP1-RENEW"), credID...), nonce...))
	r, s, err := ecdsa.Sign(rand.Reader, key, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return sig
}

func (f renewalFixture) challenge(t *testing.T, credID []byte) []byte {
	t.Helper()
	rec := f.do(t, http.MethodPost, "/v1/credentials/"+hex.EncodeToString(credID)+":challenge", "", map[string]string{})
	if rec.Code != http.StatusCreated {
		t.Fatalf("challenge: %d %s", rec.Code, rec.Body)
	}
	var out struct {
		Nonce []byte `json:"nonce"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	return out.Nonce
}

func (f renewalFixture) renew(t *testing.T, credID, nonce, signature []byte, key string) *httptest.ResponseRecorder {
	t.Helper()
	return f.do(t, http.MethodPost, "/v1/credentials/"+hex.EncodeToString(credID)+":renew", key, map[string]string{
		"nonce": base64.StdEncoding.EncodeToString(nonce), "signature": base64.StdEncoding.EncodeToString(signature),
	})
}

func (f renewalFixture) advance(d time.Duration) {
	now := f.h.Now().Add(d)
	f.h.Now = func() time.Time { return now }
}

func TestTantanganPerpanjanganMengembalikanNonce(t *testing.T) {
	f := provisionedForRenewal(t)
	rec := f.do(t, http.MethodPost, "/v1/credentials/"+hex.EncodeToString(f.credID)+":challenge", "", map[string]string{})
	if rec.Code != http.StatusCreated {
		t.Fatalf("status %d %s", rec.Code, rec.Body)
	}
	var out struct {
		Nonce     []byte `json:"nonce"`
		ExpiresAt string `json:"expires_at"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if len(out.Nonce) != 32 {
		t.Fatalf("nonce %d B, harus 32", len(out.Nonce))
	}
	if want := f.h.Now().Add(120 * time.Second).UTC().Format(time.RFC3339); out.ExpiresAt != want {
		t.Fatalf("expires_at %s, harus %s", out.ExpiresAt, want)
	}
}

func TestPerpanjanganMenerbitkanSertifikatBaru(t *testing.T) {
	f := provisionedForRenewal(t)
	f.advance(4 * 24 * time.Hour)
	nonce := f.challenge(t, f.credID)
	rec := f.renew(t, f.credID, nonce, renewalSignature(t, f.key, f.credID, nonce), "renew-1")
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d %s", rec.Code, rec.Body)
	}
	var out struct {
		CredentialID []byte `json:"credential_id"`
		Channel      string `json:"channel"`
		Certificate  []byte `json:"certificate"`
		NotBefore    string `json:"not_before"`
		NotAfter     string `json:"not_after"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(out.CredentialID, f.credID) || out.Channel != "ble" {
		t.Fatalf("kredensial berubah: %x %s", out.CredentialID, out.Channel)
	}
	now := f.h.Now().UTC()
	if out.NotBefore != now.Format(time.RFC3339) || out.NotAfter != now.Add(7*24*time.Hour).Format(time.RFC3339) {
		t.Fatalf("masa berlaku %s–%s", out.NotBefore, out.NotAfter)
	}
	req, err := certs.Verify(out.Certificate, f.signer.Public())
	if err != nil {
		t.Fatal(err)
	}
	pub, _ := f.key.PublicKey.ECDH()
	if !bytes.Equal(req.CredentialID, f.credID) || !bytes.Equal(req.PublicKey, pub.Bytes()) || !req.NotAfter.After(f.notAfter) {
		t.Fatalf("isi sertifikat salah: %+v", req)
	}
	cert, notAfter, err := f.store.CredentialCert(context.Background(), f.credID)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(cert, out.Certificate) || !notAfter.Equal(now.Add(7*24*time.Hour)) {
		t.Fatal("database tidak memuat sertifikat baru")
	}
}

func TestPerpanjanganIdempotent(t *testing.T) {
	f := provisionedForRenewal(t)
	nonce := f.challenge(t, f.credID)
	sig := renewalSignature(t, f.key, f.credID, nonce)
	first := f.renew(t, f.credID, nonce, sig, "renew-same")
	second := f.renew(t, f.credID, nonce, sig, "renew-same")
	if first.Code != http.StatusOK || second.Code != http.StatusOK || first.Body.String() != second.Body.String() {
		t.Fatalf("retry tidak identik: %d %d", first.Code, second.Code)
	}
}

func TestNonceSekaliPakai(t *testing.T) {
	f := provisionedForRenewal(t)
	nonce := f.challenge(t, f.credID)
	sig := renewalSignature(t, f.key, f.credID, nonce)
	if rec := f.renew(t, f.credID, nonce, sig, "renew-a"); rec.Code != http.StatusOK {
		t.Fatalf("pertama: %d %s", rec.Code, rec.Body)
	}
	rec := f.renew(t, f.credID, nonce, sig, "renew-b")
	if rec.Code != http.StatusBadRequest || problemType(t, rec) != "CRED-CHALLENGE-INVALID" {
		t.Fatalf("nonce dipakai ulang: %d %s", rec.Code, rec.Body)
	}
}

func TestNonceKedaluwarsaDitolak(t *testing.T) {
	f := provisionedForRenewal(t)
	nonce := f.challenge(t, f.credID)
	f.advance(121 * time.Second)
	rec := f.renew(t, f.credID, nonce, renewalSignature(t, f.key, f.credID, nonce), "renew-late")
	if rec.Code != http.StatusBadRequest || problemType(t, rec) != "CRED-CHALLENGE-INVALID" {
		t.Fatalf("nonce kedaluwarsa diterima: %d %s", rec.Code, rec.Body)
	}
}

func TestNonceKredensialLainDitolak(t *testing.T) {
	// Review Focus 1: nonce terikat ke satu kredensial.
	a := provisionedForRenewal(t)
	b := a.fixture.provision(t)
	nonceA := a.challenge(t, a.credID)
	rec := b.renew(t, b.credID, nonceA, renewalSignature(t, b.key, b.credID, nonceA), "renew-cross")
	if rec.Code != http.StatusBadRequest || problemType(t, rec) != "CRED-CHALLENGE-INVALID" {
		t.Fatalf("nonce lintas kredensial diterima: %d %s", rec.Code, rec.Body)
	}
}

func TestTandaTanganSalahDitolak(t *testing.T) {
	f := provisionedForRenewal(t)
	nonce := f.challenge(t, f.credID)
	other, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	rec := f.renew(t, f.credID, nonce, renewalSignature(t, other, f.credID, nonce), "renew-bad")
	if rec.Code != http.StatusBadRequest || problemType(t, rec) != "CRED-PROOF-INVALID" {
		t.Fatalf("tanda tangan salah diterima: %d %s", rec.Code, rec.Body)
	}
	// Nonce hanya terpakai bila perpanjangan sukses.
	if rec := f.renew(t, f.credID, nonce, renewalSignature(t, f.key, f.credID, nonce), "renew-good"); rec.Code != http.StatusOK {
		t.Fatalf("tanda tangan benar setelah gagal: %d %s", rec.Code, rec.Body)
	}
}

func TestKredensialDitangguhkanTidakDiperpanjang(t *testing.T) {
	// Review Focus 2.
	f := provisionedForRenewal(t)
	nonce := f.challenge(t, f.credID)
	if err := f.store.SetCardInstanceStatus(context.Background(), f.enrollmentID, "SUSPENDED"); err != nil {
		t.Fatal(err)
	}
	rec := f.renew(t, f.credID, nonce, renewalSignature(t, f.key, f.credID, nonce), "renew-suspended")
	if rec.Code != http.StatusConflict || problemType(t, rec) != "CRED-NOT-RENEWABLE" {
		t.Fatalf("renew kartu ditangguhkan: %d %s", rec.Code, rec.Body)
	}
	// ADR-0027: challenge tetap boleh untuk kartu ditangguhkan (dipakai untuk hapus kartu).
	if rec := f.do(t, http.MethodPost, "/v1/credentials/"+hex.EncodeToString(f.credID)+":challenge", "", map[string]string{}); rec.Code != http.StatusCreated {
		t.Fatalf("challenge kartu ditangguhkan: %d %s", rec.Code, rec.Body)
	}
}

func TestKredensialTakDikenal(t *testing.T) {
	f := newFixture(t)
	for _, path := range []string{
		"/v1/credentials/" + hex.EncodeToString(bytes.Repeat([]byte{0x77}, 16)) + ":challenge",
		"/v1/credentials/zz:challenge",
		"/v1/credentials/" + hex.EncodeToString(bytes.Repeat([]byte{0x77}, 8)) + ":challenge",
	} {
		rec := f.do(t, http.MethodPost, path, "", map[string]string{})
		if rec.Code != http.StatusNotFound || problemType(t, rec) != "CRED-NOT-FOUND" {
			t.Fatalf("%s: %d %s", path, rec.Code, rec.Body)
		}
	}
	rec := f.do(t, http.MethodPost, "/v1/credentials/"+hex.EncodeToString(bytes.Repeat([]byte{0x77}, 16))+":rotate", "", map[string]string{})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("aksi tak dikenal: %d", rec.Code)
	}
}

func TestPerpanjanganTanpaIdempotencyKeyDitolak(t *testing.T) {
	f := provisionedForRenewal(t)
	nonce := f.challenge(t, f.credID)
	rec := f.renew(t, f.credID, nonce, renewalSignature(t, f.key, f.credID, nonce), "")
	if rec.Code != http.StatusBadRequest || problemType(t, rec) != "REQ-IDEMPOTENCY-KEY" {
		t.Fatalf("tanpa Idempotency-Key: %d %s", rec.Code, rec.Body)
	}
}

func TestProvisioningMengembalikanNotBefore(t *testing.T) {
	f := newFixture(t)
	id := f.enroll(t)
	rec := f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "prov-nb", map[string]string{
		"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(phoneKey(t)),
	})
	var out struct {
		NotBefore string `json:"not_before"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if out.NotBefore != f.h.Now().UTC().Format(time.RFC3339) {
		t.Fatalf("not_before = %q", out.NotBefore)
	}
}

func TestNonceKedaluwarsaDibersihkan(t *testing.T) {
	f := provisionedForRenewal(t)
	f.challenge(t, f.credID)
	f.advance(10 * time.Minute)
	f.challenge(t, f.credID) // masih berlaku
	n, err := f.store.PurgeRenewalChallenges(context.Background(), f.h.Now())
	if err != nil || n != 1 {
		t.Fatalf("purge = %d, %v; harus 1", n, err)
	}
}

func TestKanalDimatikanTidakDiperpanjang(t *testing.T) {
	// Review perpanjangan I3: kill switch kanal (FR-04) juga menghentikan perpanjangan.
	f := provisionedForRenewal(t)
	nonce := f.challenge(t, f.credID)
	f.handlerConfig(t, []string{"nfcHCE"})
	rec := f.renew(t, f.credID, nonce, renewalSignature(t, f.key, f.credID, nonce), "renew-killed")
	if rec.Code != http.StatusConflict || problemType(t, rec) != "CRED-NOT-RENEWABLE" {
		t.Fatalf("renew kanal mati: %d %s", rec.Code, rec.Body)
	}
	// Challenge tetap boleh: nonce juga dipakai untuk hapus kartu (ADR-0026), dan pengguna harus
	// tetap bisa menghapus kartu di kanal yang dimatikan.
	if rec := f.do(t, http.MethodPost, "/v1/credentials/"+hex.EncodeToString(f.credID)+":challenge", "", map[string]string{}); rec.Code != http.StatusCreated {
		t.Fatalf("challenge kanal mati: %d %s", rec.Code, rec.Body)
	}
}

func TestKredensialDicabutTidakDiperpanjang(t *testing.T) {
	// Review perpanjangan M1: status kredensial (bukan card instance) juga dihormati.
	f := provisionedForRenewal(t)
	nonce := f.challenge(t, f.credID)
	f.exec(t, `UPDATE credentials SET status = 'REVOKED'`)
	rec := f.renew(t, f.credID, nonce, renewalSignature(t, f.key, f.credID, nonce), "renew-revoked")
	if rec.Code != http.StatusConflict || problemType(t, rec) != "CRED-NOT-RENEWABLE" {
		t.Fatalf("renew dicabut: %d %s", rec.Code, rec.Body)
	}
	rec = f.do(t, http.MethodPost, "/v1/credentials/"+hex.EncodeToString(f.credID)+":challenge", "", map[string]string{})
	if rec.Code != http.StatusGone || problemType(t, rec) != "CARD-GONE" {
		t.Fatalf("challenge dicabut: %d %s", rec.Code, rec.Body)
	}
}

func TestChallengeMemuatIDKartu(t *testing.T) {
	// Review hapus kartu C1 (rekomendasi 1): app tidak perlu menyimpan ID kartu server.
	f := provisionedForRenewal(t)
	rec := f.do(t, http.MethodPost, "/v1/credentials/"+hex.EncodeToString(f.credID)+":challenge", "", map[string]string{})
	var out struct {
		CardInstanceID string `json:"card_instance_id"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil || out.CardInstanceID != f.enrollmentID {
		t.Fatalf("card_instance_id = %q, ingin %q (%v)", out.CardInstanceID, f.enrollmentID, err)
	}
}

func hexString(b []byte) string { return hex.EncodeToString(b) }
