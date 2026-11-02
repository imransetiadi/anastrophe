package loadtest

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/certs"
	"github.com/imransetiadi/anastrophe/backend/internal/enroll"
	"github.com/imransetiadi/anastrophe/backend/internal/httpapi"
	"github.com/imransetiadi/anastrophe/backend/internal/registry"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
	"github.com/imransetiadi/anastrophe/backend/internal/testpg"
)

var adminDSN, skipReason string

func TestMain(m *testing.M) {
	dsn, stop, err := testpg.Start()
	if err != nil && !errors.Is(err, testpg.ErrUnavailable) {
		fmt.Println(err)
		os.Exit(1)
	}
	if err != nil {
		skipReason = err.Error()
	}
	adminDSN = dsn
	code := m.Run()
	stop()
	os.Exit(code)
}

// apiLab menjalankan API in-process dengan PostgreSQL uji dan kartu sintetis terdaftar.
func apiLab(t *testing.T, cards int) *Client {
	t.Helper()
	if adminDSN == "" {
		testpg.Skip(t, skipReason)
	}
	ctx := context.Background()
	dsn, err := testpg.NewDatabase(ctx, adminDSN)
	if err != nil {
		t.Fatal(err)
	}
	s, err := store.Open(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(s.Close)
	if err := s.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	org, _ := s.CreateOrganization(ctx, "Org Beban", "ID")
	site, err := s.CreateSite(ctx, org, "Gedung Beban", "ID", "Asia/Jakarta", []byte{1, 2, 3, 4, 5, 6, 7, 8})
	if err != nil {
		t.Fatal(err)
	}
	groupKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	groupPub, _ := groupKey.PublicKey.ECDH()
	if err := s.AddReaderGroup(ctx, []byte{0xB1, 2, 3, 4, 5, 6, 7, 8}, site, groupPub.Bytes()); err != nil {
		t.Fatal(err)
	}
	mac, err := registry.NewDevMAC("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
	if err != nil {
		t.Fatal(err)
	}
	var csvBuf bytes.Buffer
	if err := GenerateCards(&csvBuf, cards); err != nil {
		t.Fatal(err)
	}
	pool, err := LoadCards(bytes.NewReader(csvBuf.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	var physical []store.PhysicalCard
	for _, id := range pool.ids {
		identity, err := registry.ParseCardIdentity("iso14443a", id)
		if err != nil {
			t.Fatal(err)
		}
		sum, err := mac.MAC(ctx, site, identity.MACInput())
		if err != nil {
			t.Fatal(err)
		}
		physical = append(physical, store.PhysicalCard{CardHMAC: sum})
	}
	if _, _, err := s.UpsertPhysicalCards(ctx, site, "uji", physical, 0, time.Now()); err != nil {
		t.Fatal(err)
	}
	code, _, err := s.RotateSiteJoinCode(ctx, site, "uji", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	caKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	signer := certs.NewSoftwareSigner(caKey)
	h := &enroll.Handler{
		Store: s, Signers: func(string) (certs.Signer, error) { return signer, nil }, Now: time.Now,
		Validity: 7 * 24 * time.Hour, EnabledChannels: []string{"ble"}, Registry: mac,
	}
	server := httptest.NewServer(httpapi.New(httpapi.Config{EnabledChannels: []string{"ble"}}, httpapi.Deps{Routes: h.Register}))
	t.Cleanup(server.Close)
	return &Client{Base: server.URL, HTTP: server.Client(), SiteID: site, JoinCode: code, Cards: pool, Creds: &CredPool{}}
}

func TestSkenarioTerhadapAPI(t *testing.T) {
	// Review Focus 3 (ADR-0055): setiap skenario memakai format protokol yang benar, jadi 0 galat.
	c := apiLab(t, 3)
	rec := NewRecorder()
	ctx := context.Background()
	for i := 0; i < 3; i++ {
		for name, it := range map[string]Iteration{"config": c.Config, "lookup": c.Lookup, "enrol": c.Enrol} {
			if err := it(ctx, rec); err != nil {
				t.Fatalf("%s #%d: %v", name, i, err)
			}
		}
	}
	for i := 0; i < 3; i++ {
		if err := c.Renew(ctx, rec); err != nil {
			t.Fatalf("renew #%d: %v", i, err)
		}
	}
	want := map[string]int{"config": 200, "lookup": 200, "enrol.enrolment": 201, "enrol.provisioning": 200, "renew.challenge": 201, "renew.perpanjangan": 200}
	got := map[string]StepSummary{}
	for _, s := range rec.Summary() {
		got[s.Step] = s
	}
	for step, status := range want {
		s, ok := got[step]
		if !ok || s.Count != 3 || s.Errors != 0 || s.ByStatus[status] != 3 {
			t.Fatalf("langkah %s = %+v, ingin 3× status %d tanpa galat", step, s, status)
		}
	}
	if len(got) != len(want) {
		t.Fatalf("langkah tak terduga: %v", got)
	}
}

func TestRenewTanpaKredensialGagalJelas(t *testing.T) {
	c := &Client{Base: "http://127.0.0.1:1", HTTP: http.DefaultClient, Creds: &CredPool{}}
	rec := NewRecorder()
	if err := c.Renew(context.Background(), rec); err == nil {
		t.Fatal("renew tanpa kredensial tidak gagal")
	}
	if s := rec.Summary(); len(s) != 1 || s[0].Step != "renew.tanpa_kredensial" || s[0].Errors != 1 {
		t.Fatalf("ringkasan = %+v", s)
	}
}

func TestEnrolKartuHabisGagalJelas(t *testing.T) {
	c := &Client{Base: "http://127.0.0.1:1", HTTP: http.DefaultClient, Cards: &CardPool{}, Creds: &CredPool{}}
	rec := NewRecorder()
	if err := c.Enrol(context.Background(), rec); err == nil {
		t.Fatal("enrol tanpa kartu tidak gagal")
	}
	if s := rec.Summary(); len(s) != 1 || s[0].Step != "enrol.kartu_habis" || s[0].Errors != 1 {
		t.Fatalf("ringkasan = %+v", s)
	}
}

func TestStatusTakTerdugaDihitungGalat(t *testing.T) {
	// Galat server tidak boleh tertutupi: status di luar yang diharapkan langkah = galat.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	t.Cleanup(server.Close)
	c := &Client{Base: server.URL, HTTP: server.Client()}
	rec := NewRecorder()
	if err := c.Config(context.Background(), rec); err == nil {
		t.Fatal("status 500 dianggap sukses")
	}
	if s := rec.Summary(); len(s) != 1 || s[0].Errors != 1 || s[0].ByStatus[500] != 1 {
		t.Fatalf("ringkasan = %+v", s)
	}
}
