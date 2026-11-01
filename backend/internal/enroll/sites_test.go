package enroll

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

// get mengirim GET tanpa body (lookup kode gedung tidak membutuhkan header apa pun).
func (f fixture) get(t *testing.T, target string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	f.handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, target, nil))
	return rec
}

func (f fixture) joinCode(t *testing.T) string {
	t.Helper()
	code, _, err := f.store.RotateSiteJoinCode(context.Background(), f.siteID, "staf-01", time.Unix(1_794_000_000, 0))
	if err != nil {
		t.Fatal(err)
	}
	return code
}

func TestLookupKodeGedung(t *testing.T) {
	// ADR-0044: kode yang diketik penghuni (huruf kecil, dengan "-") menghasilkan gedung untuk dikonfirmasi.
	f := newFixture(t)
	code := f.joinCode(t)
	typed := strings.ToLower(code[:4] + "-" + code[4:])
	rec := f.get(t, "/v1/sites/lookup?code="+url.QueryEscape(typed))
	if rec.Code != http.StatusOK {
		t.Fatalf("lookup: %d %s", rec.Code, rec.Body)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Fatalf("Cache-Control = %q", got)
	}
	var out map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	// ADR-0049: lookup juga membawa kanal efektif gedung.
	if len(out) != 3 || out["site_id"] != f.siteID || out["name"] != "Menara Uji" || out["channels"] == nil {
		t.Fatalf("body = %v", out)
	}
}

func TestLookupKodeGedungIdentik(t *testing.T) {
	// Review Focus 3: kode tak dikenal, rusak, kosong, atau hilang tidak bisa dibedakan.
	f := newFixture(t)
	f.joinCode(t)
	var first []byte
	for _, target := range []string{
		"/v1/sites/lookup?code=ZZZZZZZZ",
		"/v1/sites/lookup?code=abc",
		"/v1/sites/lookup?code=",
		"/v1/sites/lookup",
		"/v1/sites/lookup?code=7K2Q9XU4",
		"/v1/sites/lookup?code=" + strings.Repeat("A", 100),
	} {
		rec := f.get(t, target)
		if rec.Code != http.StatusNotFound || problemType(t, rec) != "SITE-NOT-FOUND" {
			t.Fatalf("%s: %d %s", target, rec.Code, rec.Body)
		}
		if rec.Header().Get("Cache-Control") != "no-store" {
			t.Fatalf("%s: tanpa no-store", target)
		}
		if first == nil {
			first = rec.Body.Bytes()
		} else if string(rec.Body.Bytes()) != string(first) {
			t.Fatalf("%s: body berbeda: %s vs %s", target, rec.Body, first)
		}
	}
}
