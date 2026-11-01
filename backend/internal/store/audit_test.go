package store

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"strings"
	"sync"
	"testing"
	"time"
)

func newAuditSite(t *testing.T, s *Store, code byte) string {
	t.Helper()
	ctx := context.Background()
	orgID, err := s.CreateOrganization(ctx, "Org", "ID")
	if err != nil {
		t.Fatal(err)
	}
	siteID, err := s.CreateSite(ctx, orgID, "Menara", "ID", "Asia/Jakarta", []byte{code, 2, 3, 4, 5, 6, 7, 8})
	if err != nil {
		t.Fatal(err)
	}
	return siteID
}

func auditEvent(siteID string, i int) AuditEvent {
	return AuditEvent{
		SiteID: siteID, Actor: "device:d1", Action: "credential.provisioned",
		Subject: fmt.Sprintf("credential:%02x", i), Data: map[string]any{"channel": "ble"},
		At: time.Unix(1_794_000_000+int64(i), 0),
	}
}

type auditRow struct {
	seq        int64
	prev, hash []byte
}

func auditRows(t *testing.T, s *Store, chain string) []auditRow {
	t.Helper()
	rows, err := s.pool.Query(context.Background(), `SELECT seq, prev_hash, hash FROM audit_events WHERE chain = $1 ORDER BY seq`, chain)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var out []auditRow
	for rows.Next() {
		var r auditRow
		if err := rows.Scan(&r.seq, &r.prev, &r.hash); err != nil {
			t.Fatal(err)
		}
		out = append(out, r)
	}
	return out
}

func TestHashAuditVektor(t *testing.T) {
	// Nilai dihitung implementasi Python independen (hashlib + json sort_keys).
	got := auditHash(make([]byte, 32), 1, "site:00000000-0000-0000-0000-000000000001",
		time.Unix(1_794_000_000, 123_456_000), "device:d1", "credential.provisioned", "credential:aa",
		[]byte(`{"channel": "ble", "not_after": "2026-11-08T00:00:00Z"}`))
	// Tag berversi dan data = teks jsonb PostgreSQL (review audit I1).
	if want := "072a636f63d58bfdd43ab773c7566e63aad17fbe828ef27c58c65b1c9482a26e"; hex.EncodeToString(got) != want {
		t.Fatalf("hash = %x, ingin %s", got, want)
	}
}

func TestAuditBerantai(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()
	site := newAuditSite(t, s, 1)
	for i := 0; i < 3; i++ {
		if err := s.AppendAudit(ctx, auditEvent(site, i)); err != nil {
			t.Fatal(err)
		}
	}
	rows := auditRows(t, s, AuditChain(site))
	if len(rows) != 3 || rows[0].seq != 1 || string(rows[0].prev) != string(make([]byte, 32)) {
		t.Fatalf("baris: %+v", rows)
	}
	for i := 1; i < 3; i++ {
		if rows[i].seq != int64(i+1) || string(rows[i].prev) != string(rows[i-1].hash) {
			t.Fatalf("rantai putus di %d", i)
		}
	}
	if n, err := s.VerifyAuditChain(ctx, AuditChain(site)); err != nil || n != 3 {
		t.Fatalf("verify = %d, %v", n, err)
	}
}

func TestAuditPerGedungTerpisah(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()
	a, b := newAuditSite(t, s, 1), newAuditSite(t, s, 2)
	if err := s.AppendAudit(ctx, auditEvent(a, 0)); err != nil {
		t.Fatal(err)
	}
	if err := s.AppendAudit(ctx, auditEvent(b, 0)); err != nil {
		t.Fatal(err)
	}
	for _, site := range []string{a, b} {
		rows := auditRows(t, s, AuditChain(site))
		if len(rows) != 1 || rows[0].seq != 1 {
			t.Fatalf("rantai %s: %+v", site, rows)
		}
	}
}

func TestAuditTidakBisaDiubah(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()
	site := newAuditSite(t, s, 1)
	if err := s.AppendAudit(ctx, auditEvent(site, 0)); err != nil {
		t.Fatal(err)
	}
	for _, stmt := range []string{`UPDATE audit_events SET actor = 'x'`, `DELETE FROM audit_events`, `TRUNCATE audit_events`} {
		if _, err := s.pool.Exec(ctx, stmt); err == nil {
			t.Fatalf("%s diterima", stmt)
		}
	}
}

func TestAuditManipulasiTerdeteksi(t *testing.T) {
	// Review Focus 2: DBA mematikan trigger lalu mengubah atau menghapus baris.
	for name, tamper := range map[string]string{
		"ubah":  `UPDATE audit_events SET data = '{"channel":"nfcHCE"}' WHERE chain = $1 AND seq = 2`,
		"hapus": `DELETE FROM audit_events WHERE chain = $1 AND seq = 2`,
	} {
		t.Run(name, func(t *testing.T) {
			s := freshStore(t)
			ctx := context.Background()
			site := newAuditSite(t, s, 1)
			for i := 0; i < 3; i++ {
				if err := s.AppendAudit(ctx, auditEvent(site, i)); err != nil {
					t.Fatal(err)
				}
			}
			if _, err := s.pool.Exec(ctx, `ALTER TABLE audit_events DISABLE TRIGGER USER`); err != nil {
				t.Fatal(err)
			}
			if _, err := s.pool.Exec(ctx, tamper, AuditChain(site)); err != nil {
				t.Fatal(err)
			}
			_, err := s.VerifyAuditChain(ctx, AuditChain(site))
			var tampered *AuditTamperedError
			if !errors.Is(err, ErrAuditTampered) || !errors.As(err, &tampered) || tampered.Seq != 2 {
				t.Fatalf("err = %v, ingin rusak di seq 2", err)
			}
		})
	}
}

func TestAuditBersamaanTetapBerantai(t *testing.T) {
	// Review Focus 1: penambahan paralel di gedung yang sama tidak bercabang.
	s := freshStore(t)
	ctx := context.Background()
	site := newAuditSite(t, s, 1)
	var wg sync.WaitGroup
	errs := make(chan error, 10)
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			errs <- s.AppendAudit(ctx, auditEvent(site, i))
		}(i)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	if n, err := s.VerifyAuditChain(ctx, AuditChain(site)); err != nil || n != 10 {
		t.Fatalf("verify = %d, %v", n, err)
	}
}

func TestAuditDataNumerikTetapTerverifikasi(t *testing.T) {
	// Review audit I1: data valid tidak boleh memicu alarm manipulasi setelah lewat jsonb.
	s := freshStore(t)
	ctx := context.Background()
	site := newAuditSite(t, s, 1)
	e := auditEvent(site, 0)
	e.Data = map[string]any{"v": 1e-7, "w": 1e21, "z": math.Copysign(0, -1), "s": "<&>é"}
	if err := s.AppendAudit(ctx, e); err != nil {
		t.Fatal(err)
	}
	if n, err := s.VerifyAuditChain(ctx, AuditChain(site)); err != nil || n != 1 {
		t.Fatalf("verify = %d, %v", n, err)
	}
}

func TestAuditTolakNULDanWaktuKosong(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()
	site := newAuditSite(t, s, 1)
	withNUL := auditEvent(site, 0)
	withNUL.Data = map[string]any{"s": "a\x00b"}
	noTime := auditEvent(site, 1)
	noTime.At = time.Time{}
	for _, e := range []AuditEvent{withNUL, noTime} {
		if err := s.AppendAudit(ctx, e); err == nil {
			t.Fatalf("event diterima: %+v", e)
		}
	}
}

func TestAuditChainKanonik(t *testing.T) {
	// Review audit C1: huruf besar dari klien tidak boleh membuat rantai kedua.
	id := "0F41AB12-0000-4000-8000-00000000ABCD"
	if got := AuditChain(id); got != "site:"+strings.ToLower(id) {
		t.Fatalf("chain = %s", got)
	}
}

func TestAuditChainHarusCocokDenganSite(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()
	site := newAuditSite(t, s, 1)
	_, err := s.pool.Exec(ctx, `INSERT INTO audit_events (chain, site_id, seq, at, actor, action, subject, prev_hash, hash)
		VALUES ('site:lain', $1, 1, now(), 'a', 'b', 'c', $2, $2)`, site, make([]byte, 32))
	if err == nil {
		t.Fatal("baris dengan chain tak cocok site_id diterima")
	}
}

func TestAuditHeads(t *testing.T) {
	// Review audit I2: head per rantai untuk dicatat ke log terpusat (anchor parsial).
	s := freshStore(t)
	ctx := context.Background()
	a, b := newAuditSite(t, s, 1), newAuditSite(t, s, 2)
	for i := 0; i < 3; i++ {
		if err := s.AppendAudit(ctx, auditEvent(a, i)); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.AppendAudit(ctx, auditEvent(b, 0)); err != nil {
		t.Fatal(err)
	}
	heads, err := s.AuditHeads(ctx)
	if err != nil || len(heads) != 2 {
		t.Fatalf("heads = %+v, %v", heads, err)
	}
	for _, h := range heads {
		rows := auditRows(t, s, h.Chain)
		last := rows[len(rows)-1]
		if h.Seq != last.seq || string(h.Hash) != string(last.hash) {
			t.Fatalf("head %s tidak cocok", h.Chain)
		}
	}
}

func TestAuditWaktuTidakMundur(t *testing.T) {
	// Review audit minor 3: waktu dari pemanggil bisa lebih awal dari baris sebelumnya
	// (diambil sebelum menunggu kunci); urutan waktu sepanjang seq tidak boleh mundur.
	s := freshStore(t)
	ctx := context.Background()
	site := newAuditSite(t, s, 1)
	later, earlier := auditEvent(site, 10), auditEvent(site, 0)
	for _, e := range []AuditEvent{later, earlier} {
		if err := s.AppendAudit(ctx, e); err != nil {
			t.Fatal(err)
		}
	}
	events, err := s.AuditEvents(ctx, AuditChain(site))
	if err != nil || len(events) != 2 {
		t.Fatalf("events: %v %v", events, err)
	}
	if events[1].At.Before(events[0].At) {
		t.Fatalf("waktu mundur: %v lalu %v", events[0].At, events[1].At)
	}
	if n, err := s.VerifyAuditChain(ctx, AuditChain(site)); err != nil || n != 2 {
		t.Fatalf("verify = %d, %v", n, err)
	}
}
