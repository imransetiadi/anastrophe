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
	"strings"
	"testing"

	"github.com/imransetiadi/anastrophe/backend/internal/store"
	"github.com/jackc/pgx/v5"
)

// newProvisioningSecret membuat rahasia enrolment seperti app (ADR-0040).
func newProvisioningSecret(t *testing.T) (secret []byte, bearer, hashB64 string) {
	t.Helper()
	secret = make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(secret)
	return secret, "Bearer " + base64.RawURLEncoding.EncodeToString(secret), base64.StdEncoding.EncodeToString(sum[:])
}

// enrollWith mendaftarkan kartu lab berikutnya untuk perangkat dengan hash rahasia tertentu (tanpa
// perilaku otomatis do()).
func (f fixture) enrollWith(t *testing.T, deviceID string, card int, hashB64 string) (string, string) {
	t.Helper()
	body := map[string]any{"device_id": deviceID, "site_id": f.siteID, "card": map[string]string{"tech": "iso14443a", "id": labCardHex(card)}}
	if hashB64 != "" {
		body["provisioning_key_hash"] = hashB64
	}
	rec := f.request(t, http.MethodPost, "/v1/enrollments", "", body, nil)
	if rec.Code != http.StatusCreated && rec.Code != http.StatusOK {
		t.Fatalf("enrolment: %d %s", rec.Code, rec.Body)
	}
	return enrolResult(t, rec.Body)
}

func (f fixture) provisionWith(t *testing.T, id, authorization, channel string) *httpResult {
	t.Helper()
	key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	headers := map[string]string{}
	if authorization != "" {
		headers["Authorization"] = authorization
	}
	rec := f.request(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "prov-"+hex.EncodeToString(mustPub(t, key))[:16], map[string]string{
		"channel": channel, "public_key": base64.StdEncoding.EncodeToString(mustPub(t, key)),
	}, headers)
	return &httpResult{code: rec.Code, body: rec.Body.Bytes(), typ: problemTypeOrEmpty(rec.Body.Bytes())}
}

type httpResult struct {
	code int
	body []byte
	typ  string
}

func problemTypeOrEmpty(body []byte) string {
	var out struct {
		Type string `json:"type"`
	}
	_ = json.Unmarshal(body, &out)
	return out.Type
}

func TestProvisioningTanpaRahasiaIdentik(t *testing.T) {
	// Review Focus 1 (ADR-0040): tanpa rahasia enrolment, instance apa pun (PROVISIONING, PENDING_APPROVAL,
	// tanpa hash) dijawab sama dengan id tak dikenal; rahasia diperiksa sebelum status diungkap.
	f := newFixture(t)
	_, bearer, hashB64 := newProvisioningSecret(t)
	id, _ := f.enrollWith(t, f.deviceID, 0, hashB64)
	_, wrongBearer, _ := newProvisioningSecret(t)
	other, _ := f.store.CreateDevice(context.Background())
	_, pendingBearer, pendingHash := newProvisioningSecret(t)
	pending, status := f.enrollWith(t, other, 0, pendingHash)
	if status != "PENDING_APPROVAL" {
		t.Fatalf("perangkat kedua: %s", status)
	}
	noHash, _ := f.enrollWith(t, f.deviceID, 1, "")
	cases := map[string]*httpResult{
		"tanpa header":        f.provisionWith(t, id, "", "ble"),
		"base64 rusak":        f.provisionWith(t, id, "Bearer !!!", "ble"),
		"rahasia salah":       f.provisionWith(t, id, wrongBearer, "ble"),
		"bukan bearer":        f.provisionWith(t, id, "Basic "+strings.TrimPrefix(bearer, "Bearer "), "ble"),
		"id tak dikenal":      f.provisionWith(t, "00000000-0000-4000-8000-000000000000", bearer, "ble"),
		"menunggu tanpa":      f.provisionWith(t, pending, wrongBearer, "ble"),
		"instance tanpa hash": f.provisionWith(t, noHash, bearer, "ble"),
	}
	var reference []byte
	for name, r := range cases {
		if r.code != http.StatusNotFound || r.typ != "ENR-NOT-FOUND" {
			t.Errorf("%s: %d %s", name, r.code, r.body)
		}
		if reference == nil {
			reference = r.body
		} else if !bytes.Equal(reference, r.body) {
			t.Errorf("%s: body berbeda", name)
		}
	}
	if r := f.provisionWith(t, pending, pendingBearer, "ble"); r.code != http.StatusConflict || r.typ != "ENR-PENDING-APPROVAL" {
		t.Fatalf("menunggu dengan rahasia benar: %d %s", r.code, r.body)
	}
	if r := f.provisionWith(t, id, bearer, "ble"); r.code != http.StatusOK {
		t.Fatalf("rahasia benar: %d %s", r.code, r.body)
	}
}

func TestTambahKanalKartuAktifDitolak(t *testing.T) {
	// Review Focus 2: kanal baru untuk instance ACTIVE ditolak, juga bila hash masih ada.
	f := newFixture(t)
	_, bearer, hashB64 := newProvisioningSecret(t)
	id, _ := f.enrollWith(t, f.deviceID, 0, hashB64)
	if r := f.provisionWith(t, id, bearer, "ble"); r.code != http.StatusOK {
		t.Fatalf("kredensial pertama: %d %s", r.code, r.body)
	}
	if r := f.provisionWith(t, id, bearer, "nfcHCE"); r.code != http.StatusNotFound || r.typ != "ENR-NOT-FOUND" {
		t.Fatalf("kanal kedua setelah hash terhapus: %d %s", r.code, r.body)
	}
	secret, again, _ := newProvisioningSecret(t)
	sum := sha256.Sum256(secret)
	_, _, err := f.store.Idempotent(context.Background(), "pasang-hash", []byte("h"), func(ctx context.Context, tx *store.Tx) (int, []byte, error) {
		return 200, []byte("{}"), tx.SetProvisioningKeyHash(ctx, id, sum[:])
	})
	if err != nil {
		t.Fatal(err)
	}
	if r := f.provisionWith(t, id, again, "nfcHCE"); r.code != http.StatusConflict || r.typ != "ENR-NOT-PROVISIONABLE" {
		t.Fatalf("kanal kedua dengan hash: %d %s", r.code, r.body)
	}
	if n, err := f.store.CredentialCount(context.Background(), id); err != nil || n != 1 {
		t.Fatalf("kredensial = %d (%v), ingin 1", n, err)
	}
}

func TestRahasiaDigantiSaatMelanjutkan(t *testing.T) {
	// Review Focus 3: melanjutkan (ADR-0034) dan promosi undangan (ADR-0035) memasang rahasia terbaru.
	f := newFixture(t)
	_, oldBearer, oldHash := newProvisioningSecret(t)
	id, _ := f.enrollWith(t, f.deviceID, 0, oldHash)
	_, newBearer, newHash := newProvisioningSecret(t)
	if again, status := f.enrollWith(t, f.deviceID, 0, newHash); again != id || status != "PROVISIONING" {
		t.Fatalf("melanjutkan: %s %s", again, status)
	}
	if r := f.provisionWith(t, id, oldBearer, "ble"); r.code != http.StatusNotFound {
		t.Fatalf("rahasia lama masih berlaku: %d", r.code)
	}
	if r := f.provisionWith(t, id, newBearer, "ble"); r.code != http.StatusOK {
		t.Fatalf("rahasia baru: %d %s", r.code, r.body)
	}
	// Promosi: perangkat kedua menunggu persetujuan untuk kartu yang sama, lalu menebus undangan berkartu.
	other, _ := f.store.CreateDevice(context.Background())
	_, _, pendingHash := newProvisioningSecret(t)
	pending, status := f.enrollWith(t, other, 0, pendingHash)
	if status != "PENDING_APPROVAL" {
		t.Fatalf("perangkat kedua: %s", status)
	}
	token := f.invitation(t, store.Invitation{CardHMAC: f.cardHMAC(t, labCardHex(0))}, f.h.Now())
	_, promotedBearer, promotedHash := newProvisioningSecret(t)
	rec := f.request(t, http.MethodPost, "/v1/enrollments", "", map[string]string{"device_id": other, "invitation": token, "provisioning_key_hash": promotedHash}, nil)
	if got, status := enrolResult(t, rec.Body); got != pending || status != "PROVISIONING" {
		t.Fatalf("promosi: %d %s", rec.Code, rec.Body)
	}
	if r := f.provisionWith(t, pending, promotedBearer, "ble"); r.code != http.StatusOK {
		t.Fatalf("provisioning setelah promosi: %d %s", r.code, r.body)
	}
}

func TestRahasiaEnrolmentTidakBocor(t *testing.T) {
	// Review Focus 4: server hanya menyimpan SHA-256; rahasia tidak ada di log maupun tabel.
	f := newFixture(t)
	var logs bytes.Buffer
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewTextHandler(&logs, &slog.HandlerOptions{Level: slog.LevelDebug})))
	t.Cleanup(func() { slog.SetDefault(previous) })
	secret, bearer, hashB64 := newProvisioningSecret(t)
	id, _ := f.enrollWith(t, f.deviceID, 0, hashB64)
	stored := provisioningHashOf(t, f, id)
	if sum := sha256.Sum256(secret); !bytes.Equal(stored, sum[:]) {
		t.Fatalf("tersimpan %x, ingin SHA-256 rahasia", stored)
	}
	f.provisionWith(t, id, bearer+"x", "ble")
	f.provisionWith(t, id, bearer, "ble")
	for _, text := range []string{logs.String(), allTablesText(t, f.dsn)} {
		for _, form := range []string{base64.RawURLEncoding.EncodeToString(secret), base64.StdEncoding.EncodeToString(secret), hex.EncodeToString(secret)} {
			// allTablesText menurunkan huruf seluruh dump, jadi bentuk huruf kecil juga dicari (review akhir I2).
			if strings.Contains(text, form) || strings.Contains(text, strings.ToLower(form)) {
				t.Fatalf("rahasia enrolment bocor dalam bentuk %q", form)
			}
		}
	}
}

func TestHashRahasiaDihapusSetelahKredensialPertama(t *testing.T) {
	// Review Focus 5: tidak ada kapabilitas provisioning yang tertinggal setelah kartu aktif.
	f := newFixture(t)
	_, bearer, hashB64 := newProvisioningSecret(t)
	id, _ := f.enrollWith(t, f.deviceID, 0, hashB64)
	if r := f.provisionWith(t, id, bearer, "ble"); r.code != http.StatusOK {
		t.Fatalf("provisioning: %d %s", r.code, r.body)
	}
	if stored := provisioningHashOf(t, f, id); stored != nil {
		t.Fatalf("hash masih ada: %x", stored)
	}
}

func TestHashRahasiaBukan32ByteDitolak(t *testing.T) {
	f := newFixture(t)
	body := map[string]any{"device_id": f.deviceID, "site_id": f.siteID, "card": map[string]string{"tech": "iso14443a", "id": labCardHex(0)},
		"provisioning_key_hash": base64.StdEncoding.EncodeToString(make([]byte, 31))}
	rec := f.request(t, http.MethodPost, "/v1/enrollments", "", body, nil)
	if rec.Code != http.StatusBadRequest || problemType(t, rec) != "REQ-INVALID" {
		t.Fatalf("hash 31 byte: %d %s", rec.Code, rec.Body)
	}
}

func provisioningHashOf(t *testing.T, f fixture, id string) []byte {
	t.Helper()
	conn, err := pgx.Connect(context.Background(), f.dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close(context.Background())
	var stored []byte
	if err := conn.QueryRow(context.Background(), `SELECT provisioning_key_hash FROM card_instances WHERE id = $1`, id).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	return stored
}
