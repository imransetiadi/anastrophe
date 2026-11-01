package main

import (
	"strings"
	"testing"
)

func TestRegistriWajibAdaKunci(t *testing.T) {
	// Tanpa kunci registri yang valid, API menolak start (ADR-0031).
	for _, key := range []string{"", "zz", strings.Repeat("ab", 31)} {
		if _, err := registryFromEnv(func(string) string { return key }); err == nil {
			t.Errorf("kunci %q seharusnya ditolak", key)
		}
	}
	if mac, err := registryFromEnv(func(string) string { return strings.Repeat("ab", 32) }); err != nil || mac == nil {
		t.Fatalf("kunci valid ditolak: %v", err)
	}
}
