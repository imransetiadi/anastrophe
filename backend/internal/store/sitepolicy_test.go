package store

import (
	"bytes"
	"context"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"
)

func TestPerbaruiKebijakanSebagian(t *testing.T) {
	// Review Focus 1 (ADR-0049): pembaruan satu kunci tidak menyentuh zona, bitmap 64-bit, atau kunci lain.
	s := freshStore(t)
	site, _ := seed(t, s)
	ctx := context.Background()
	at := time.Unix(1_794_000_000, 0)
	if err := s.SetSitePolicy(ctx, site, []byte(`{"zones": ["Lobi", "Parkir"], "zones_bitmap": 9223372036854775808, "x": "y"}`)); err != nil {
		t.Fatal(err)
	}
	days := 3
	got, err := s.UpdateSitePolicy(ctx, site, "staf-01", PolicyUpdate{CertValidityDays: &days}, at)
	if err != nil || got.CertValidityDays != 3 || got.Channels != nil || got.ZoneCount != 2 {
		t.Fatalf("masa berlaku: %+v %v", got, err)
	}
	channels := []string{"ble"}
	got, err = s.UpdateSitePolicy(ctx, site, "staf-01", PolicyUpdate{Channels: &channels}, at)
	if err != nil || got.CertValidityDays != 3 || !slices.Equal(got.Channels, []string{"ble"}) {
		t.Fatalf("kanal: %+v %v", got, err)
	}
	var raw string
	if err := s.pool.QueryRow(ctx, `SELECT policy::text FROM sites WHERE id = $1`, site).Scan(&raw); err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{`"zones_bitmap": 9223372036854775808`, `"x": "y"`, `"Lobi"`, `"Parkir"`, `"cert_validity_days": 3`, `"channels": ["ble"]`} {
		if !strings.Contains(raw, want) {
			t.Fatalf("policy %s tanpa %s", raw, want)
		}
	}
	all := []string{}
	got, err = s.UpdateSitePolicy(ctx, site, "staf-01", PolicyUpdate{Channels: &all}, at)
	if err != nil || got.Channels != nil || got.CertValidityDays != 3 {
		t.Fatalf("semua kanal: %+v %v", got, err)
	}
	var n int
	var data, actor string
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM audit_events WHERE action = 'site.policy_updated'`).Scan(&n); err != nil || n != 3 {
		t.Fatalf("audit: %d %v", n, err)
	}
	if err := s.pool.QueryRow(ctx, `SELECT actor, data::text FROM audit_events WHERE action = 'site.policy_updated' ORDER BY seq LIMIT 1`).Scan(&actor, &data); err != nil {
		t.Fatal(err)
	}
	if actor != "operator:staf-01" || !strings.Contains(data, `"cert_validity_days": 3`) {
		t.Fatalf("audit pertama %q %s", actor, data)
	}
}

func TestKebijakanTidakValidDitolak(t *testing.T) {
	s := freshStore(t)
	site, _ := seed(t, s)
	ctx := context.Background()
	at := time.Unix(1_794_000_000, 0)
	if err := s.SetSitePolicy(ctx, site, []byte(`{"zones": ["Lobi"], "cert_validity_days": 7}`)); err != nil {
		t.Fatal(err)
	}
	zero, big := 0, 31
	wallet, unknown := []string{"wallet"}, []string{"ble", "x"}
	for _, c := range []struct {
		name     string
		operator string
		site     string
		update   PolicyUpdate
		want     error
	}{
		{"hari 0", "staf-01", site, PolicyUpdate{CertValidityDays: &zero}, ErrInvalidPolicy},
		{"hari 31", "staf-01", site, PolicyUpdate{CertValidityDays: &big}, ErrInvalidPolicy},
		{"kanal wallet", "staf-01", site, PolicyUpdate{Channels: &wallet}, ErrInvalidPolicy},
		{"kanal tak dikenal", "staf-01", site, PolicyUpdate{Channels: &unknown}, ErrInvalidPolicy},
		{"tanpa perubahan", "staf-01", site, PolicyUpdate{}, ErrInvalidPolicy},
		{"operator kosong", "", site, PolicyUpdate{CertValidityDays: &big}, ErrInvalidOperator},
		{"gedung tak dikenal", "staf-01", "00000000-0000-4000-8000-000000000000", PolicyUpdate{Channels: &[]string{"ble"}}, ErrNotFound},
	} {
		if _, err := s.UpdateSitePolicy(ctx, c.site, c.operator, c.update, at); !errors.Is(err, c.want) {
			t.Fatalf("%s: %v, ingin %v", c.name, err, c.want)
		}
	}
	got, err := s.SitePolicyOf(ctx, site)
	if err != nil || got.CertValidityDays != 7 || got.Channels != nil || got.ZoneCount != 1 {
		t.Fatalf("kebijakan berubah: %+v %v", got, err)
	}
	var n int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM audit_events`).Scan(&n); err != nil || n != 0 {
		t.Fatalf("penolakan diaudit: %d %v", n, err)
	}
}

func TestKanalKebijakanTerbawaKeEnrolmentDanLookup(t *testing.T) {
	s := freshStore(t)
	site, device := seed(t, s)
	ctx := context.Background()
	at := time.Unix(1_794_000_000, 0)
	card := bytes.Repeat([]byte{0x42}, 32)
	if _, _, err := s.UpsertPhysicalCards(ctx, site, "uji", []PhysicalCard{{CardHMAC: card}}, 0, at); err != nil {
		t.Fatal(err)
	}
	code, _, err := s.RotateSiteJoinCode(ctx, site, "staf-01", at)
	if err != nil {
		t.Fatal(err)
	}
	ref, err := s.SiteByJoinCode(ctx, code)
	if err != nil || ref.Channels != nil {
		t.Fatalf("tanpa kebijakan kanal: %+v %v", ref, err)
	}
	only := []string{"nfcHCE"}
	if _, err := s.UpdateSitePolicy(ctx, site, "staf-01", PolicyUpdate{Channels: &only}, at); err != nil {
		t.Fatal(err)
	}
	if ref, err = s.SiteByJoinCode(ctx, code); err != nil || !slices.Equal(ref.Channels, only) {
		t.Fatalf("lookup: %+v %v", ref, err)
	}
	var enrolled CardEnrollment
	var policyChannels []string
	var enrollment Enrollment
	err = s.InTx(ctx, func(tx *Tx) error {
		var err error
		if enrolled, err = tx.EnrollCard(ctx, device, site, card, at); err != nil {
			return err
		}
		if policyChannels, err = tx.SiteChannelsOfInstance(ctx, enrolled.ID); err != nil {
			return err
		}
		enrollment, err = tx.EnrollmentForUpdate(ctx, enrolled.ID)
		return err
	})
	if err != nil || !slices.Equal(policyChannels, only) || !slices.Equal(enrollment.Channels, only) {
		t.Fatalf("enrolment: %v %v %v", policyChannels, enrollment.Channels, err)
	}
}

func TestKebijakanTidakBerbentukArrayTidakMenggagalkan(t *testing.T) {
	// Review akhir #1: nilai kebijakan yang ditulis lewat SQL (null, string, objek, [null], []) tidak boleh
	// membuat lookup, enrolment, atau EnrollmentForUpdate gagal; CLI membaca nilai yang sama dengan server.
	ctx := context.Background()
	at := time.Unix(1_794_000_000, 0)
	for i, c := range []struct {
		policy   string
		channels []string // nil = tanpa pembatasan; [] = tidak ada kanal (fail-closed)
		days     int
	}{
		{`{"channels": null}`, nil, 0},
		{`{"channels": "ble"}`, []string{}, 0},
		{`{"channels": {}}`, []string{}, 0},
		{`{"channels": [null]}`, []string{}, 0},
		{`{"channels": []}`, []string{}, 0},
		{`{"channels": ["ble"], "zones": "x"}`, []string{"ble"}, 0},
		{`{"cert_validity_days": "3", "zones": [null, "Lobi"]}`, nil, 3},
	} {
		s := freshStore(t)
		site, device := seed(t, s)
		if err := s.SetSitePolicy(ctx, site, []byte(c.policy)); err != nil {
			t.Fatal(err)
		}
		card := bytes.Repeat([]byte{byte(0x10 + i)}, 32)
		if _, _, err := s.UpsertPhysicalCards(ctx, site, "uji", []PhysicalCard{{CardHMAC: card}}, 0, at); err != nil {
			t.Fatal(err)
		}
		code, _, err := s.RotateSiteJoinCode(ctx, site, "staf-01", at)
		if err != nil {
			t.Fatal(err)
		}
		same := func(got []string) bool {
			return (got == nil) == (c.channels == nil) && slices.Equal(got, c.channels)
		}
		ref, err := s.SiteByJoinCode(ctx, code)
		if err != nil || !same(ref.Channels) {
			t.Fatalf("%s lookup: %#v %v", c.policy, ref.Channels, err)
		}
		policy, err := s.SitePolicyOf(ctx, site)
		if err != nil || !same(policy.Channels) || policy.CertValidityDays != c.days {
			t.Fatalf("%s CLI: %+v %v", c.policy, policy, err)
		}
		var enrollment Enrollment
		err = s.InTx(ctx, func(tx *Tx) error {
			enrolled, err := tx.EnrollCard(ctx, device, site, card, at)
			if err != nil {
				return err
			}
			enrollment, err = tx.EnrollmentForUpdate(ctx, enrolled.ID)
			return err
		})
		if err != nil || !same(enrollment.Channels) || enrollment.CertValidityDays != c.days {
			t.Fatalf("%s enrolment: %#v %d %v", c.policy, enrollment.Channels, enrollment.CertValidityDays, err)
		}
	}
}
