package store

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"errors"
	"testing"
)

func TestSeedLab(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()
	groupKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	pub, _ := groupKey.PublicKey.ECDH()
	in := SeedInput{
		OrgName: "Lab", SiteName: "Gedung Lab", SiteCode: []byte{1, 2, 3, 4, 5, 6, 7, 8},
		Zones: []string{"Pintu Lab"}, ZonesBitmap: 1,
		GroupID: []byte{0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8}, GroupKey: pub.Bytes(),
	}
	out, err := s.SeedLab(ctx, in)
	if err != nil {
		t.Fatal(err)
	}
	cardID, err := s.AddCardInstance(ctx, out.DeviceID, out.SiteID)
	if err != nil {
		t.Fatalf("perangkat/gedung seed tidak bisa dipakai: %v", err)
	}
	_, _, err = s.Idempotent(ctx, "seed-cek", []byte("h"), func(ctx context.Context, tx *Tx) (int, []byte, error) {
		e, err := tx.EnrollmentForUpdate(ctx, cardID)
		if err != nil {
			return 0, nil, err
		}
		if e.SiteName != "Gedung Lab" || e.ZonesBitmap != 1 || len(e.Zones) != 1 || e.Zones[0] != "Pintu Lab" {
			t.Errorf("gedung seed: %+v", e)
		}
		keys, err := tx.ReaderGroupKeys(ctx, out.SiteID)
		if err != nil || len(keys["a1a2a3a4a5a6a7a8"]) != 1 {
			t.Errorf("reader group seed: %v %v", keys, err)
		}
		return 200, []byte("{}"), nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.SeedLab(ctx, in); !errors.Is(err, ErrSiteExists) {
		t.Fatalf("seed ulang site code sama: err = %v, ingin ErrSiteExists", err)
	}
}

func labSeedInput(t *testing.T, code byte) SeedInput {
	t.Helper()
	groupKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	pub, _ := groupKey.PublicKey.ECDH()
	return SeedInput{
		OrgName: "Lab", SiteName: "Gedung Lab", SiteCode: []byte{code, 2, 3, 4, 5, 6, 7, 8},
		Zones: []string{"Pintu Lab"}, ZonesBitmap: 1,
		GroupID: []byte{0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8}, GroupKey: pub.Bytes(),
	}
}

func TestSeedLabGroupBentrokBukanSiteExists(t *testing.T) {
	// Review lab M3: -lab-dir (group_id tetap) + -site-code baru tidak boleh dilaporkan
	// sebagai "site_code sudah ada".
	s := freshStore(t)
	ctx := context.Background()
	if _, err := s.SeedLab(ctx, labSeedInput(t, 1)); err != nil {
		t.Fatal(err)
	}
	_, err := s.SeedLab(ctx, labSeedInput(t, 9))
	if !errors.Is(err, ErrReaderGroupExists) || errors.Is(err, ErrSiteExists) {
		t.Fatalf("err = %v, ingin ErrReaderGroupExists", err)
	}
}

func TestAddLabDeviceUntukSiteAda(t *testing.T) {
	// Review lab I1: jalur pulih bila slot kartu perangkat seed habis.
	s := freshStore(t)
	ctx := context.Background()
	in := labSeedInput(t, 1)
	first, err := s.SeedLab(ctx, in)
	if err != nil {
		t.Fatal(err)
	}
	again, err := s.AddLabDevice(ctx, in.SiteCode)
	if err != nil {
		t.Fatal(err)
	}
	if again.SiteID != first.SiteID || again.DeviceID == first.DeviceID {
		t.Fatalf("perangkat baru: %+v vs %+v", again, first)
	}
	if _, err := s.AddCardInstance(ctx, again.DeviceID, again.SiteID); err != nil {
		t.Fatalf("perangkat baru tidak bisa dipakai: %v", err)
	}
	if _, err := s.AddLabDevice(ctx, []byte{9, 9, 9, 9, 9, 9, 9, 9}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("site tak dikenal: err = %v", err)
	}
}
