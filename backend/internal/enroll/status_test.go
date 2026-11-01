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
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// newStatusToken membuat token baca status seperti app (ADR-0037): header bearer base64url dan hash
// base64 untuk body.
func newStatusToken(t *testing.T) (token []byte, header, hashB64 string) {
	t.Helper()
	token = make([]byte, 32)
	if _, err := rand.Read(token); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(token)
	return token, "Bearer " + base64.RawURLEncoding.EncodeToString(token), base64.StdEncoding.EncodeToString(sum[:])
}

func (f fixture) cardStatus(t *testing.T, id, authorization string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/v1/cards/"+id+"/status", nil)
	if authorization != "" {
		req.Header.Set("Authorization", authorization)
	}
	rec := httptest.NewRecorder()
	f.handler.ServeHTTP(rec, req)
	return rec
}

func statusValue(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	var out struct {
		Status string `json:"status"`
	}
	if rec.Code != http.StatusOK || json.Unmarshal(rec.Body.Bytes(), &out) != nil {
		t.Fatalf("status kartu: %d %s", rec.Code, rec.Body)
	}
	return out.Status
}

// provisionWithStatusToken memprovisikan kartu BLE dengan hash token baca status di body.
func (f fixture) provisionWithStatusToken(t *testing.T, hashB64 string) renewalFixture {
	t.Helper()
	id := f.enroll(t)
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	pub, _ := key.PublicKey.ECDH()
	rec := f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "prov-token-"+id, map[string]string{
		"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(pub.Bytes()), "status_token_hash": hashB64,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("provisioning: %d %s", rec.Code, rec.Body)
	}
	var out struct {
		CredentialID []byte `json:"credential_id"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	return renewalFixture{fixture: f, enrollmentID: id, credID: out.CredentialID, key: key}
}

func TestProvisioningMenyimpanHashTokenStatus(t *testing.T) {
	// ADR-0037: hash token dari app disimpan saat provisioning; token dipakai membaca status.
	f := newFixture(t)
	_, header, hashB64 := newStatusToken(t)
	card := f.provisionWithStatusToken(t, hashB64)
	if got := statusValue(t, f.cardStatus(t, card.enrollmentID, header)); got != "ACTIVE" {
		t.Fatalf("status = %q", got)
	}
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	pub, _ := key.PublicKey.ECDH()
	short := base64.StdEncoding.EncodeToString(make([]byte, 31))
	rec := f.do(t, http.MethodPost, "/v1/enrollments/"+f.enroll(t)+"/credentials", "prov-pendek", map[string]string{
		"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(pub.Bytes()), "status_token_hash": short,
	})
	if rec.Code != http.StatusBadRequest || problemType(t, rec) != "REQ-INVALID" {
		t.Fatalf("hash 31 byte: %d %s", rec.Code, rec.Body)
	}
	// Pengulangan Idempotency-Key dengan hash token lain tidak boleh memakai respons lama.
	_, _, otherHash := newStatusToken(t)
	rec = f.do(t, http.MethodPost, "/v1/enrollments/"+card.enrollmentID+"/credentials", "prov-token-"+card.enrollmentID, map[string]string{
		"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(mustPub(t, card.key)), "status_token_hash": otherHash,
	})
	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("pengulangan dengan hash lain: %d %s", rec.Code, rec.Body)
	}
}

func mustPub(t *testing.T, key *ecdsa.PrivateKey) []byte {
	t.Helper()
	pub, err := key.PublicKey.ECDH()
	if err != nil {
		t.Fatal(err)
	}
	return pub.Bytes()
}

func TestPerpanjanganMenggantiHashTokenStatus(t *testing.T) {
	// ADR-0037: kartu lama tanpa token mendapat token lewat perpanjangan bertanda tangan.
	f := provisionedForRenewal(t)
	_, header, hashB64 := newStatusToken(t)
	if rec := f.cardStatus(t, f.enrollmentID, header); rec.Code != http.StatusNotFound {
		t.Fatalf("sebelum perpanjangan: %d %s", rec.Code, rec.Body)
	}
	nonce := f.challenge(t, f.credID)
	rec := f.do(t, http.MethodPost, "/v1/credentials/"+hex.EncodeToString(f.credID)+":renew", "renew-token", map[string]string{
		"nonce":             base64.StdEncoding.EncodeToString(nonce),
		"signature":         base64.StdEncoding.EncodeToString(renewalSignature(t, f.key, f.credID, nonce)),
		"status_token_hash": hashB64,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("perpanjangan: %d %s", rec.Code, rec.Body)
	}
	if got := statusValue(t, f.cardStatus(t, f.enrollmentID, header)); got != "ACTIVE" {
		t.Fatalf("status = %q", got)
	}
	nonce = f.challenge(t, f.credID)
	rec = f.do(t, http.MethodPost, "/v1/credentials/"+hex.EncodeToString(f.credID)+":renew", "renew-pendek", map[string]string{
		"nonce":             base64.StdEncoding.EncodeToString(nonce),
		"signature":         base64.StdEncoding.EncodeToString(renewalSignature(t, f.key, f.credID, nonce)),
		"status_token_hash": base64.StdEncoding.EncodeToString(make([]byte, 31)),
	})
	if rec.Code != http.StatusBadRequest || problemType(t, rec) != "REQ-INVALID" {
		t.Fatalf("hash 31 byte: %d %s", rec.Code, rec.Body)
	}
}

func TestStatusKartuTidakBerlakuIdentik(t *testing.T) {
	// Review Focus 1: semua kegagalan dijawab sama, sehingga endpoint tidak membocorkan card id.
	f := newFixture(t)
	_, header, hashB64 := newStatusToken(t)
	card := f.provisionWithStatusToken(t, hashB64)
	_, wrongHeader, _ := newStatusToken(t)
	withoutToken := f.provision(t)
	cases := map[string]*httptest.ResponseRecorder{
		"bukan uuid":           f.cardStatus(t, "bukan-uuid", header),
		"tak dikenal":          f.cardStatus(t, "00000000-0000-4000-8000-000000000000", header),
		"tanpa header":         f.cardStatus(t, card.enrollmentID, ""),
		"bukan bearer":         f.cardStatus(t, card.enrollmentID, "Basic "+strings.TrimPrefix(header, "Bearer ")),
		"base64 rusak":         f.cardStatus(t, card.enrollmentID, "Bearer !!!"),
		"token salah":          f.cardStatus(t, card.enrollmentID, wrongHeader),
		"token pendek":         f.cardStatus(t, card.enrollmentID, "Bearer "+base64.RawURLEncoding.EncodeToString(make([]byte, 16))),
		"instance tanpa token": f.cardStatus(t, withoutToken.enrollmentID, header),
	}
	var reference []byte
	for name, rec := range cases {
		if rec.Code != http.StatusNotFound || problemType(t, rec) != "CARD-NOT-FOUND" {
			t.Errorf("%s: %d %s", name, rec.Code, rec.Body)
		}
		if reference == nil {
			reference = rec.Body.Bytes()
		} else if !bytes.Equal(reference, rec.Body.Bytes()) {
			t.Errorf("%s: body berbeda: %s vs %s", name, rec.Body, reference)
		}
	}
	if got := statusValue(t, f.cardStatus(t, card.enrollmentID, header)); got != "ACTIVE" {
		t.Fatalf("token benar: %q", got)
	}
}

func TestPerpanjanganDitolakSetelahDitangguhkan(t *testing.T) {
	// Review Focus 4: kartu yang ditangguhkan operator tidak bisa diperpanjang, dan app membaca statusnya.
	f := newFixture(t)
	_, header, hashB64 := newStatusToken(t)
	card := f.provisionWithStatusToken(t, hashB64)
	if err := f.store.SuspendCard(context.Background(), card.enrollmentID, "staf-01", f.h.Now()); err != nil {
		t.Fatal(err)
	}
	nonce := card.challenge(t, card.credID)
	if rec := card.renew(t, card.credID, nonce, renewalSignature(t, card.key, card.credID, nonce), "renew-ditangguhkan"); rec.Code != http.StatusConflict || problemType(t, rec) != "CRED-NOT-RENEWABLE" {
		t.Fatalf("perpanjangan: %d %s", rec.Code, rec.Body)
	}
	if got := statusValue(t, f.cardStatus(t, card.enrollmentID, header)); got != "SUSPENDED" {
		t.Fatalf("status = %q", got)
	}
}

func TestTokenStatusTidakBocor(t *testing.T) {
	// Review Focus 2: token mentah tidak muncul di log, database, maupun baris idempotency.
	f := newFixture(t)
	var logs bytes.Buffer
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewTextHandler(&logs, &slog.HandlerOptions{Level: slog.LevelDebug})))
	t.Cleanup(func() { slog.SetDefault(previous) })
	token, header, hashB64 := newStatusToken(t)
	card := f.provisionWithStatusToken(t, hashB64)
	statusValue(t, f.cardStatus(t, card.enrollmentID, header))
	f.cardStatus(t, card.enrollmentID, header+"x")
	encoded := []string{base64.RawURLEncoding.EncodeToString(token), base64.StdEncoding.EncodeToString(token), hex.EncodeToString(token)}
	for _, text := range []string{logs.String(), allTablesText(t, f.dsn)} {
		for _, form := range encoded {
			// allTablesText menurunkan huruf seluruh dump, jadi bentuk huruf kecil juga dicari.
			if strings.Contains(text, form) || strings.Contains(text, strings.ToLower(form)) {
				t.Fatalf("token baca status mentah bocor dalam bentuk %q", form)
			}
		}
	}
}

func TestProvisioningTidakMenimpaHashTokenStatus(t *testing.T) {
	// Review akhir I1: provisioning hanya dilindungi id instance (bisa didapat dari :challenge), jadi
	// hanya boleh memasang hash bila belum ada. Penggantian hanya lewat perpanjangan bertanda tangan.
	f := newFixture(t)
	_, header, hashB64 := newStatusToken(t)
	card := f.provisionWithStatusToken(t, hashB64)
	_, attackerHeader, attackerHash := newStatusToken(t)
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	rec := f.do(t, http.MethodPost, "/v1/enrollments/"+card.enrollmentID+"/credentials", "prov-kanal-kedua", map[string]string{
		"channel": "nfcHCE", "public_key": base64.StdEncoding.EncodeToString(mustPub(t, key)), "status_token_hash": attackerHash,
	})
	// ADR-0040: kanal kedua untuk kartu aktif kini ditolak seluruhnya, jadi hash tidak mungkin diganti.
	if rec.Code != http.StatusNotFound {
		t.Fatalf("provisioning kanal kedua: %d %s", rec.Code, rec.Body)
	}
	if got := statusValue(t, f.cardStatus(t, card.enrollmentID, header)); got != "ACTIVE" {
		t.Fatalf("token pemilik = %q", got)
	}
	if rec := f.cardStatus(t, card.enrollmentID, attackerHeader); rec.Code != http.StatusNotFound {
		t.Fatalf("hash pengganti diterima: %d %s", rec.Code, rec.Body)
	}
}

func TestPerpanjanganTidakMembocorkanPenangguhan(t *testing.T) {
	// Review akhir M2 (ADR-0037 requirement 1): tanpa kunci kredensial, kartu ditangguhkan dan aktif
	// dijawab sama; status hanya terlihat setelah nonce dan tanda tangan valid.
	answers := map[string][]string{}
	for _, suspended := range []bool{false, true} {
		f := newFixture(t)
		_, _, hashB64 := newStatusToken(t)
		card := f.provisionWithStatusToken(t, hashB64)
		if suspended {
			if err := f.store.SuspendCard(context.Background(), card.enrollmentID, "staf-01", f.h.Now()); err != nil {
				t.Fatal(err)
			}
		}
		nonce := card.challenge(t, card.credID)
		badSig := card.renew(t, card.credID, nonce, make([]byte, 64), "renew-sig-sampah")
		badNonce := card.renew(t, card.credID, make([]byte, 32), renewalSignature(t, card.key, card.credID, make([]byte, 32)), "renew-nonce-sampah")
		key := map[bool]string{false: "aktif", true: "ditangguhkan"}[suspended]
		answers[key] = []string{badSig.Body.String(), badNonce.Body.String()}
		if badSig.Code != http.StatusBadRequest || badNonce.Code != http.StatusBadRequest {
			t.Errorf("%s: tanda tangan sampah %d, nonce sampah %d", key, badSig.Code, badNonce.Code)
		}
	}
	if strings.Join(answers["aktif"], "|") != strings.Join(answers["ditangguhkan"], "|") {
		t.Fatalf("jawaban berbeda: %v vs %v", answers["aktif"], answers["ditangguhkan"])
	}
}
