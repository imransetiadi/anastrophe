package enroll

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func revokeSignature(t *testing.T, key *ecdsa.PrivateKey, credID, nonce []byte, cardID string) []byte {
	t.Helper()
	msg := append(append(append([]byte("ANP1-REVOKE"), credID...), nonce...), []byte(strings.ToLower(cardID))...)
	digest := sha256.Sum256(msg)
	r, s, err := ecdsa.Sign(rand.Reader, key, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return sig
}

func (f renewalFixture) deleteCard(t *testing.T, cardID string, credID, nonce, sig []byte, key string) *httptest.ResponseRecorder {
	t.Helper()
	return f.do(t, http.MethodDelete, "/v1/cards/"+cardID, key, map[string]string{
		"credential_id": base64.StdEncoding.EncodeToString(credID),
		"nonce":         base64.StdEncoding.EncodeToString(nonce),
		"signature":     base64.StdEncoding.EncodeToString(sig),
	})
}

func (f renewalFixture) deleteOwnCard(t *testing.T, key string) *httptest.ResponseRecorder {
	t.Helper()
	nonce := f.challenge(t, f.credID)
	return f.deleteCard(t, f.enrollmentID, f.credID, nonce, revokeSignature(t, f.key, f.credID, nonce, f.enrollmentID), key)
}

func TestHapusKartuMencabutDanMencatatAudit(t *testing.T) {
	f := provisionedForRenewal(t)
	if rec := f.deleteOwnCard(t, "del-1"); rec.Code != http.StatusNoContent {
		t.Fatalf("hapus: %d %s", rec.Code, rec.Body)
	}
	// Kredensial dicabut: tidak bisa diperpanjang lagi.
	rec := f.do(t, http.MethodPost, "/v1/credentials/"+hexString(f.credID)+":challenge", "", map[string]string{})
	if rec.Code != http.StatusGone || problemType(t, rec) != "CARD-GONE" {
		t.Fatalf("challenge setelah hapus: %d %s", rec.Code, rec.Body)
	}
	events := f.audit(t)
	last := events[len(events)-1]
	if last.Action != "credential.revoked" || last.Data["reason"] != "user_deleted" || last.Data["channel"] != "ble" {
		t.Fatalf("audit: %+v", last)
	}
}

func TestHapusKartuMembebaskanSlot(t *testing.T) {
	// Review Focus 2: kartu yang dihapus tidak lagi memakai slot batas 8 kartu (FR-15).
	f := provisionedForRenewal(t)
	for i := 0; i < 7; i++ {
		f.enroll(t)
	}
	if rec := f.do(t, http.MethodPost, "/v1/enrollments", "", map[string]string{"device_id": f.deviceID, "site_id": f.siteID}); rec.Code != http.StatusConflict {
		t.Fatalf("kartu ke-9: %d", rec.Code)
	}
	if rec := f.deleteOwnCard(t, "del-slot"); rec.Code != http.StatusNoContent {
		t.Fatalf("hapus: %d %s", rec.Code, rec.Body)
	}
	if rec := f.do(t, http.MethodPost, "/v1/enrollments", "", map[string]string{"device_id": f.deviceID, "site_id": f.siteID}); rec.Code != http.StatusCreated {
		t.Fatalf("enrol setelah hapus: %d %s", rec.Code, rec.Body)
	}
}

func TestHapusDenganKredensialKartuLainDitolak(t *testing.T) {
	// Review Focus 1.
	a := provisionedForRenewal(t)
	b := a.fixture.provision(t)
	nonce := a.challenge(t, a.credID)
	rec := a.deleteCard(t, b.enrollmentID, a.credID, nonce, revokeSignature(t, a.key, a.credID, nonce, b.enrollmentID), "del-cross")
	if rec.Code != http.StatusBadRequest || problemType(t, rec) != "CRED-PROOF-INVALID" {
		t.Fatalf("hapus kartu lain: %d %s", rec.Code, rec.Body)
	}
}

func TestHapusTandaTanganSalahDitolak(t *testing.T) {
	f := provisionedForRenewal(t)
	nonce := f.challenge(t, f.credID)
	other, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	rec := f.deleteCard(t, f.enrollmentID, f.credID, nonce, revokeSignature(t, other, f.credID, nonce, f.enrollmentID), "del-bad")
	if rec.Code != http.StatusBadRequest || problemType(t, rec) != "CRED-PROOF-INVALID" {
		t.Fatalf("tanda tangan salah: %d %s", rec.Code, rec.Body)
	}
	if rec := f.deleteCard(t, f.enrollmentID, f.credID, nonce, revokeSignature(t, f.key, f.credID, nonce, f.enrollmentID), "del-good"); rec.Code != http.StatusNoContent {
		t.Fatalf("tanda tangan benar: %d %s", rec.Code, rec.Body)
	}
}

func TestHapusKartuDuaKaliGone(t *testing.T) {
	f := provisionedForRenewal(t)
	nonce := f.challenge(t, f.credID)
	sig := revokeSignature(t, f.key, f.credID, nonce, f.enrollmentID)
	if rec := f.deleteCard(t, f.enrollmentID, f.credID, nonce, sig, "del-a"); rec.Code != http.StatusNoContent {
		t.Fatalf("pertama: %d", rec.Code)
	}
	rec := f.deleteCard(t, f.enrollmentID, f.credID, nonce, sig, "del-b")
	if rec.Code != http.StatusGone || problemType(t, rec) != "CARD-GONE" {
		t.Fatalf("kedua: %d %s", rec.Code, rec.Body)
	}
}

func TestHapusValidasiPermintaan(t *testing.T) {
	f := provisionedForRenewal(t)
	nonce := f.challenge(t, f.credID)
	sig := revokeSignature(t, f.key, f.credID, nonce, f.enrollmentID)
	if rec := f.deleteCard(t, f.enrollmentID, f.credID, nonce, sig, ""); rec.Code != http.StatusBadRequest || problemType(t, rec) != "REQ-IDEMPOTENCY-KEY" {
		t.Fatalf("tanpa key: %d %s", rec.Code, rec.Body)
	}
	if rec := f.deleteCard(t, "6f1c2a9e-0000-4000-8000-000000000099", f.credID, nonce, sig, "del-unknown"); rec.Code != http.StatusGone || problemType(t, rec) != "CARD-GONE" {
		t.Fatalf("kartu tak dikenal: %d %s", rec.Code, rec.Body)
	}
}

func TestHapusKartuDitangguhkan(t *testing.T) {
	// ADR-0027: kartu SUSPENDED bisa dihapus pemiliknya, slot terbebas.
	f := provisionedForRenewal(t)
	if err := f.store.SetCardInstanceStatus(context.Background(), f.enrollmentID, "SUSPENDED"); err != nil {
		t.Fatal(err)
	}
	if rec := f.deleteOwnCard(t, "del-suspended"); rec.Code != http.StatusNoContent {
		t.Fatalf("hapus kartu ditangguhkan: %d %s", rec.Code, rec.Body)
	}
	rec := f.do(t, http.MethodPost, "/v1/credentials/"+hexString(f.credID)+":challenge", "", map[string]string{})
	if rec.Code != http.StatusGone {
		t.Fatalf("setelah hapus: %d %s", rec.Code, rec.Body)
	}
}
