package enroll

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/certs"
	"github.com/imransetiadi/anastrophe/backend/internal/httpapi"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
	"github.com/imransetiadi/anastrophe/backend/internal/testpg"
)

var adminDSN string

func TestMain(m *testing.M) {
	dsn, stop, err := testpg.Start()
	if err != nil && !errors.Is(err, testpg.ErrUnavailable) {
		fmt.Println(err)
		os.Exit(1)
	}
	adminDSN = dsn
	code := m.Run()
	stop()
	os.Exit(code)
}

type fixture struct {
	h        *Handler
	handler  http.Handler
	store    *store.Store
	signer   *certs.SoftwareSigner
	siteID   string
	deviceID string
	groupID  []byte
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	return newFixtureWithPool(t, "")
}

// newFixtureWithPool membuka store dengan parameter pool tertentu (mis. "pool_max_conns=2").
func newFixtureWithPool(t *testing.T, poolParams string) fixture {
	t.Helper()
	if adminDSN == "" {
		t.Skip("PostgreSQL tidak tersedia")
	}
	ctx := context.Background()
	dsn, err := testpg.NewDatabase(ctx, adminDSN)
	if err != nil {
		t.Fatal(err)
	}
	if poolParams != "" {
		dsn += "&" + poolParams
	}
	s, err := store.Open(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(s.Close)
	if err := s.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	orgID, _ := s.CreateOrganization(ctx, "Org", "ID")
	siteID, err := s.CreateSite(ctx, orgID, "Menara Uji", "ID", "Asia/Jakarta", []byte{1, 2, 3, 4, 5, 6, 7, 8})
	if err != nil {
		t.Fatal(err)
	}
	groupKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	groupPub, _ := groupKey.PublicKey.ECDH()
	groupID := []byte{0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8}
	if err := s.AddReaderGroup(ctx, groupID, siteID, groupPub.Bytes()); err != nil {
		t.Fatal(err)
	}
	deviceID, _ := s.CreateDevice(ctx)
	caKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	signer := certs.NewSoftwareSigner(caKey)
	h := &Handler{
		Store:           s,
		Signers:         func(string) (certs.Signer, error) { return signer, nil },
		Now:             func() time.Time { return time.Unix(1_794_000_000, 0) },
		Validity:        7 * 24 * time.Hour,
		EnabledChannels: []string{"ble", "nfcHCE"},
	}
	return fixture{
		h:        h,
		handler:  httpapi.New(httpapi.Config{}, httpapi.Deps{Routes: h.Register}),
		store:    s,
		signer:   signer,
		siteID:   siteID,
		deviceID: deviceID,
		groupID:  groupID,
	}
}

func (f fixture) handlerConfig(t *testing.T, channels []string) {
	t.Helper()
	f.h.EnabledChannels = channels
}

func (f fixture) do(t *testing.T, method, path, idempotencyKey string, body any) *httptest.ResponseRecorder {
	t.Helper()
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest(method, path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	if idempotencyKey != "" {
		req.Header.Set("Idempotency-Key", idempotencyKey)
	}
	rec := httptest.NewRecorder()
	f.handler.ServeHTTP(rec, req)
	return rec
}

func (f fixture) doRaw(t *testing.T, path, idempotencyKey, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Idempotency-Key", idempotencyKey)
	rec := httptest.NewRecorder()
	f.handler.ServeHTTP(rec, req)
	return rec
}

func (f fixture) enroll(t *testing.T) string {
	t.Helper()
	rec := f.do(t, http.MethodPost, "/v1/enrollments", "", map[string]string{"device_id": f.deviceID, "site_id": f.siteID})
	if rec.Code != http.StatusCreated {
		t.Fatalf("enrol: %d %s", rec.Code, rec.Body)
	}
	var out struct {
		EnrollmentID string `json:"enrollment_id"`
	}
	json.Unmarshal(rec.Body.Bytes(), &out)
	return out.EnrollmentID
}

func phoneKey(t *testing.T) []byte {
	t.Helper()
	k, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	pub, _ := k.PublicKey.ECDH()
	return pub.Bytes()
}

func problemType(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	var p httpapi.Problem
	if err := json.Unmarshal(rec.Body.Bytes(), &p); err != nil {
		t.Fatalf("bukan problem+json: %s", rec.Body)
	}
	return p.Type
}

func TestProvisioningMengembalikanKontrakApp(t *testing.T) {
	f := newFixture(t)
	id, pub := f.enroll(t), phoneKey(t)
	rec := f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "k-1", map[string]string{"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(pub)})
	if rec.Code < 200 || rec.Code > 299 {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	var raw map[string]json.RawMessage
	json.Unmarshal(rec.Body.Bytes(), &raw)
	keys := make([]string, 0, len(raw))
	for k := range raw {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	if got := strings.Join(keys, ","); got != "certificate,channel,credential_id,group_keys,not_after,site_name,zones" {
		t.Fatalf("kunci JSON berbeda dengan kontrak app ProvisionedCredential: %s", got)
	}
	var body struct {
		CredentialID []byte              `json:"credential_id"`
		Channel      string              `json:"channel"`
		Certificate  []byte              `json:"certificate"`
		NotAfter     string              `json:"not_after"`
		SiteName     string              `json:"site_name"`
		GroupKeys    map[string][][]byte `json:"group_keys"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.NotAfter != "2026-11-13T21:20:00Z" || body.Channel != "ble" || body.SiteName != "Menara Uji" || len(body.CredentialID) != 16 {
		t.Fatalf("isi respons tidak sesuai: %+v", body)
	}
	if keys := body.GroupKeys[hex.EncodeToString(f.groupID)]; len(keys) != 1 || len(keys[0]) != 65 {
		t.Fatalf("group_keys = %v", body.GroupKeys)
	}
	cert, err := certs.Verify(body.Certificate, f.signer.Public())
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(cert.PublicKey, pub) || !bytes.Equal(cert.CredentialID, body.CredentialID) || !bytes.Equal(cert.SiteID, []byte{1, 2, 3, 4, 5, 6, 7, 8}) {
		t.Fatal("sertifikat tidak cocok dengan permintaan")
	}
}

func TestIdempotencyKeySama(t *testing.T) {
	// Review Focus 2: ketukan ganda → satu kredensial, respons identik.
	f := newFixture(t)
	id := f.enroll(t)
	body := map[string]string{"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(phoneKey(t))}
	var wg sync.WaitGroup
	responses := make([]string, 3)
	for i := range responses {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			responses[i] = f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "sama", body).Body.String()
		}(i)
	}
	wg.Wait()
	if responses[0] != responses[1] || responses[1] != responses[2] {
		t.Fatal("respons berbeda untuk Idempotency-Key yang sama")
	}
	if n, err := f.store.CredentialCount(context.Background(), id); err != nil || n != 1 {
		t.Fatalf("kredensial tersimpan = %d (err %v), ingin 1", n, err)
	}
}

func TestIdempotencyKeyBedaBodyDitolak(t *testing.T) {
	f := newFixture(t)
	id := f.enroll(t)
	path := "/v1/enrollments/" + id + "/credentials"
	f.do(t, http.MethodPost, path, "k", map[string]string{"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(phoneKey(t))})
	rec := f.do(t, http.MethodPost, path, "k", map[string]string{"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(phoneKey(t))})
	if rec.Code != http.StatusUnprocessableEntity || problemType(t, rec) != "REQ-IDEMPOTENCY-CONFLICT" {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
}

func TestTanpaIdempotencyKeyDitolak(t *testing.T) {
	f := newFixture(t)
	id := f.enroll(t)
	rec := f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "", map[string]string{"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(phoneKey(t))})
	if rec.Code != http.StatusBadRequest || problemType(t, rec) != "REQ-IDEMPOTENCY-KEY" {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
}

func TestKunciPublikTidakValidDitolak(t *testing.T) {
	// Review Focus 4.
	f := newFixture(t)
	id := f.enroll(t)
	offCurve := append([]byte{0x04}, bytes.Repeat([]byte{0x01}, 64)...)
	for i, key := range [][]byte{offCurve, {0x04, 0x01}} {
		rec := f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", fmt.Sprintf("bad-%d", i), map[string]string{"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(key)})
		if rec.Code != http.StatusBadRequest || problemType(t, rec) != "ENR-INVALID-KEY" {
			t.Fatalf("kunci %d: status %d: %s", i, rec.Code, rec.Body)
		}
	}
	if n, _ := f.store.CredentialCount(context.Background(), id); n != 0 {
		t.Fatalf("kredensial diterbitkan untuk kunci tidak valid: %d", n)
	}
}

func TestTidakDeadlockSaatPermintaanMelebihiPool(t *testing.T) {
	// Temuan review C1: Idempotent tidak boleh butuh koneksi kedua selagi memegang lock.
	f := newFixtureWithPool(t, "pool_max_conns=2")
	const requests = 6
	ids := make([]string, requests)
	for i := range ids {
		ids[i] = f.enroll(t)
	}
	done := make(chan int, requests)
	for i := 0; i < requests; i++ {
		go func(i int) {
			rec := f.do(t, http.MethodPost, "/v1/enrollments/"+ids[i]+"/credentials", fmt.Sprintf("pool-%d", i), map[string]string{"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(phoneKey(t))})
			done <- rec.Code
		}(i)
	}
	deadline := time.After(10 * time.Second)
	for i := 0; i < requests; i++ {
		select {
		case code := <-done:
			if code != http.StatusOK {
				t.Fatalf("status %d", code)
			}
		case <-deadline:
			t.Fatalf("deadlock: hanya %d dari %d permintaan selesai", i, requests)
		}
	}
}

func TestStatusKartuTidakBolehDiprovisikan(t *testing.T) {
	// Temuan review I2: kartu ditangguhkan/dicabut tidak mendapat sertifikat baru (SDD §8.2).
	f := newFixture(t)
	for _, status := range []string{"PENDING_APPROVAL", "SUSPENDED", "REVOKED", "DELETED"} {
		id := f.enroll(t)
		if err := f.store.SetCardInstanceStatus(context.Background(), id, status); err != nil {
			t.Fatal(err)
		}
		rec := f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "status-"+status, map[string]string{"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(phoneKey(t))})
		if rec.Code != http.StatusConflict || problemType(t, rec) != "ENR-NOT-PROVISIONABLE" {
			t.Fatalf("%s: status %d: %s", status, rec.Code, rec.Body)
		}
		if n, _ := f.store.CredentialCount(context.Background(), id); n != 0 {
			t.Fatalf("%s: kredensial diterbitkan", status)
		}
	}
}

func TestSatuKredensialPerKanal(t *testing.T) {
	// Temuan review I2: kunci lain untuk kanal yang sama tidak boleh mendapat sertifikat kedua.
	f := newFixture(t)
	id := f.enroll(t)
	path := "/v1/enrollments/" + id + "/credentials"
	if rec := f.do(t, http.MethodPost, path, "c-1", map[string]string{"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(phoneKey(t))}); rec.Code != http.StatusOK {
		t.Fatalf("pertama: %d %s", rec.Code, rec.Body)
	}
	rec := f.do(t, http.MethodPost, path, "c-2", map[string]string{"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(phoneKey(t))})
	if rec.Code != http.StatusConflict || problemType(t, rec) != "ENR-CHANNEL-EXISTS" {
		t.Fatalf("kedua: %d %s", rec.Code, rec.Body)
	}
	if rec := f.do(t, http.MethodPost, path, "c-3", map[string]string{"channel": "nfcHCE", "public_key": base64.StdEncoding.EncodeToString(phoneKey(t))}); rec.Code != http.StatusOK {
		t.Fatalf("kanal lain harus boleh: %d %s", rec.Code, rec.Body)
	}
	if n, _ := f.store.CredentialCount(context.Background(), id); n != 2 {
		t.Fatalf("kredensial = %d, ingin 2", n)
	}
}

func TestIdempotencyKeyTidakValidDitolak400(t *testing.T) {
	// Minor 1: key non-UTF-8 atau berkarakter aneh → 400, bukan 500 dari Postgres.
	f := newFixture(t)
	id := f.enroll(t)
	for _, key := range []string{"\xff\xfe", "ada spasi", strings.Repeat("a", 129)} {
		rec := f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", key, map[string]string{"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(phoneKey(t))})
		if rec.Code != http.StatusBadRequest || problemType(t, rec) != "REQ-IDEMPOTENCY-KEY" {
			t.Fatalf("key %q: status %d: %s", key, rec.Code, rec.Body)
		}
	}
}

func TestBodyTerlaluBesarDitolak413(t *testing.T) {
	// Minor 10: body > 4 KiB tidak boleh dipotong diam-diam lalu diproses.
	f := newFixture(t)
	id := f.enroll(t)
	padding := strings.Repeat(" ", 5000)
	raw := `{"channel":"ble","public_key":"` + base64.StdEncoding.EncodeToString(phoneKey(t)) + `"}` + padding + "sampah"
	req := httptest.NewRequest(http.MethodPost, "/v1/enrollments/"+id+"/credentials", strings.NewReader(raw))
	req.Header.Set("Idempotency-Key", "besar")
	rec := httptest.NewRecorder()
	f.handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusRequestEntityTooLarge || problemType(t, rec) != "REQ-TOO-LARGE" {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
}

func TestHashPermintaanKanonik(t *testing.T) {
	// Minor 8: urutan kunci JSON berbeda (klien Swift tanpa .sortedKeys) tetap dianggap sama.
	f := newFixture(t)
	id := f.enroll(t)
	pub := base64.StdEncoding.EncodeToString(phoneKey(t))
	path := "/v1/enrollments/" + id + "/credentials"
	first := f.doRaw(t, path, "urutan", `{"channel":"ble","public_key":"`+pub+`"}`)
	second := f.doRaw(t, path, "urutan", `{"public_key":"`+pub+`","channel":"ble"}`)
	if first.Code != http.StatusOK || second.Code != http.StatusOK || first.Body.String() != second.Body.String() {
		t.Fatalf("pertama %d, kedua %d: %s", first.Code, second.Code, second.Body)
	}
}

func TestRespons4xxTidakDisimpanSebagaiIdempoten(t *testing.T) {
	// Minor 9: hanya 2xx yang disimpan, agar penyerang tak bisa menumbuhkan tabel dengan 4xx.
	f := newFixture(t)
	id := f.enroll(t)
	f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "salah", map[string]string{"channel": "ble", "public_key": "bukan-base64"})
	if n, err := f.store.IdempotencyKeyCount(context.Background()); err != nil || n != 0 {
		t.Fatalf("baris idempotency = %d (err %v), ingin 0", n, err)
	}
}

func provision(t *testing.T, f fixture, key string) (*httptest.ResponseRecorder, certs.Request) {
	t.Helper()
	id := f.enroll(t)
	rec := f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", key, map[string]string{"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(phoneKey(t))})
	var body struct {
		Certificate []byte `json:"certificate"`
	}
	json.Unmarshal(rec.Body.Bytes(), &body)
	cert, _ := certs.Verify(body.Certificate, f.signer.Public())
	return rec, cert
}

func TestZonaTanpaKebijakanTertutup(t *testing.T) {
	// Minor 6: gedung tanpa kebijakan zona tidak boleh memberi akses ke bit 0 (fail-closed).
	f := newFixture(t)
	rec, cert := provision(t, f, "zona-0")
	if rec.Code != http.StatusOK || cert.Zones != 0 {
		t.Fatalf("status %d, zones %d (ingin 0)", rec.Code, cert.Zones)
	}
	if !strings.Contains(rec.Body.String(), `"zones":[]`) {
		t.Fatalf("zones harus [] bukan null: %s", rec.Body)
	}
}

func TestZonaDariKebijakanTermasukBit63(t *testing.T) {
	f := newFixture(t)
	if err := f.store.SetSitePolicy(context.Background(), f.siteID, []byte(`{"zones":["Lobi","Parkir"],"zones_bitmap":9223372036854775809}`)); err != nil {
		t.Fatal(err)
	}
	rec, cert := provision(t, f, "zona-63")
	if rec.Code != http.StatusOK || cert.Zones != 1<<63|1 {
		t.Fatalf("status %d, zones %d", rec.Code, cert.Zones)
	}
	if !strings.Contains(rec.Body.String(), `"zones":["Lobi","Parkir"]`) {
		t.Fatalf("zones: %s", rec.Body)
	}
}

func TestMasaBerlakuDariKebijakanGedung(t *testing.T) {
	// Minor 7: ADR-0010 — 1–30 hari per gedung, default 7.
	f := newFixture(t)
	if err := f.store.SetSitePolicy(context.Background(), f.siteID, []byte(`{"cert_validity_days":3}`)); err != nil {
		t.Fatal(err)
	}
	_, cert := provision(t, f, "berlaku-3")
	if got := cert.NotAfter.Sub(cert.NotBefore); got != 72*time.Hour {
		t.Fatalf("masa berlaku %v, ingin 72h", got)
	}
}

func TestKanalDimatikanDitolak(t *testing.T) {
	// Minor 7: kill switch kanal (/v1/config) juga ditegakkan saat provisioning.
	f := newFixture(t)
	f.handlerConfig(t, []string{"ble"})
	id := f.enroll(t)
	rec := f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "hce-mati", map[string]string{"channel": "nfcHCE", "public_key": base64.StdEncoding.EncodeToString(phoneKey(t))})
	if rec.Code != http.StatusBadRequest || problemType(t, rec) != "ENR-INVALID-CHANNEL" {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
}

func TestBatasKartuMenjadiENRLIMIT(t *testing.T) {
	f := newFixture(t)
	for i := 0; i < 8; i++ {
		f.enroll(t)
	}
	rec := f.do(t, http.MethodPost, "/v1/enrollments", "", map[string]string{"device_id": f.deviceID, "site_id": f.siteID})
	if rec.Code != http.StatusConflict || problemType(t, rec) != "ENR-LIMIT" {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
}
