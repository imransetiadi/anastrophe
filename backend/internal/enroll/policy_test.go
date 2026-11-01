package enroll

import (
	"context"
	"encoding/json"
	"net/http"
	"slices"
	"testing"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/store"
)

func (f fixture) setChannels(t *testing.T, channels ...string) {
	t.Helper()
	list := channels
	if _, err := f.store.UpdateSitePolicy(context.Background(), f.siteID, "staf-01", store.PolicyUpdate{Channels: &list}, time.Unix(1_794_000_000, 0)); err != nil {
		t.Fatal(err)
	}
}

func channelsOf(t *testing.T, body []byte) []string {
	t.Helper()
	var out struct {
		Channels *[]string `json:"channels"`
	}
	if err := json.Unmarshal(body, &out); err != nil || out.Channels == nil {
		t.Fatalf("tanpa channels: %s (%v)", body, err)
	}
	return *out.Channels
}

func TestKanalEfektifTanpaKebijakan(t *testing.T) {
	// Review Focus 4 (ADR-0049): tanpa policy.channels, kanal gedung = kanal global.
	f := newFixture(t)
	rec := f.get(t, "/v1/sites/lookup?code="+f.joinCode(t))
	if got := channelsOf(t, rec.Body.Bytes()); !slices.Equal(got, []string{"ble", "nfcHCE"}) {
		t.Fatalf("channels = %v", got)
	}
}

func TestLookupMembawaKanalGedung(t *testing.T) {
	f := newFixture(t)
	code := f.joinCode(t)
	f.setChannels(t, "nfcHCE")
	if got := channelsOf(t, f.get(t, "/v1/sites/lookup?code="+code).Body.Bytes()); !slices.Equal(got, []string{"nfcHCE"}) {
		t.Fatalf("channels = %v", got)
	}
	// Irisan dengan kanal global: kebijakan nfcHCE + global hanya ble → kosong (array, bukan null).
	f.handlerConfig(t, []string{"ble"})
	if got := channelsOf(t, f.get(t, "/v1/sites/lookup?code="+code).Body.Bytes()); len(got) != 0 {
		t.Fatalf("channels = %v, ingin kosong", got)
	}
}

func TestEnrolmentMembawaKanalGedung(t *testing.T) {
	f := newFixture(t)
	f.setChannels(t, "ble")
	rec := f.do(t, http.MethodPost, "/v1/enrollments", "", f.cardBody())
	if rec.Code != http.StatusCreated || !slices.Equal(channelsOf(t, rec.Body.Bytes()), []string{"ble"}) {
		t.Fatalf("enrolment kartu: %d %s", rec.Code, rec.Body)
	}
	token := f.invitation(t, store.Invitation{ZonesBitmap: 1}, f.h.Now())
	rec = f.do(t, http.MethodPost, "/v1/enrollments", "", map[string]string{"device_id": newDeviceID(t), "invitation": token})
	if rec.Code != http.StatusCreated || !slices.Equal(channelsOf(t, rec.Body.Bytes()), []string{"ble"}) {
		t.Fatalf("enrolment undangan: %d %s", rec.Code, rec.Body)
	}
}

func TestKanalGedungDitolakSesudahRahasia(t *testing.T) {
	// Review Focus 2: kebijakan kanal tidak bocor sebelum rahasia enrolment diperiksa (ADR-0040).
	f := newFixture(t)
	f.setChannels(t, "nfcHCE")
	id := f.enroll(t)
	path := "/v1/enrollments/" + id + "/credentials"
	body := map[string]string{"channel": "ble", "public_key": encodeKey(phoneKey(t))}
	if rec := f.request(t, http.MethodPost, path, "tanpa-rahasia", body, nil); rec.Code != http.StatusNotFound || problemType(t, rec) != "ENR-NOT-FOUND" {
		t.Fatalf("tanpa rahasia: %d %s", rec.Code, rec.Body)
	}
	if rec := f.do(t, http.MethodPost, path, "kanal-terlarang", body); rec.Code != http.StatusBadRequest || problemType(t, rec) != "ENR-INVALID-CHANNEL" {
		t.Fatalf("kanal terlarang: %d %s", rec.Code, rec.Body)
	}
	allowed := map[string]string{"channel": "nfcHCE", "public_key": encodeKey(phoneKey(t))}
	if rec := f.do(t, http.MethodPost, path, "kanal-diizinkan", allowed); rec.Code != http.StatusOK {
		t.Fatalf("kanal diizinkan: %d %s", rec.Code, rec.Body)
	}
}
