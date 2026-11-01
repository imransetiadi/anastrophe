package enroll

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
)

func enrolResult(t *testing.T, body *bytes.Buffer) (id, status string) {
	t.Helper()
	var out struct {
		EnrollmentID string `json:"enrollment_id"`
		Status       string `json:"status"`
	}
	if err := json.Unmarshal(body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	return out.EnrollmentID, out.Status
}

func TestEnrolmentKartuMenjawabStatus(t *testing.T) {
	f := newFixture(t)
	body := f.cardBody()
	rec := f.do(t, http.MethodPost, "/v1/enrollments", "", body)
	if rec.Code != http.StatusCreated {
		t.Fatalf("pertama: %d %s", rec.Code, rec.Body)
	}
	if _, status := enrolResult(t, rec.Body); status != "PROVISIONING" {
		t.Fatalf("status pertama = %q", status)
	}
	// ADR-0032: perangkat lain untuk kartu yang sama menunggu persetujuan.
	other, _ := f.store.CreateDevice(context.Background())
	body["device_id"] = other
	rec = f.do(t, http.MethodPost, "/v1/enrollments", "", body)
	pendingID, status := enrolResult(t, rec.Body)
	if rec.Code != http.StatusCreated || status != "PENDING_APPROVAL" {
		t.Fatalf("perangkat lain: %d %s", rec.Code, rec.Body)
	}
	// ADR-0034: perangkat yang sama dengan kartu yang sama melanjutkan instance-nya (200, id sama).
	rec = f.do(t, http.MethodPost, "/v1/enrollments", "", body)
	if resumedID, resumedStatus := enrolResult(t, rec.Body); rec.Code != http.StatusOK || resumedID != pendingID || resumedStatus != "PENDING_APPROVAL" {
		t.Fatalf("lanjut: %d %s", rec.Code, rec.Body)
	}
	// Setelah aktif, kartu yang sama di perangkat yang sama menjadi duplikat.
	if err := f.store.SetCardInstanceStatus(context.Background(), pendingID, "ACTIVE"); err != nil {
		t.Fatal(err)
	}
	rec = f.do(t, http.MethodPost, "/v1/enrollments", "", body)
	if rec.Code != http.StatusConflict || problemType(t, rec) != "ENR-DUPLICATE" {
		t.Fatalf("duplikat: %d %s", rec.Code, rec.Body)
	}
}

func TestEnrolmentKartuDitolakDenganAlasan(t *testing.T) {
	f := newFixture(t)
	cases := []struct {
		name   string
		card   any
		status int
		code   string
	}{
		{"tanpa kartu", nil, http.StatusBadRequest, "REQ-INVALID"},
		{"tech tak dikenal", map[string]string{"tech": "iso9999", "id": "04a1b2c3"}, http.StatusBadRequest, "REQ-INVALID"},
		{"panjang salah", map[string]string{"tech": "iso14443a", "id": "04a1b2c3d4"}, http.StatusBadRequest, "REQ-INVALID"},
		{"tidak terdaftar", map[string]string{"tech": "iso14443a", "id": "04ffffffffff01"}, http.StatusNotFound, "ENR-NOT-REGISTERED"},
	}
	for _, c := range cases {
		body := map[string]any{"device_id": f.deviceID, "site_id": f.siteID}
		if c.card != nil {
			body["card"] = c.card
		}
		rec := f.do(t, http.MethodPost, "/v1/enrollments", "", body)
		if rec.Code != c.status || problemType(t, rec) != c.code {
			t.Errorf("%s: %d %s", c.name, rec.Code, rec.Body)
		}
	}
}

func TestEnrolmentGedungTanpaRegistri(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	orgID, _ := f.store.CreateOrganization(ctx, "Org Lain", "ID")
	empty, err := f.store.CreateSite(ctx, orgID, "Gedung Baru", "ID", "Asia/Jakarta", []byte{9, 9, 9, 9, 9, 9, 9, 9})
	if err != nil {
		t.Fatal(err)
	}
	body := f.cardBody()
	body["site_id"] = empty
	rec := f.do(t, http.MethodPost, "/v1/enrollments", "", body)
	if rec.Code != http.StatusNotFound || problemType(t, rec) != "ENR-SITE-UNSUPPORTED" {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
}

func TestProvisioningMenungguPersetujuanDitolak(t *testing.T) {
	f := newFixture(t)
	body := f.cardBody()
	if rec := f.do(t, http.MethodPost, "/v1/enrollments", "", body); rec.Code != http.StatusCreated {
		t.Fatalf("pertama: %d", rec.Code)
	}
	other, _ := f.store.CreateDevice(context.Background())
	body["device_id"] = other
	rec := f.do(t, http.MethodPost, "/v1/enrollments", "", body)
	pending, _ := enrolResult(t, rec.Body)
	rec = f.do(t, http.MethodPost, "/v1/enrollments/"+pending+"/credentials", "prov-pending", map[string]string{"channel": "ble", "public_key": encodeKey(phoneKey(t))})
	if rec.Code != http.StatusConflict || problemType(t, rec) != "ENR-PENDING-APPROVAL" {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
}

func TestZonaDariKartuTerdaftar(t *testing.T) {
	// Review Focus 4: zona sertifikat dari kartu terdaftar; bitmap 0 tidak membuka zona apa pun.
	f := newFixture(t)
	ctx := context.Background()
	if err := f.store.SetSitePolicy(ctx, f.siteID, []byte(`{"zones": ["Lobi", "Lift A"], "zones_bitmap": 3}`)); err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct {
		id     string
		bitmap uint64
		zones  string
	}{{"04aaaaaaaaaa01", 1, "Lobi"}, {"04aaaaaaaaaa02", 0, ""}} {
		f.registerCard(t, c.id, c.bitmap)
		body := map[string]any{"device_id": f.deviceID, "site_id": f.siteID, "card": map[string]string{"tech": "iso14443a", "id": c.id}}
		rec := f.do(t, http.MethodPost, "/v1/enrollments", "", body)
		id, _ := enrolResult(t, rec.Body)
		rec = f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "prov-"+c.id, map[string]string{"channel": "ble", "public_key": encodeKey(phoneKey(t))})
		var out struct {
			Zones []string `json:"zones"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &out); rec.Code != http.StatusOK || err != nil || strings.Join(out.Zones, ",") != c.zones {
			t.Errorf("%s: %d zona=%v %s", c.id, rec.Code, out.Zones, rec.Body)
		}
	}
}

func TestIdentitasKartuTidakBocor(t *testing.T) {
	// CLAUDE.md aturan 6: identitas kartu tidak muncul di respons, log, atau baris idempotency.
	f := newFixture(t)
	var logs bytes.Buffer
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewTextHandler(&logs, &slog.HandlerOptions{Level: slog.LevelDebug})))
	t.Cleanup(func() { slog.SetDefault(previous) })
	const secret = "04ffffffffff02"
	body := map[string]any{"device_id": f.deviceID, "site_id": f.siteID, "card": map[string]string{"tech": "iso14443a", "id": secret}}
	unknown := f.do(t, http.MethodPost, "/v1/enrollments", "enr-rahasia", body)
	known := f.do(t, http.MethodPost, "/v1/enrollments", "enr-terdaftar", f.cardBody())
	for _, out := range []string{unknown.Body.String(), known.Body.String(), logs.String()} {
		if strings.Contains(strings.ToLower(out), secret) || strings.Contains(strings.ToLower(out), labCardHex(0)) {
			t.Fatalf("identitas kartu bocor: %s", out)
		}
	}
	// Hash idempotency memakai HMAC kartu, bukan identitas mentah (SHA-256 dari UID pendek bisa ditebak).
	conn, err := pgx.Connect(context.Background(), f.dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close(context.Background())
	var stored [][]byte
	rows, err := conn.Query(context.Background(), `SELECT request_hash FROM idempotency_keys`)
	if err != nil {
		t.Fatal(err)
	}
	for rows.Next() {
		var h []byte
		_ = rows.Scan(&h)
		stored = append(stored, h)
	}
	if len(stored) == 0 {
		t.Fatal("tidak ada baris idempotency")
	}
	for _, raw := range []string{secret, labCardHex(0)} {
		guess := sha256.Sum256([]byte("/v1/enrollments\n" + f.deviceID + "\n" + f.siteID + "\n" + raw))
		for _, h := range stored {
			if bytes.Equal(h, guess[:]) {
				t.Fatalf("hash idempotency diturunkan dari identitas mentah %s", raw)
			}
		}
	}
}
