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
