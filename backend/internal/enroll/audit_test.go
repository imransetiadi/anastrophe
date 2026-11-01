package enroll

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/store"
	"github.com/jackc/pgx/v5"
)

func encodeKey(b []byte) string { return base64.StdEncoding.EncodeToString(b) }

// exec menjalankan SQL langsung ke database test (injeksi kegagalan, bukan jalur aplikasi).
func (f fixture) exec(t *testing.T, sql string) {
	t.Helper()
	conn, err := pgx.Connect(context.Background(), f.dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close(context.Background())
	if _, err := conn.Exec(context.Background(), sql); err != nil {
		t.Fatal(err)
	}
}

func (f fixture) audit(t *testing.T) []store.AuditRecord {
	t.Helper()
	events, err := f.store.AuditEvents(context.Background(), store.AuditChain(f.siteID))
	if err != nil {
		t.Fatal(err)
	}
	return events
}

func actions(events []store.AuditRecord) []string {
	out := make([]string, len(events))
	for i, e := range events {
		out[i] = e.Action
	}
	return out
}

func TestEnrolmentMencatatAudit(t *testing.T) {
	f := newFixture(t)
	id := f.enroll(t)
	events := f.audit(t)
	if len(events) != 1 || events[0].Action != "enrollment.started" || events[0].Actor != "device:"+f.deviceID || events[0].Subject != "card_instance:"+id {
		t.Fatalf("audit: %+v", events)
	}
}

func TestProvisioningDanRenewMencatatAudit(t *testing.T) {
	f := provisionedForRenewal(t)
	f.advance(4 * 24 * time.Hour)
	nonce := f.challenge(t, f.credID)
	if rec := f.renew(t, f.credID, nonce, renewalSignature(t, f.key, f.credID, nonce), "renew-audit"); rec.Code != http.StatusOK {
		t.Fatalf("renew: %d %s", rec.Code, rec.Body)
	}
	events := f.audit(t)
	if got := actions(events); len(got) != 3 || got[0] != "enrollment.started" || got[1] != "credential.provisioned" || got[2] != "credential.renewed" {
		t.Fatalf("aksi audit: %v", got)
	}
	subject := "credential:" + hex.EncodeToString(f.credID)
	for _, e := range events[1:] {
		if e.Subject != subject || e.Actor != "device:"+f.deviceID || e.Data["channel"] != "ble" {
			t.Fatalf("event kredensial: %+v", e)
		}
	}
	if events[2].Data["not_after"] != f.h.Now().UTC().Add(7*24*time.Hour).Format(time.RFC3339) {
		t.Fatalf("not_after perpanjangan: %v", events[2].Data["not_after"])
	}
	if n, err := f.store.VerifyAuditChain(context.Background(), store.AuditChain(f.siteID)); err != nil || n != 3 {
		t.Fatalf("verify = %d, %v", n, err)
	}
}

func TestAuditTanpaDataPribadi(t *testing.T) {
	// Review Focus 4: hanya field yang diizinkan (CLAUDE.md aturan 6, FR-54), termasuk perpanjangan.
	f := provisionedForRenewal(t)
	nonce := f.challenge(t, f.credID)
	if rec := f.renew(t, f.credID, nonce, renewalSignature(t, f.key, f.credID, nonce), "renew-pii"); rec.Code != http.StatusOK {
		t.Fatalf("renew: %d", rec.Code)
	}
	if got := actions(f.audit(t)); len(got) != 3 {
		t.Fatalf("aksi: %v", got)
	}
	for _, e := range f.audit(t) {
		for k := range e.Data {
			if k != "channel" && k != "not_after" {
				t.Fatalf("field audit tak diizinkan %q di %s", k, e.Action)
			}
		}
	}
}

func TestRetryIdempotenTidakMenggandakanAudit(t *testing.T) {
	// Review Focus 5.
	f := newFixture(t)
	id := f.enroll(t)
	body := map[string]string{"channel": "ble", "public_key": encodeKey(phoneKey(t))}
	for i := 0; i < 2; i++ {
		if rec := f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "prov-retry", body); rec.Code != http.StatusOK {
			t.Fatalf("provisioning %d: %d", i, rec.Code)
		}
	}
	count := 0
	for _, e := range f.audit(t) {
		if e.Action == "credential.provisioned" {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("credential.provisioned = %d, ingin 1", count)
	}
}

func TestAuditGagalMembatalkanProvisioning(t *testing.T) {
	// Review Focus 3: audit gagal → kredensial tidak tersimpan (satu transaksi).
	f := newFixture(t)
	id := f.enroll(t)
	f.exec(t, `ALTER TABLE audit_events ADD CONSTRAINT tolak_uji CHECK (action <> 'credential.provisioned')`)
	body := map[string]string{"channel": "ble", "public_key": encodeKey(phoneKey(t))}
	rec := f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "prov-fail", body)
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status %d, ingin 500", rec.Code)
	}
	if n, _ := f.store.CredentialCount(context.Background(), id); n != 0 {
		t.Fatalf("kredensial tersimpan tanpa audit: %d", n)
	}
	// Setelah gangguan hilang, retry dengan key yang sama berhasil tepat sekali.
	f.exec(t, `ALTER TABLE audit_events DROP CONSTRAINT tolak_uji`)
	if rec := f.do(t, http.MethodPost, "/v1/enrollments/"+id+"/credentials", "prov-fail", body); rec.Code != http.StatusOK {
		t.Fatalf("retry: %d %s", rec.Code, rec.Body)
	}
	if n, _ := f.store.CredentialCount(context.Background(), id); n != 1 {
		t.Fatalf("kredensial setelah retry: %d", n)
	}
}

func TestEnrolmentHurufBesarSatuRantai(t *testing.T) {
	// Review audit C1: UUID huruf besar (mis. UUID.uuidString Swift) tidak membelah rantai gedung.
	f := newFixture(t)
	rec := f.do(t, http.MethodPost, "/v1/enrollments", "enr-upper", map[string]string{"device_id": strings.ToUpper(f.deviceID), "site_id": strings.ToUpper(f.siteID)})
	if rec.Code != http.StatusCreated {
		t.Fatalf("enrol: %d %s", rec.Code, rec.Body)
	}
	var out struct {
		EnrollmentID string `json:"enrollment_id"`
	}
	json.Unmarshal(rec.Body.Bytes(), &out)
	if rec := f.do(t, http.MethodPost, "/v1/enrollments/"+out.EnrollmentID+"/credentials", "prov-upper", map[string]string{"channel": "ble", "public_key": encodeKey(phoneKey(t))}); rec.Code != http.StatusOK {
		t.Fatalf("provisioning: %d", rec.Code)
	}
	events := f.audit(t)
	if got := actions(events); len(got) != 2 || events[0].Actor != "device:"+strings.ToLower(f.deviceID) {
		t.Fatalf("audit: %+v", events)
	}
	upper, _ := f.store.AuditEvents(context.Background(), "site:"+strings.ToUpper(f.siteID))
	if len(upper) != 0 {
		t.Fatalf("rantai huruf besar terbentuk: %d baris", len(upper))
	}
}

func TestRetryEnrolmentBerkunciTidakMenggandakanAudit(t *testing.T) {
	f := newFixture(t)
	body := map[string]string{"device_id": f.deviceID, "site_id": f.siteID}
	for i := 0; i < 2; i++ {
		if rec := f.do(t, http.MethodPost, "/v1/enrollments", "enr-retry", body); rec.Code != http.StatusCreated {
			t.Fatalf("enrol %d: %d", i, rec.Code)
		}
	}
	if got := actions(f.audit(t)); len(got) != 1 {
		t.Fatalf("aksi: %v", got)
	}
}
