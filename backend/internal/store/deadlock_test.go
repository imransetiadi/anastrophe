package store

import (
	"context"
	"errors"
	"sort"
	"strings"
	"testing"
	"time"
)

// waitForLockWait menunggu sampai ada backend lain yang menunggu kunci baris dengan query yang memuat
// fragmen tertentu (pola deterministik, tanpa jeda tetap; ADR-0051).
func waitForLockWait(t *testing.T, s *Store, fragment string) {
	t.Helper()
	ctx := context.Background()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		var n int
		err := s.pool.QueryRow(ctx, `SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND query LIKE '%' || $1 || '%' AND pid <> pg_backend_pid()`, fragment).Scan(&n)
		if err != nil {
			t.Fatal(err)
		}
		if n > 0 {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("tidak ada transaksi yang menunggu kunci untuk %q", fragment)
}

// auditChainLockFree memeriksa dari koneksi lain bahwa kunci advisory rantai audit gedung tidak dipegang.
func auditChainLockFree(t *testing.T, s *Store, site string) bool {
	t.Helper()
	ctx := context.Background()
	conn, err := s.pool.Acquire(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Release()
	var free bool
	if err := conn.QueryRow(ctx, `SELECT pg_try_advisory_lock($1, hashtext($2))`, auditLockNamespace, AuditChain(site)).Scan(&free); err != nil {
		t.Fatal(err)
	}
	if free {
		if _, err := conn.Exec(ctx, `SELECT pg_advisory_unlock($1, hashtext($2))`, auditLockNamespace, AuditChain(site)); err != nil {
			t.Fatal(err)
		}
	}
	return free
}

func abandonedAudits(t *testing.T, s *Store, instance string) int {
	t.Helper()
	var n int
	if err := s.pool.QueryRow(context.Background(), `SELECT count(*) FROM audit_events WHERE action = 'enrollment.abandoned' AND subject = $1`, "card_instance:"+instance).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestEnrolmentKartuTidakMemegangKunciAuditSaatMenunggu(t *testing.T) {
	// Review Focus 1 (ADR-0051): enrolment menandai instance basi lalu harus menunggu baris instance yang
	// dilanjutkan; selama menunggu, kunci rantai audit gedung tidak boleh dipegang (sumber deadlock 40P01
	// dengan sapuan per jam).
	s := freshStore(t)
	site, _ := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 1}, PhysicalCard{CardHMAC: cardHMAC("B"), ZonesBitmap: 1})
	device := newDevice(t, s)
	ctx := context.Background()
	t0 := time.Now().Add(-time.Hour)
	stale, err := s.EnrollCard(ctx, device, site, cardHMAC("A"), t0)
	if err != nil {
		t.Fatal(err)
	}
	resumed, err := s.EnrollCard(ctx, device, site, cardHMAC("B"), t0.Add(10*time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	holder, err := s.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer holder.Rollback(ctx)
	if _, err := holder.Exec(ctx, `SELECT id FROM card_instances WHERE id = $1 FOR UPDATE`, resumed.ID); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		_, err := s.EnrollCard(ctx, device, site, cardHMAC("B"), t0.Add(20*time.Minute))
		done <- err
	}()
	waitForLockWait(t, s, "status_changed_at")
	free := auditChainLockFree(t, s, site)
	if err := holder.Rollback(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatalf("enrolment sesudah kunci dilepas: %v", err)
	}
	if !free {
		t.Fatal("enrolment memegang kunci rantai audit sambil menunggu baris instance")
	}
	if n := abandonedAudits(t, s, stale.ID); n != 1 {
		t.Fatalf("audit enrollment.abandoned untuk instance basi = %d, ingin 1", n)
	}
}

func TestEnrolmentUndanganTidakMemegangKunciAuditSaatMenunggu(t *testing.T) {
	// Review Focus 2: jalur undangan dengan pola yang sama.
	s := freshStore(t)
	site, _ := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 1})
	device := newDevice(t, s)
	ctx := context.Background()
	t0 := time.Now().Add(-time.Hour)
	stale, err := s.EnrollCard(ctx, device, site, cardHMAC("A"), t0)
	if err != nil {
		t.Fatal(err)
	}
	created, err := s.CreateInvitation(ctx, Invitation{SiteID: site, ZonesBitmap: 1, TTL: 7 * 24 * time.Hour}, "staf-01", t0)
	if err != nil {
		t.Fatal(err)
	}
	tokenHash, err := InvitationTokenHash(created.Token)
	if err != nil {
		t.Fatal(err)
	}
	var resumed CardEnrollment
	if err := s.InTx(ctx, func(tx *Tx) error {
		var err error
		resumed, err = tx.EnrollInvitation(ctx, device, tokenHash, t0.Add(10*time.Minute))
		return err
	}); err != nil {
		t.Fatal(err)
	}
	holder, err := s.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer holder.Rollback(ctx)
	if _, err := holder.Exec(ctx, `SELECT id FROM card_instances WHERE id = $1 FOR UPDATE`, resumed.ID); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		done <- s.InTx(ctx, func(tx *Tx) error {
			_, err := tx.EnrollInvitation(ctx, device, tokenHash, t0.Add(20*time.Minute))
			return err
		})
	}()
	waitForLockWait(t, s, "status_changed_at")
	free := auditChainLockFree(t, s, site)
	if err := holder.Rollback(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatalf("enrolment undangan sesudah kunci dilepas: %v", err)
	}
	if !free {
		t.Fatal("enrolment undangan memegang kunci rantai audit sambil menunggu baris instance")
	}
	if n := abandonedAudits(t, s, stale.ID); n != 1 {
		t.Fatalf("audit enrollment.abandoned untuk instance basi = %d, ingin 1", n)
	}
}

func TestAuditTertundaDiurutkanPerRantai(t *testing.T) {
	// Review Focus 4: event yang ditahan ditulis berurutan per rantai (urutan global yang sama untuk semua
	// transaksi), dan urutan di dalam satu rantai dipertahankan.
	s := freshStore(t)
	ctx := context.Background()
	siteB, _ := seed(t, s)
	org, err := s.CreateOrganization(ctx, "Org Lain", "ID")
	if err != nil {
		t.Fatal(err)
	}
	siteA, err := s.CreateSite(ctx, org, "Gedung Lain", "ID", "Asia/Jakarta", []byte{9, 9, 9, 9, 9, 9, 9, 9})
	if err != nil {
		t.Fatal(err)
	}
	first, second := AuditChain(siteA), AuditChain(siteB)
	if second < first {
		siteA, siteB = siteB, siteA
		first, second = second, first
	}
	at := time.Unix(1_794_000_000, 0)
	err = s.InTx(ctx, func(tx *Tx) error {
		tx.deferAudits()
		for _, e := range []AuditEvent{
			{SiteID: siteB, Actor: "system", Action: "uji.b1", Subject: "x", At: at},
			{SiteID: siteA, Actor: "system", Action: "uji.a1", Subject: "x", At: at},
			{SiteID: siteB, Actor: "system", Action: "uji.b2", Subject: "x", At: at},
		} {
			if err := tx.AppendAudit(ctx, e); err != nil {
				return err
			}
		}
		var written int
		if err := tx.tx.QueryRow(ctx, `SELECT count(*) FROM audit_events`).Scan(&written); err != nil || written != 0 {
			t.Fatalf("event tertunda sudah tertulis sebelum flush: %d %v", written, err)
		}
		return tx.flushAudits(ctx)
	})
	if err != nil {
		t.Fatal(err)
	}
	rows, err := s.pool.Query(ctx, `SELECT chain, action FROM audit_events ORDER BY id`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var order []string
	for rows.Next() {
		var chain, action string
		if err := rows.Scan(&chain, &action); err != nil {
			t.Fatal(err)
		}
		order = append(order, chain+" "+action)
	}
	got := strings.Join(order, ", ")
	expected := strings.Join([]string{first + " uji.a1", second + " uji.b1", second + " uji.b2"}, ", ")
	if got != expected {
		t.Fatalf("urutan = %s, ingin %s", got, expected)
	}
}

func TestEnrolmentMenungguPersetujuanTidakMemegangKunciAudit(t *testing.T) {
	// Ruling Task 1 (ADR-0051): instance PENDING_APPROVAL yang dilanjutkan dikunci di dalam enrolment, jadi
	// pemasangan rahasia enrolment sesudah flush (handler, ADR-0040) tidak menunggu baris sambil memegang
	// kunci rantai audit (siklus dengan DecideEnrollment yang mengunci baris lalu menulis audit).
	s := freshStore(t)
	site, _ := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 1}, PhysicalCard{CardHMAC: cardHMAC("B"), ZonesBitmap: 1})
	device, other := newDevice(t, s), newDevice(t, s)
	ctx := context.Background()
	t0 := time.Now().Add(-time.Hour)
	if _, err := s.EnrollCard(ctx, other, site, cardHMAC("B"), t0); err != nil {
		t.Fatal(err)
	}
	pending, err := s.EnrollCard(ctx, device, site, cardHMAC("B"), t0.Add(time.Minute))
	if err != nil || pending.Status != "PENDING_APPROVAL" {
		t.Fatalf("enrolment perangkat kedua: %+v %v", pending, err)
	}
	stale, err := s.EnrollCard(ctx, device, site, cardHMAC("A"), t0.Add(2*time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	holder, err := s.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer holder.Rollback(ctx)
	if _, err := holder.Exec(ctx, `SELECT id FROM card_instances WHERE id = $1 FOR UPDATE`, pending.ID); err != nil {
		t.Fatal(err)
	}
	type outcome struct {
		r   CardEnrollment
		err error
	}
	done := make(chan outcome, 1)
	go func() {
		var r CardEnrollment
		err := s.InTx(ctx, func(tx *Tx) error {
			var err error
			if r, err = tx.EnrollCard(ctx, device, site, cardHMAC("B"), t0.Add(20*time.Minute)); err != nil {
				return err
			}
			return tx.SetProvisioningKeyHash(ctx, r.ID, make([]byte, 32))
		})
		done <- outcome{r, err}
	}()
	waitForLockWait(t, s, "card_instances")
	free := auditChainLockFree(t, s, site)
	if err := holder.Rollback(ctx); err != nil {
		t.Fatal(err)
	}
	got := <-done
	if got.err != nil || got.r.ID != pending.ID || got.r.Status != "PENDING_APPROVAL" || !got.r.Resumed {
		t.Fatalf("enrolment sesudah kunci dilepas: %+v %v", got.r, got.err)
	}
	if !free {
		t.Fatal("enrolment memegang kunci rantai audit sambil menunggu baris instance PENDING_APPROVAL")
	}
	if n := abandonedAudits(t, s, stale.ID); n != 1 {
		t.Fatalf("audit enrollment.abandoned untuk instance basi = %d, ingin 1", n)
	}
}

func startedAudits(t *testing.T, s *Store, instance string) int {
	t.Helper()
	var n int
	if err := s.pool.QueryRow(context.Background(), `SELECT count(*) FROM audit_events WHERE action = 'enrollment.started' AND subject = $1`, "card_instance:"+instance).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestPengulanganEnrolmentMenulisAuditTepatSekali(t *testing.T) {
	// Review Focus 3: instance yang hendak dilanjutkan ditandai ABANDONED oleh transaksi lain saat enrolment
	// menunggu, jadi enrolment diulang. Event dari percobaan pertama (abandoned) dan kedua (started) masing-masing
	// ditulis tepat sekali.
	s := freshStore(t)
	site, _ := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 1}, PhysicalCard{CardHMAC: cardHMAC("B"), ZonesBitmap: 1})
	device := newDevice(t, s)
	ctx := context.Background()
	t0 := time.Now().Add(-time.Hour)
	stale, err := s.EnrollCard(ctx, device, site, cardHMAC("A"), t0)
	if err != nil {
		t.Fatal(err)
	}
	resumed, err := s.EnrollCard(ctx, device, site, cardHMAC("B"), t0.Add(10*time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	holder, err := s.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer holder.Rollback(ctx)
	if _, err := holder.Exec(ctx, `UPDATE card_instances SET status = 'ABANDONED' WHERE id = $1`, resumed.ID); err != nil {
		t.Fatal(err)
	}
	type outcome struct {
		r   CardEnrollment
		err error
	}
	done := make(chan outcome, 1)
	go func() {
		r, err := s.EnrollCard(ctx, device, site, cardHMAC("B"), t0.Add(20*time.Minute))
		done <- outcome{r, err}
	}()
	waitForLockWait(t, s, "status_changed_at")
	if err := holder.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	got := <-done
	if got.err != nil || got.r.ID == resumed.ID || got.r.Status != "PROVISIONING" || got.r.Resumed {
		t.Fatalf("enrolment sesudah pengulangan: %+v %v", got.r, got.err)
	}
	if n := abandonedAudits(t, s, stale.ID); n != 1 {
		t.Fatalf("audit enrollment.abandoned dari percobaan pertama = %d, ingin 1", n)
	}
	if n := startedAudits(t, s, got.r.ID); n != 1 {
		t.Fatalf("audit enrollment.started untuk instance baru = %d, ingin 1", n)
	}
}

func TestAuditTertundaTetapDitulisSaatEnrolmentGagal(t *testing.T) {
	// Keputusan builder (ADR-0051): event yang ditahan tetap ditulis saat enrolment gagal, sehingga pemanggil
	// yang meng-commit perubahan sebelum galat (instance basi ditandai ABANDONED) tidak kehilangan auditnya.
	s := freshStore(t)
	site, _ := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 1})
	device := newDevice(t, s)
	ctx := context.Background()
	t0 := time.Now().Add(-time.Hour)
	stale, err := s.EnrollCard(ctx, device, site, cardHMAC("A"), t0)
	if err != nil {
		t.Fatal(err)
	}
	var enrollErr error
	if err := s.InTx(ctx, func(tx *Tx) error {
		_, enrollErr = tx.EnrollCard(ctx, device, site, cardHMAC("tidak-terdaftar"), t0.Add(20*time.Minute))
		return nil // pemanggil meng-commit walau enrolment gagal
	}); err != nil {
		t.Fatal(err)
	}
	if !errors.Is(enrollErr, ErrNotRegistered) {
		t.Fatalf("galat enrolment = %v, ingin ErrNotRegistered", enrollErr)
	}
	var status string
	if err := s.pool.QueryRow(ctx, `SELECT status FROM card_instances WHERE id = $1`, stale.ID).Scan(&status); err != nil || status != "ABANDONED" {
		t.Fatalf("status instance basi = %q %v", status, err)
	}
	if n := abandonedAudits(t, s, stale.ID); n != 1 {
		t.Fatalf("audit enrollment.abandoned = %d, ingin 1", n)
	}
}

func TestSapuanMenulisAuditBerurutanPerRantai(t *testing.T) {
	// Tujuan 3: sapuan per jam menulis audit berurutan per rantai, jadi dua sapuan bersamaan (beberapa
	// instance API) tidak saling mengunci rantai dalam urutan berlawanan.
	s := freshStore(t)
	ctx := context.Background()
	var cards []PhysicalCard
	for _, l := range []string{"1", "2", "3", "4"} {
		cards = append(cards, PhysicalCard{CardHMAC: cardHMAC(l), ZonesBitmap: 1})
	}
	siteB, _ := registrySite(t, s, cards...)
	org, err := s.CreateOrganization(ctx, "Org Lain", "ID")
	if err != nil {
		t.Fatal(err)
	}
	siteA, err := s.CreateSite(ctx, org, "Gedung Lain", "ID", "Asia/Jakarta", []byte{9, 9, 9, 9, 9, 9, 9, 9})
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.UpsertPhysicalCards(ctx, siteA, "uji", cards, 0, time.Now()); err != nil {
		t.Fatal(err)
	}
	t0 := time.Unix(1_794_000_000, 0)
	for _, site := range []string{siteA, siteB} {
		device := newDevice(t, s)
		for _, c := range cards {
			if _, err := s.EnrollCard(ctx, device, site, c.CardHMAC, t0); err != nil {
				t.Fatal(err)
			}
		}
	}
	if n, err := s.AbandonStaleEnrollments(ctx, t0.Add(AbandonedEnrollmentTTL+time.Second)); err != nil || n != 8 {
		t.Fatalf("sapuan = %d %v, ingin 8", n, err)
	}
	rows, err := s.pool.Query(ctx, `SELECT chain FROM audit_events WHERE action = 'enrollment.abandoned' ORDER BY id`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var chains []string
	for rows.Next() {
		var c string
		if err := rows.Scan(&c); err != nil {
			t.Fatal(err)
		}
		chains = append(chains, c)
	}
	if len(chains) != 8 || !sort.StringsAreSorted(chains) {
		t.Fatalf("urutan rantai audit sapuan = %v", chains)
	}
}

func TestEnrolmentMelanjutkanSesudahDisetujuiSaatMenunggu(t *testing.T) {
	// Ruling Task 1: kunci instance PENDING_APPROVAL dijaga status. Bila operator menyetujuinya selama
	// enrolment menunggu, enrolment diulang dan melanjutkan instance itu sebagai PROVISIONING.
	s := freshStore(t)
	site, _ := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("B"), ZonesBitmap: 1})
	device, other := newDevice(t, s), newDevice(t, s)
	ctx := context.Background()
	t0 := time.Now().Add(-time.Hour)
	if _, err := s.EnrollCard(ctx, other, site, cardHMAC("B"), t0); err != nil {
		t.Fatal(err)
	}
	pending, err := s.EnrollCard(ctx, device, site, cardHMAC("B"), t0.Add(time.Minute))
	if err != nil || pending.Status != "PENDING_APPROVAL" {
		t.Fatalf("enrolment perangkat kedua: %+v %v", pending, err)
	}
	holder, err := s.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer holder.Rollback(ctx)
	if _, err := holder.Exec(ctx, `UPDATE card_instances SET status = 'PROVISIONING', status_changed_at = now() WHERE id = $1`, pending.ID); err != nil {
		t.Fatal(err)
	}
	type outcome struct {
		r   CardEnrollment
		err error
	}
	done := make(chan outcome, 1)
	go func() {
		r, err := s.EnrollCard(ctx, device, site, cardHMAC("B"), t0.Add(2*time.Minute))
		done <- outcome{r, err}
	}()
	waitForLockWait(t, s, "card_instances")
	if err := holder.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	got := <-done
	if got.err != nil || got.r.ID != pending.ID || got.r.Status != "PROVISIONING" || !got.r.Resumed {
		t.Fatalf("enrolment sesudah disetujui: %+v %v", got.r, got.err)
	}
}

func TestPenahananAuditBersarang(t *testing.T) {
	// Enrolment di dalam penahanan yang sudah aktif tidak menulis event pemanggil luar lebih awal.
	s := freshStore(t)
	site, _ := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 1})
	device := newDevice(t, s)
	ctx := context.Background()
	err := s.InTx(ctx, func(tx *Tx) error {
		tx.deferAudits()
		if _, err := tx.EnrollCard(ctx, device, site, cardHMAC("A"), time.Now()); err != nil {
			return err
		}
		var written int
		if err := tx.tx.QueryRow(ctx, `SELECT count(*) FROM audit_events WHERE action = 'enrollment.started'`).Scan(&written); err != nil || written != 0 {
			t.Fatalf("event ditulis sebelum flush pemanggil luar: %d %v", written, err)
		}
		return tx.flushAudits(ctx)
	})
	if err != nil {
		t.Fatal(err)
	}
	var n int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM audit_events WHERE action = 'enrollment.started'`).Scan(&n); err != nil || n != 1 {
		t.Fatalf("audit enrollment.started = %d %v, ingin 1", n, err)
	}
}
