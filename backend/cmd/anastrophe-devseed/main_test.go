package main

import "testing"

func TestHanyaDatabaseLokal(t *testing.T) {
	// Review lab M5: devseed menulis data lab, jadi hanya untuk database lokal.
	for dsn, want := range map[string]bool{
		"postgres://lab@127.0.0.1:55433/anastrophe?sslmode=disable": true,
		"postgres://lab@localhost/anastrophe":                       true,
		"postgres://lab@[::1]:5432/anastrophe":                      true,
		"host=/tmp dbname=anastrophe":                               true,
		"postgres://lab@db.prod.example.com/anastrophe":             false,
		"postgres://lab@10.0.0.5/anastrophe":                        false,
	} {
		got, err := localDatabase(dsn)
		if err != nil || got != want {
			t.Errorf("localDatabase(%q) = %v, %v; ingin %v", dsn, got, err, want)
		}
	}
}

func TestKartuLabDariFlag(t *testing.T) {
	// Kartu lab didaftarkan ke registri agar enrolment lab lewat jalur kartu (ADR-0031).
	if id, err := parseLabCard("iso14443a:04a1b2c3d4e5f6"); err != nil || id.Tech != 1 || len(id.ID) != 7 {
		t.Fatalf("kartu lab valid ditolak: %+v %v", id, err)
	}
	for _, bad := range []string{"", "iso14443a", "felica:zz", "iso9999:04a1b2c3"} {
		if _, err := parseLabCard(bad); err == nil {
			t.Errorf("%q seharusnya ditolak", bad)
		}
	}
}
