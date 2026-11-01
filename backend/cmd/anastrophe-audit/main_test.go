package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/store"
	"github.com/imransetiadi/anastrophe/backend/internal/testpg"
)

var adminDSN, skipReason string

func TestMain(m *testing.M) {
	dsn, stop, err := testpg.Start()
	if err != nil && !errors.Is(err, testpg.ErrUnavailable) {
		fmt.Println("test database gagal:", err)
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

func freshStore(t *testing.T) (*store.Store, string) {
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
	orgID, _ := s.CreateOrganization(ctx, "Org", "ID")
	siteID, err := s.CreateSite(ctx, orgID, "Menara", "ID", "Asia/Jakarta", []byte{1, 2, 3, 4, 5, 6, 7, 8})
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 3; i++ {
		if err := s.AppendAudit(ctx, store.AuditEvent{SiteID: siteID, Actor: "device:d1", Action: "credential.provisioned", Subject: fmt.Sprintf("credential:%02x", i), At: time.Unix(1_794_000_000+int64(i), 0)}); err != nil {
			t.Fatal(err)
		}
	}
	return s, dsn
}

func TestVerifikasiSemuaRantai(t *testing.T) {
	s, _ := freshStore(t)
	var out bytes.Buffer
	tampered, err := verifyAll(context.Background(), s, &out)
	if err != nil || tampered != 0 {
		t.Fatalf("tampered = %d, err = %v", tampered, err)
	}
	var line struct {
		Chain string `json:"chain"`
		Seq   int64  `json:"seq"`
		Hash  string `json:"hash"`
		OK    bool   `json:"ok"`
	}
	if err := json.Unmarshal(bytes.TrimSpace(out.Bytes()), &line); err != nil || !strings.HasPrefix(line.Chain, "site:") || line.Seq != 3 || len(line.Hash) != 64 || !line.OK {
		t.Fatalf("keluaran: %q (%v)", out.String(), err)
	}
}

func TestVerifikasiMelaporkanManipulasi(t *testing.T) {
	s, dsn := freshStore(t)
	ctx := context.Background()
	other, err := store.Open(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer other.Close()
	if err := tamperSecondRow(ctx, dsn); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	tampered, err := verifyAll(ctx, s, &out)
	if err != nil || tampered != 1 || !strings.Contains(out.String(), `"ok":false`) {
		t.Fatalf("tampered = %d, err = %v, keluaran %q", tampered, err, out.String())
	}
}
