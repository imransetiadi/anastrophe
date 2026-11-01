package store

import (
	"context"
	"errors"
	"sync"
	"testing"
)

func seed(t *testing.T, s *Store) (siteID, deviceID string) {
	t.Helper()
	ctx := context.Background()
	orgID, err := s.CreateOrganization(ctx, "Org Uji", "ID")
	if err != nil {
		t.Fatal(err)
	}
	siteID, err = s.CreateSite(ctx, orgID, "Menara Uji", "ID", "Asia/Jakarta", []byte{1, 2, 3, 4, 5, 6, 7, 8})
	if err != nil {
		t.Fatal(err)
	}
	deviceID, err = s.CreateDevice(ctx)
	if err != nil {
		t.Fatal(err)
	}
	return siteID, deviceID
}

func TestBatasDelapanKartu(t *testing.T) {
	// FR-15, TC-ENR-11 (sisi server).
	s := freshStore(t)
	siteID, deviceID := seed(t, s)
	ctx := context.Background()
	for i := 0; i < 8; i++ {
		if _, err := s.AddCardInstance(ctx, deviceID, siteID); err != nil {
			t.Fatalf("kartu ke-%d: %v", i+1, err)
		}
	}
	if _, err := s.AddCardInstance(ctx, deviceID, siteID); !errors.Is(err, ErrCardLimit) {
		t.Fatalf("kartu ke-9: err = %v, ingin ErrCardLimit", err)
	}
}

func TestRaceBatasDelapan(t *testing.T) {
	// Review Focus 3, TC-ENR-12: dua permintaan paralel saat 7 kartu → tepat satu sukses.
	s := freshStore(t)
	siteID, deviceID := seed(t, s)
	ctx := context.Background()
	for i := 0; i < 7; i++ {
		if _, err := s.AddCardInstance(ctx, deviceID, siteID); err != nil {
			t.Fatal(err)
		}
	}
	for round := 0; round < 5; round++ {
		var wg sync.WaitGroup
		results := make([]error, 2)
		for i := range results {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				_, results[i] = s.AddCardInstance(ctx, deviceID, siteID)
			}(i)
		}
		wg.Wait()
		successes := 0
		for _, err := range results {
			if err == nil {
				successes++
			} else if !errors.Is(err, ErrCardLimit) {
				t.Fatal(err)
			}
		}
		want := 0
		if round == 0 {
			want = 1
		}
		if successes != want {
			t.Fatalf("putaran %d: %d sukses, ingin %d", round, successes, want)
		}
	}
	if n, err := s.ActiveCardCount(ctx, deviceID); err != nil || n != 8 {
		t.Fatalf("jumlah aktif = %d (err %v), ingin 8", n, err)
	}
}

func TestMigrateIdempoten(t *testing.T) {
	s := freshStore(t)
	if err := s.Migrate(context.Background()); err != nil {
		t.Fatalf("migrasi kedua: %v", err)
	}
}
