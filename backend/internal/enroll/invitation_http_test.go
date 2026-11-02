package enroll

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/certs"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
	"github.com/jackc/pgx/v5"
)

func (f fixture) invitation(t *testing.T, inv store.Invitation, at time.Time) string {
	t.Helper()
	inv.SiteID = f.siteID
	if inv.TTL == 0 {
		inv.TTL = 7 * 24 * time.Hour
	}
	created, err := f.store.CreateInvitation(context.Background(), inv, "staf-01", at)
	if err != nil {
		t.Fatal(err)
	}
	return created.Token
}

func TestEnrolmentDenganUndangan(t *testing.T) {
	// ADR-0033: undangan menggantikan kartu fisik; zona sertifikat dari undangan.
	f := newFixture(t)
	if err := f.store.SetSitePolicy(context.Background(), f.siteID, []byte(`{"zones": ["Lobi", "Lift A"], "zones_bitmap": 3}`)); err != nil {
		t.Fatal(err)
	}
	token := f.invitation(t, store.Invitation{ZonesBitmap: 2}, f.h.Now())
	rec := f.do(t, http.MethodPost, "/v1/enrollments", "", map[string]string{"device_id": f.deviceID, "invitation": token})
	id, status := enrolResult(t, rec.Body)
	if rec.Code != http.StatusCreated || status != "PROVISIONING" {
		t.Fatalf("enrolment undangan: %d %s", rec.Code, rec.Body)
	}
	rec = f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "prov-undangan", map[string]string{"channel": "ble", "public_key": encodeKey(phoneKey(t))})
	var body struct {
		Certificate []byte   `json:"certificate"`
		Zones       []string `json:"zones"`
	}
	if rec.Code != http.StatusOK || json.Unmarshal(rec.Body.Bytes(), &body) != nil {
		t.Fatalf("provisioning: %d %s", rec.Code, rec.Body)
	}
	cert, err := certs.Verify(body.Certificate, f.signer.Public())
	if err != nil || cert.Zones != 2 || strings.Join(body.Zones, ",") != "Lift A" {
		t.Fatalf("zona = %d %v (%v), ingin 2 [Lift A]", cert.Zones, body.Zones, err)
	}
}

func TestKartuDanUndanganSalingEksklusif(t *testing.T) {
	f := newFixture(t)
	token := f.invitation(t, store.Invitation{}, f.h.Now())
	card := map[string]string{"tech": "iso14443a", "id": labCardHex(0)}
	for name, body := range map[string]map[string]any{
		"keduanya":       {"device_id": f.deviceID, "site_id": f.siteID, "card": card, "invitation": token},
		"tanpa-keduanya": {"device_id": f.deviceID, "site_id": f.siteID},
		"token-rusak":    {"device_id": f.deviceID, "invitation": token[:40]},
	} {
		if rec := f.do(t, http.MethodPost, "/v1/enrollments", "", body); rec.Code != http.StatusBadRequest || problemType(t, rec) != "REQ-INVALID" {
			t.Errorf("%s: %d %s", name, rec.Code, rec.Body)
		}
	}
}

func TestUndanganTidakBerlakuIdentik(t *testing.T) {
	// Review Focus 2 / TC-ENR-08: tak dikenal, kedaluwarsa, dan terpakai tidak bisa dibedakan.
	f := newFixture(t)
	random := make([]byte, 32)
	_, _ = rand.Read(random)
	unknown := base64.RawURLEncoding.EncodeToString(random)
	expired := f.invitation(t, store.Invitation{}, f.h.Now().Add(-8*24*time.Hour))
	used := f.invitation(t, store.Invitation{}, f.h.Now())
	other, _ := f.store.CreateDevice(context.Background())
	if rec := f.do(t, http.MethodPost, "/v1/enrollments", "", map[string]string{"device_id": other, "invitation": used}); rec.Code != http.StatusCreated {
		t.Fatalf("pemakaian pertama: %d %s", rec.Code, rec.Body)
	}
	var first *bytes.Buffer
	for name, token := range map[string]string{"tak-dikenal": unknown, "kedaluwarsa": expired, "terpakai": used} {
		rec := f.do(t, http.MethodPost, "/v1/enrollments", "", map[string]string{"device_id": f.deviceID, "invitation": token})
		if rec.Code != http.StatusNotFound || problemType(t, rec) != "ENR-INVITATION-INVALID" {
			t.Fatalf("%s: %d %s", name, rec.Code, rec.Body)
		}
		if first == nil {
			first = rec.Body
		} else if rec.Body.String() != first.String() {
			t.Fatalf("%s: body berbeda %q vs %q", name, rec.Body, first)
		}
	}
}

func TestTokenUndanganTidakBocor(t *testing.T) {
	// Review Focus 3: token mentah tidak muncul di respons, log, database, atau hash idempotency.
	f := newFixture(t)
	var logs bytes.Buffer
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewTextHandler(&logs, &slog.HandlerOptions{Level: slog.LevelDebug})))
	t.Cleanup(func() { slog.SetDefault(previous) })
	token := f.invitation(t, store.Invitation{}, f.h.Now())
	rec := f.do(t, http.MethodPost, "/v1/enrollments", "undangan-1", map[string]string{"device_id": f.deviceID, "invitation": token})
	if rec.Code != http.StatusCreated {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
	raw, _ := base64.RawURLEncoding.DecodeString(token)
	for _, text := range []string{rec.Body.String(), logs.String(), allTablesText(t, f.dsn)} {
		if strings.Contains(text, strings.ToLower(token)) || strings.Contains(text, token) || strings.Contains(text, hexLower(raw)) {
			t.Fatal("token undangan mentah bocor")
		}
	}
	conn, err := pgx.Connect(context.Background(), f.dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close(context.Background())
	var stored []byte
	if err := conn.QueryRow(context.Background(), `SELECT request_hash FROM idempotency_keys WHERE key = 'undangan-1'`).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if guess := sha256.Sum256([]byte("/v1/enrollments\n" + f.deviceID + "\n" + token)); bytes.Equal(stored, guess[:]) {
		t.Fatal("hash idempotency diturunkan dari token mentah")
	}
}

func TestUndanganBatasKartuMenjadiENRLIMIT(t *testing.T) {
	// Review akhir I4 (CLAUDE.md aturan 8): batas 8 kartu juga di jalur undangan.
	f := newFixture(t)
	for i := 0; i < 8; i++ {
		f.enroll(t)
	}
	token := f.invitation(t, store.Invitation{ZonesBitmap: 1}, f.h.Now())
	rec := f.do(t, http.MethodPost, "/v1/enrollments", "", map[string]string{"device_id": f.deviceID, "invitation": token})
	if rec.Code != http.StatusConflict || problemType(t, rec) != "ENR-LIMIT" {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
}

func hexLower(b []byte) string {
	const digits = "0123456789abcdef"
	out := make([]byte, 0, len(b)*2)
	for _, c := range b {
		out = append(out, digits[c>>4], digits[c&0x0f])
	}
	return string(out)
}

func TestUndanganIdempotencyMemuatToken(t *testing.T) {
	// Review akhir undangan M9: key sama dengan token lain tidak boleh memakai respons enrolment lama.
	f := newFixture(t)
	first := f.invitation(t, store.Invitation{ZonesBitmap: 1}, f.h.Now())
	second := f.invitation(t, store.Invitation{ZonesBitmap: 1}, f.h.Now())
	if rec := f.request(t, http.MethodPost, "/v1/enrollments", "undangan-sama", map[string]string{"device_id": f.deviceID, "invitation": first}, nil); rec.Code != http.StatusCreated {
		t.Fatalf("pertama: %d %s", rec.Code, rec.Body)
	}
	if rec := f.request(t, http.MethodPost, "/v1/enrollments", "undangan-sama", map[string]string{"device_id": f.deviceID, "invitation": second}, nil); rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("token lain: %d %s", rec.Code, rec.Body)
	}
}
