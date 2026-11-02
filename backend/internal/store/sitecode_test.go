package store

import (
	"context"
	"errors"
	"regexp"
	"strings"
	"testing"
	"time"
)

// Vektor normalisasi bersama dengan app (Packages/Tests/ANCoreTests/SiteJoinCodeTests.swift).
var joinCodeVectors = []struct {
	in   string
	want string
	ok   bool
}{
	{"7k2q-9xa4", "7K2Q9XA4", true},
	{" 7K2Q 9XA4 ", "7K2Q9XA4", true},
	{"OIL0-1234", "01101234", true},
	{"7K2Q9XA", "", false},
	{"7K2Q9XA4Z", "", false},
	{"7K2Q9XU4", "", false},
	{"", "", false},
}

func TestNormalisasiKodeGedung(t *testing.T) {
	// ADR-0044: huruf besar, "-" dan spasi dibuang, O→0, I/L→1, tepat 8 simbol Crockford.
	for _, v := range joinCodeVectors {
		got, ok := NormalizeJoinCode(v.in)
		if got != v.want || ok != v.ok {
			t.Errorf("NormalizeJoinCode(%q) = %q, %v; ingin %q, %v", v.in, got, ok, v.want, v.ok)
		}
	}
	if got := FormatJoinCode("7K2Q9XA4"); got != "7K2Q-9XA4" {
		t.Errorf("FormatJoinCode = %q", got)
	}
}

var joinCodePattern = regexp.MustCompile(`^[0-9A-HJKMNP-TV-Z]{8}$`)

func TestRotasiKodeGedung(t *testing.T) {
	s := freshStore(t)
	site, _ := seed(t, s)
	ctx := context.Background()
	at := time.Unix(1_794_000_000, 0)
	first, replaced, err := s.RotateSiteJoinCode(ctx, site, "staf-01", at)
	if err != nil || replaced || !joinCodePattern.MatchString(first) {
		t.Fatalf("kode pertama %q replaced=%v err=%v", first, replaced, err)
	}
	second, replaced, err := s.RotateSiteJoinCode(ctx, site, "staf-01", at.Add(time.Minute))
	if err != nil || !replaced || second == first || !joinCodePattern.MatchString(second) {
		t.Fatalf("rotasi %q replaced=%v err=%v (lama %q)", second, replaced, err, first)
	}
	if _, err := s.SiteByJoinCode(ctx, first); !errors.Is(err, ErrNotFound) {
		t.Fatalf("kode lama masih berlaku: %v", err)
	}
	ref, err := s.SiteByJoinCode(ctx, second)
	if err != nil || ref.ID != site || ref.Name != "Menara Uji" {
		t.Fatalf("kode baru: %+v %v", ref, err)
	}
	// Audit di rantai gedung tanpa nilai kode.
	var actor, subject, data string
	var n int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM audit_events WHERE action = 'site.join_code_rotated'`).Scan(&n); err != nil || n != 2 {
		t.Fatalf("audit rotasi: %d %v", n, err)
	}
	if err := s.pool.QueryRow(ctx, `SELECT actor, subject, data::text FROM audit_events WHERE action = 'site.join_code_rotated' ORDER BY seq DESC LIMIT 1`).Scan(&actor, &subject, &data); err != nil {
		t.Fatal(err)
	}
	if actor != "operator:staf-01" || subject != "site:"+site {
		t.Fatalf("audit %q %q", actor, subject)
	}
	var dump string
	if err := s.pool.QueryRow(ctx, `SELECT coalesce(string_agg(actor || subject || data::text, ' '), '') FROM audit_events`).Scan(&dump); err != nil {
		t.Fatal(err)
	}
	for _, code := range []string{first, second, strings.ToLower(first), strings.ToLower(second)} {
		if strings.Contains(dump, code) {
			t.Fatalf("audit memuat kode gedung %q", code)
		}
	}
}

func TestRotasiKodeGedungValidasi(t *testing.T) {
	s := freshStore(t)
	site, _ := seed(t, s)
	ctx := context.Background()
	at := time.Unix(1_794_000_000, 0)
	if _, _, err := s.RotateSiteJoinCode(ctx, site, "", at); !errors.Is(err, ErrInvalidOperator) {
		t.Fatalf("operator kosong: %v", err)
	}
	for _, bad := range []string{"bukan-uuid", "00000000-0000-4000-8000-000000000000"} {
		if _, _, err := s.RotateSiteJoinCode(ctx, bad, "staf-01", at); !errors.Is(err, ErrNotFound) {
			t.Fatalf("gedung %q: %v", bad, err)
		}
	}
	var n int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM audit_events`).Scan(&n); err != nil || n != 0 {
		t.Fatalf("penolakan tidak boleh diaudit: %d %v", n, err)
	}
}

func TestCariKodeGedung(t *testing.T) {
	s := freshStore(t)
	site, _ := seed(t, s)
	ctx := context.Background()
	code, _, err := s.RotateSiteJoinCode(ctx, site, "staf-01", time.Unix(1_794_000_000, 0))
	if err != nil {
		t.Fatal(err)
	}
	typed := strings.ToLower(code[:4] + "-" + code[4:])
	ref, err := s.SiteByJoinCode(ctx, typed)
	if err != nil || ref.ID != site || ref.Name != "Menara Uji" {
		t.Fatalf("kode diketik %q: %+v %v", typed, ref, err)
	}
	for _, bad := range []string{"", "abc", "7K2Q9XU4", strings.Repeat("A", 100)} {
		if _, err := s.SiteByJoinCode(ctx, bad); !errors.Is(err, ErrNotFound) {
			t.Fatalf("kode %q: %v", bad, err)
		}
	}
}
