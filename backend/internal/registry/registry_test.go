package registry

import (
	"bytes"
	"context"
	"encoding/hex"
	"testing"
)

const (
	testMaster = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
	testSite   = "6f1c2d3e-4a5b-4c6d-8e9f-0a1b2c3d4e5f"
)

func TestIdentitasPerTeknologi(t *testing.T) {
	valid := []struct{ tech, id string }{
		{"iso14443a", "04a1b2c3"},
		{"iso14443a", "04a1b2c3d4e5f6"},
		{"iso14443a", "04a1b2c3d4e5f6070809"},
		{"iso15693", "e004010203040506"},
		{"felica", "0123456789abcdef"},
		{"iso7816", "01"},
		{"iso7816", "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"},
	}
	for _, c := range valid {
		if _, err := ParseCardIdentity(c.tech, c.id); err != nil {
			t.Errorf("%s/%s ditolak: %v", c.tech, c.id, err)
		}
	}
	invalid := []struct{ tech, id string }{
		{"iso14443a", "04a1b2c3d4"},    // 5 B
		{"iso15693", "e0040102030405"}, // 7 B
		{"felica", "0123456789abcdef01"},
		{"iso7816", ""},
		{"iso7816", "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f2021"}, // 33 B
		{"iso9999", "0102030405060708"},
		{"iso14443a", "zz"},
	}
	for _, c := range invalid {
		if _, err := ParseCardIdentity(c.tech, c.id); err == nil {
			t.Errorf("%s/%s seharusnya ditolak", c.tech, c.id)
		}
	}
}

func TestMACInputKanonik(t *testing.T) {
	id, err := ParseCardIdentity("iso14443a", "04A1B2C3D4E5F6")
	if err != nil {
		t.Fatal(err)
	}
	want := append([]byte("ANP1-CARD-v1"), 1, 7)
	want = append(want, 0x04, 0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6)
	if !bytes.Equal(id.MACInput(), want) {
		t.Fatalf("MACInput = %x, ingin %x", id.MACInput(), want)
	}
	// Byte yang sama pada teknologi berbeda tidak boleh bertabrakan.
	a, _ := ParseCardIdentity("iso15693", "0102030405060708")
	b, _ := ParseCardIdentity("felica", "0102030405060708")
	if bytes.Equal(a.MACInput(), b.MACInput()) {
		t.Fatal("iso15693 dan felica menghasilkan masukan MAC yang sama")
	}
}

func TestNormalisasiKontak(t *testing.T) {
	ok := map[string]string{
		" User@Example.COM ":  "user@example.com",
		"+62 812-3456-7890":   "+6281234567890",
		"+62 (812) 3456.7890": "+6281234567890",
	}
	for raw, want := range ok {
		got, err := NormalizeContact(raw)
		if err != nil || got != want {
			t.Errorf("NormalizeContact(%q) = %q, %v; ingin %q", raw, got, err, want)
		}
	}
	for _, raw := range []string{"", "081234567890", "+1234567", "+1234567890123456", "+62abc4567890", "user@", "@example.com"} {
		if got, err := NormalizeContact(raw); err == nil {
			t.Errorf("NormalizeContact(%q) = %q, seharusnya ditolak", raw, got)
		}
	}
	if !bytes.Equal(ContactMACInput("+6281234567890"), []byte("ANP1-CONTACT-v1+6281234567890")) {
		t.Fatal("ContactMACInput tidak kanonik")
	}
}

func TestDevMACVektor(t *testing.T) {
	// Vektor dihitung independen dengan Python (hmac + HKDF RFC 5869).
	mac, err := NewDevMAC(testMaster)
	if err != nil {
		t.Fatal(err)
	}
	id, _ := ParseCardIdentity("iso14443a", "04a1b2c3d4e5f6")
	got, err := mac.MAC(context.Background(), testSite, id.MACInput())
	if err != nil {
		t.Fatal(err)
	}
	if hex.EncodeToString(got) != "16248b50421ea46fe0f372a7416e8e0abbab0eb8cdb31e64310f1cf9397817c9" {
		t.Fatalf("MAC kartu = %x", got)
	}
	got, _ = mac.MAC(context.Background(), testSite, ContactMACInput("+6281234567890"))
	if hex.EncodeToString(got) != "94434a2efe08306e07c8afb28f4a6abba8e7ede723bd3386343820ff02c28ba7" {
		t.Fatalf("MAC kontak = %x", got)
	}
}

func TestDevMACPerGedung(t *testing.T) {
	mac, _ := NewDevMAC(testMaster)
	id, _ := ParseCardIdentity("iso14443a", "04a1b2c3d4e5f6")
	other, _ := mac.MAC(context.Background(), "0b9a8c7d-1e2f-4a3b-9c8d-7e6f5a4b3c2d", id.MACInput())
	if hex.EncodeToString(other) != "c023100701c22b0c88b048f31a188bc8970fdac572801254bca15a06fbec09de" {
		t.Fatalf("MAC gedung lain = %x", other)
	}
	// UUID huruf besar adalah gedung yang sama.
	upper, _ := mac.MAC(context.Background(), "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F", id.MACInput())
	if hex.EncodeToString(upper) != "16248b50421ea46fe0f372a7416e8e0abbab0eb8cdb31e64310f1cf9397817c9" {
		t.Fatalf("UUID huruf besar menghasilkan MAC berbeda: %x", upper)
	}
	for _, bad := range []string{"", "zz", testMaster[:62]} {
		if _, err := NewDevMAC(bad); err == nil {
			t.Errorf("NewDevMAC(%q) seharusnya ditolak", bad)
		}
	}
}
