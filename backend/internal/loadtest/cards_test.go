package loadtest

import (
	"bytes"
	"encoding/csv"
	"strings"
	"testing"
)

func TestKartuSintetis(t *testing.T) {
	var buf bytes.Buffer
	if err := GenerateCards(&buf, 5); err != nil {
		t.Fatal(err)
	}
	rows, err := csv.NewReader(bytes.NewReader(buf.Bytes())).ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 6 || strings.Join(rows[0], ",") != "tech,card_id,holder_contact,zones" {
		t.Fatalf("CSV = %v", rows)
	}
	seen := map[string]bool{}
	for _, r := range rows[1:] {
		if r[0] != "iso14443a" || !strings.HasPrefix(r[1], "084c54") || len(r[1]) != 14 || r[2] != "" || seen[r[1]] {
			t.Fatalf("baris = %v", r)
		}
		seen[r[1]] = true
	}
	pool, err := LoadCards(bytes.NewReader(buf.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 5; i++ {
		if id, ok := pool.Next(); !ok || !seen[id] {
			t.Fatalf("kartu %d = %q %v", i, id, ok)
		}
	}
	if _, ok := pool.Next(); ok {
		t.Fatal("pool tidak habis")
	}
}

func TestLoadCardsMenolakKartuBukanSintetis(t *testing.T) {
	// Anti-goal ADR-0055: alat uji beban tidak boleh memakai identitas kartu nyata.
	in := "tech,card_id,holder_contact,zones\niso14443a,04a1b2c3d4e5f6,,\n"
	if _, err := LoadCards(strings.NewReader(in)); err == nil {
		t.Fatal("kartu bukan sintetis diterima")
	}
}
