package store

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"
)

// cardHMAC membuat HMAC uji 32 B yang deterministik; nilai mentah tidak pernah sampai ke store.
func cardHMAC(label string) []byte {
	sum := sha256.Sum256([]byte("kartu:" + label))
	return sum[:]
}

func registrySite(t *testing.T, s *Store, cards ...PhysicalCard) (siteID, deviceID string) {
	t.Helper()
	siteID, deviceID = seed(t, s)
	if len(cards) > 0 {
		if _, _, err := s.UpsertPhysicalCards(context.Background(), siteID, "uji", cards, 0, time.Now()); err != nil {
			t.Fatal(err)
		}
	}
	return siteID, deviceID
}

func newDevice(t *testing.T, s *Store) string {
	t.Helper()
	id, err := s.CreateDevice(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	return id
}

func TestEnrolmentKartuTerdaftar(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()
	siteID, deviceID := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 1})
	id, status, err := s.StartCardEnrollment(ctx, deviceID, siteID, cardHMAC("A"), time.Now())
	if err != nil || status != "PROVISIONING" {
		t.Fatalf("status=%q err=%v", status, err)
	}
	var linked bool
	if err := s.pool.QueryRow(ctx, `SELECT physical_card_id IS NOT NULL FROM card_instances WHERE id = $1`, id).Scan(&linked); err != nil || !linked {
		t.Fatalf("card instance tidak tertaut ke kartu terdaftar (err=%v)", err)
	}
}

func TestKartuTakDikenalDitolak(t *testing.T) {
	s := freshStore(t)
	siteID, deviceID := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A")})
	if _, _, err := s.StartCardEnrollment(context.Background(), deviceID, siteID, cardHMAC("B"), time.Now()); !errors.Is(err, ErrNotRegistered) {
		t.Fatalf("err=%v", err)
	}
}

func TestKartuRemovedSamaDenganTakDikenal(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()
	siteID, deviceID := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A")}, PhysicalCard{CardHMAC: cardHMAC("B")})
	if _, err := s.pool.Exec(ctx, `UPDATE physical_cards SET status = 'REMOVED' WHERE card_id_hmac = $1`, cardHMAC("A")); err != nil {
		t.Fatal(err)
	}
	_, _, removed := s.StartCardEnrollment(ctx, deviceID, siteID, cardHMAC("A"), time.Now())
	_, _, unknown := s.StartCardEnrollment(ctx, deviceID, siteID, cardHMAC("Z"), time.Now())
	if !errors.Is(removed, ErrNotRegistered) || !errors.Is(unknown, ErrNotRegistered) {
		t.Fatalf("removed=%v unknown=%v", removed, unknown)
	}
}

func TestGedungTanpaRegistri(t *testing.T) {
	s := freshStore(t)
	siteID, deviceID := registrySite(t, s)
	if _, _, err := s.StartCardEnrollment(context.Background(), deviceID, siteID, cardHMAC("A"), time.Now()); !errors.Is(err, ErrSiteUnsupported) {
		t.Fatalf("err=%v", err)
	}
}

func TestPerangkatKeduaMenungguPersetujuan(t *testing.T) {
	// ADR-0032: sebelum ada akun, perangkat tambahan untuk kartu yang sama menunggu persetujuan.
	s := freshStore(t)
	ctx := context.Background()
	siteID, first := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A")})
	second := newDevice(t, s)
	if _, st, err := s.StartCardEnrollment(ctx, first, siteID, cardHMAC("A"), time.Now()); err != nil || st != "PROVISIONING" {
		t.Fatalf("pertama: %q %v", st, err)
	}
	if _, st, err := s.StartCardEnrollment(ctx, second, siteID, cardHMAC("A"), time.Now()); err != nil || st != "PENDING_APPROVAL" {
		t.Fatalf("kedua: %q %v", st, err)
	}
}

func TestPerangkatSamaDuplikat(t *testing.T) {
	// ADR-0034: hanya instance ACTIVE/SUSPENDED milik perangkat yang sama yang menjadi duplikat.
	s := freshStore(t)
	ctx := context.Background()
	siteID, deviceID := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A")})
	id, _, err := s.StartCardEnrollment(ctx, deviceID, siteID, cardHMAC("A"), time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err := s.SetCardInstanceStatus(ctx, id, "ACTIVE"); err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.StartCardEnrollment(ctx, deviceID, siteID, cardHMAC("A"), time.Now()); !errors.Is(err, ErrDuplicateEnrollment) {
		t.Fatalf("err=%v", err)
	}
	// Setelah kartunya dihapus, perangkat yang sama boleh mendaftar lagi (ADR-0032).
	if err := s.SetCardInstanceStatus(ctx, id, "DELETED"); err != nil {
		t.Fatal(err)
	}
	if again, st, err := s.StartCardEnrollment(ctx, deviceID, siteID, cardHMAC("A"), time.Now()); err != nil || st != "PROVISIONING" || again == id {
		t.Fatalf("daftar ulang: %q %q %v", again, st, err)
	}
}

func TestPerangkatSamaMelanjutkanEnrolment(t *testing.T) {
	// ADR-0034: percobaan ulang perangkat yang sama melanjutkan instance yang belum selesai.
	s := freshStore(t)
	ctx := context.Background()
	siteID, deviceID := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A")})
	first, err := s.EnrollCard(ctx, deviceID, siteID, cardHMAC("A"), time.Now())
	if err != nil || first.Resumed || first.Status != "PROVISIONING" {
		t.Fatalf("pertama: %+v %v", first, err)
	}
	again, err := s.EnrollCard(ctx, deviceID, siteID, cardHMAC("A"), time.Now())
	if err != nil || !again.Resumed || again.ID != first.ID || again.Status != "PROVISIONING" {
		t.Fatalf("ulang: %+v %v", again, err)
	}
	var n int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM card_instances`).Scan(&n); err != nil || n != 1 {
		t.Fatalf("card instance = %d (%v), ingin 1", n, err)
	}
}

func TestDisetujuiLaluDilanjutkan(t *testing.T) {
	// ADR-0034: perangkat tambahan yang disetujui operator bisa melanjutkan ke kredensial.
	s := freshStore(t)
	ctx := context.Background()
	siteID, a := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A")})
	b := newDevice(t, s)
	if _, err := s.EnrollCard(ctx, a, siteID, cardHMAC("A"), time.Now()); err != nil {
		t.Fatal(err)
	}
	pending, err := s.EnrollCard(ctx, b, siteID, cardHMAC("A"), time.Now())
	if err != nil || pending.Status != "PENDING_APPROVAL" {
		t.Fatalf("tambahan: %+v %v", pending, err)
	}
	if again, err := s.EnrollCard(ctx, b, siteID, cardHMAC("A"), time.Now()); err != nil || !again.Resumed || again.ID != pending.ID || again.Status != "PENDING_APPROVAL" {
		t.Fatalf("ulang sebelum disetujui: %+v %v", again, err)
	}
	if err := s.DecideEnrollment(ctx, pending.ID, true, "budi", time.Now()); err != nil {
		t.Fatal(err)
	}
	if approved, err := s.EnrollCard(ctx, b, siteID, cardHMAC("A"), time.Now()); err != nil || !approved.Resumed || approved.ID != pending.ID || approved.Status != "PROVISIONING" {
		t.Fatalf("setelah disetujui: %+v %v", approved, err)
	}
}

func TestProvisioningTerbengkalaiKedaluwarsa(t *testing.T) {
	// ADR-0034: PROVISIONING tanpa kredensial lewat 15 menit menjadi ABANDONED dan tidak lagi memblokir.
	s := freshStore(t)
	ctx := context.Background()
	siteID, a := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A")})
	b := newDevice(t, s)
	t0 := time.Unix(1_794_000_000, 0)
	stale, err := s.EnrollCard(ctx, a, siteID, cardHMAC("A"), t0)
	if err != nil {
		t.Fatal(err)
	}
	fresh, err := s.EnrollCard(ctx, b, siteID, cardHMAC("A"), t0.Add(AbandonedEnrollmentTTL+time.Minute))
	if err != nil || fresh.Status != "PROVISIONING" {
		t.Fatalf("perangkat lain setelah kedaluwarsa: %+v %v", fresh, err)
	}
	var status, actor string
	_ = s.pool.QueryRow(ctx, `SELECT status FROM card_instances WHERE id = $1`, stale.ID).Scan(&status)
	_ = s.pool.QueryRow(ctx, `SELECT actor FROM audit_events WHERE action = 'enrollment.abandoned' AND subject = $1`, "card_instance:"+stale.ID).Scan(&actor)
	if status != "ABANDONED" || actor != "system" {
		t.Fatalf("instance terbengkalai: status %q, audit actor %q", status, actor)
	}
}

func TestMelanjutkanMemperbaruiWaktuKedaluwarsa(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()
	siteID, a := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A")})
	b := newDevice(t, s)
	t0 := time.Unix(1_794_000_000, 0)
	if _, err := s.EnrollCard(ctx, a, siteID, cardHMAC("A"), t0); err != nil {
		t.Fatal(err)
	}
	if _, err := s.EnrollCard(ctx, a, siteID, cardHMAC("A"), t0.Add(10*time.Minute)); err != nil {
		t.Fatal(err)
	}
	// 20 menit setelah dibuat tetapi baru 10 menit sejak dilanjutkan: belum terbengkalai.
	if other, err := s.EnrollCard(ctx, b, siteID, cardHMAC("A"), t0.Add(20*time.Minute)); err != nil || other.Status != "PENDING_APPROVAL" {
		t.Fatalf("perangkat lain: %+v %v", other, err)
	}
}

func TestSapuanEnrolmentTerbengkalai(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()
	siteID, a := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A")})
	b := newDevice(t, s)
	t0 := time.Unix(1_794_000_000, 0)
	stale, _ := s.EnrollCard(ctx, a, siteID, cardHMAC("A"), t0)
	pending, _ := s.EnrollCard(ctx, b, siteID, cardHMAC("A"), t0)
	if n, err := s.AbandonStaleEnrollments(ctx, t0.Add(AbandonedEnrollmentTTL+time.Second)); err != nil || n != 1 {
		t.Fatalf("sapuan = %d %v, ingin 1", n, err)
	}
	if n, err := s.AbandonStaleEnrollments(ctx, t0.Add(AbandonedEnrollmentTTL+time.Second)); err != nil || n != 0 {
		t.Fatalf("sapuan kedua = %d %v, ingin 0", n, err)
	}
	for id, want := range map[string]string{stale.ID: "ABANDONED", pending.ID: "PENDING_APPROVAL"} {
		var got string
		_ = s.pool.QueryRow(ctx, `SELECT status FROM card_instances WHERE id = $1`, id).Scan(&got)
		if got != want {
			t.Errorf("status %s = %q, ingin %q", id, got, want)
		}
	}
}

func TestPerangkatPenuhTanpaOracle(t *testing.T) {
	// Review minor 1: perangkat penuh mendapat ENR-LIMIT untuk kartu terdaftar maupun tidak dikenal,
	// tetapi tetap bisa melanjutkan enrolment miliknya.
	s := freshStore(t)
	ctx := context.Background()
	siteID, device := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("X")}, PhysicalCard{CardHMAC: cardHMAC("Y")})
	own, err := s.EnrollCard(ctx, device, siteID, cardHMAC("X"), time.Now())
	if err != nil {
		t.Fatal(err)
	}
	for range MaxActiveCardsPerDevice - 1 {
		if _, err := s.StartEnrollment(ctx, device, siteID, time.Now()); err != nil {
			t.Fatal(err)
		}
	}
	_, _, unknown := s.StartCardEnrollment(ctx, device, siteID, cardHMAC("Z"), time.Now())
	_, _, registered := s.StartCardEnrollment(ctx, device, siteID, cardHMAC("Y"), time.Now())
	if !errors.Is(unknown, ErrCardLimit) || !errors.Is(registered, ErrCardLimit) {
		t.Fatalf("tak dikenal=%v terdaftar=%v, keduanya ingin ErrCardLimit", unknown, registered)
	}
	if resumed, err := s.EnrollCard(ctx, device, siteID, cardHMAC("X"), time.Now()); err != nil || !resumed.Resumed || resumed.ID != own.ID {
		t.Fatalf("melanjutkan saat penuh: %+v %v", resumed, err)
	}
}

func TestEnrolmentBersamaanSatuProvisioning(t *testing.T) {
	// Review Focus 2: dua perangkat yang mendaftarkan kartu sama secara serentak menghasilkan tepat
	// satu PROVISIONING dan satu PENDING_APPROVAL. Diulang untuk 20 kartu dengan penghalang start
	// agar kedua transaksi benar-benar bertumpuk.
	s := freshStore(t)
	ctx := context.Background()
	var cards []PhysicalCard
	for i := range 20 {
		cards = append(cards, PhysicalCard{CardHMAC: cardHMAC(fmt.Sprintf("balapan-%d", i))})
	}
	siteID, _ := registrySite(t, s, cards...)
	for _, c := range cards {
		a, b := newDevice(t, s), newDevice(t, s)
		start := make(chan struct{})
		var wg sync.WaitGroup
		for _, device := range []string{a, b, a, b} {
			wg.Add(1)
			go func() {
				defer wg.Done()
				<-start
				if _, _, err := s.StartCardEnrollment(ctx, device, siteID, c.CardHMAC, time.Now()); err != nil && !errors.Is(err, ErrDuplicateEnrollment) {
					t.Error(err)
				}
			}()
		}
		close(start)
		wg.Wait()
	}
	rows, err := s.pool.Query(ctx, `
		SELECT count(*) FILTER (WHERE status = 'PROVISIONING'), count(*) FILTER (WHERE status = 'PENDING_APPROVAL')
		FROM card_instances WHERE physical_card_id IS NOT NULL GROUP BY physical_card_id`)
	if err != nil {
		t.Fatal(err)
	}
	groups := 0
	for rows.Next() {
		var provisioning, pending int
		if err := rows.Scan(&provisioning, &pending); err != nil {
			t.Fatal(err)
		}
		groups++
		if provisioning != 1 || pending != 1 {
			t.Errorf("satu kartu: PROVISIONING=%d PENDING_APPROVAL=%d", provisioning, pending)
		}
	}
	if groups != len(cards) {
		t.Fatalf("kartu dengan card instance = %d, ingin %d", groups, len(cards))
	}
}

func TestPersetujuanOperator(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()
	siteID, a := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A")})
	b, c := newDevice(t, s), newDevice(t, s)
	first, _, _ := s.StartCardEnrollment(ctx, a, siteID, cardHMAC("A"), time.Now())
	pendingB, _, _ := s.StartCardEnrollment(ctx, b, siteID, cardHMAC("A"), time.Now())
	pendingC, _, _ := s.StartCardEnrollment(ctx, c, siteID, cardHMAC("A"), time.Now())
	if err := s.DecideEnrollment(ctx, pendingB, true, "", time.Now()); !errors.Is(err, ErrInvalidOperator) {
		t.Fatalf("operator kosong: %v", err)
	}
	if err := s.DecideEnrollment(ctx, pendingB, true, "budi", time.Now()); err != nil {
		t.Fatal(err)
	}
	if err := s.DecideEnrollment(ctx, pendingC, false, "budi", time.Now()); err != nil {
		t.Fatal(err)
	}
	if err := s.DecideEnrollment(ctx, first, true, "budi", time.Now()); !errors.Is(err, ErrNotPending) {
		t.Fatalf("menyetujui PROVISIONING: %v", err)
	}
	for id, want := range map[string]string{pendingB: "PROVISIONING", pendingC: "REJECTED"} {
		var got string
		if err := s.pool.QueryRow(ctx, `SELECT status FROM card_instances WHERE id = $1`, id).Scan(&got); err != nil || got != want {
			t.Errorf("status %s = %q, ingin %q (err=%v)", id, got, want, err)
		}
	}
	var actions []string
	rows, _ := s.pool.Query(ctx, `SELECT action || ' ' || actor FROM audit_events WHERE subject = ANY($1) AND action IN ('enrollment.approved', 'enrollment.rejected') ORDER BY seq`, []string{"card_instance:" + pendingB, "card_instance:" + pendingC})
	for rows.Next() {
		var a string
		_ = rows.Scan(&a)
		actions = append(actions, a)
	}
	if strings.Join(actions, ",") != "enrollment.approved operator:budi,enrollment.rejected operator:budi" {
		t.Fatalf("audit keputusan = %v", actions)
	}
}

func TestImportUlangIdempoten(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()
	siteID, _ := seed(t, s)
	cards := []PhysicalCard{{CardHMAC: cardHMAC("A"), ZonesBitmap: 1}, {CardHMAC: cardHMAC("B"), ContactHMAC: cardHMAC("kontak"), ZonesBitmap: 2}}
	if added, updated, err := s.UpsertPhysicalCards(ctx, siteID, "budi", cards, 0, time.Now()); err != nil || added != 2 || updated != 0 {
		t.Fatalf("impor pertama: +%d ~%d %v", added, updated, err)
	}
	cards[0].ZonesBitmap = 3
	if added, updated, err := s.UpsertPhysicalCards(ctx, siteID, "budi", cards, 1, time.Now()); err != nil || added != 0 || updated != 2 {
		t.Fatalf("impor ulang: +%d ~%d %v", added, updated, err)
	}
	var n int
	var zones int64
	_ = s.pool.QueryRow(ctx, `SELECT count(*) FROM physical_cards`).Scan(&n)
	_ = s.pool.QueryRow(ctx, `SELECT zones_bitmap FROM physical_cards WHERE card_id_hmac = $1`, cardHMAC("A")).Scan(&zones)
	if n != 2 || zones != 3 {
		t.Fatalf("baris=%d zona A=%d", n, zones)
	}
	var data string
	_ = s.pool.QueryRow(ctx, `SELECT data::text FROM audit_events WHERE action = 'registry.imported' ORDER BY seq DESC LIMIT 1`).Scan(&data)
	if data != `{"added": 0, "updated": 2, "rejected": 1}` {
		t.Fatalf("audit impor = %s", data)
	}
	if _, _, err := s.UpsertPhysicalCards(ctx, siteID, "budi", []PhysicalCard{{CardHMAC: []byte{1, 2, 3}}}, 0, time.Now()); err == nil {
		t.Fatal("HMAC bukan 32 byte seharusnya ditolak")
	}
}

func TestRegistriTanpaNilaiMentah(t *testing.T) {
	// Audit hanya memuat jumlah, status, dan id internal; tidak pernah HMAC kartu atau kontak.
	s := freshStore(t)
	ctx := context.Background()
	siteID, deviceID := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ContactHMAC: cardHMAC("kontak")})
	if _, _, err := s.StartCardEnrollment(ctx, deviceID, siteID, cardHMAC("A"), time.Now()); err != nil {
		t.Fatal(err)
	}
	rows, err := s.pool.Query(ctx, `SELECT actor || ' ' || action || ' ' || subject || ' ' || data::text FROM audit_events`)
	if err != nil {
		t.Fatal(err)
	}
	for rows.Next() {
		var line string
		_ = rows.Scan(&line)
		for _, secret := range [][]byte{cardHMAC("A"), cardHMAC("kontak")} {
			if strings.Contains(line, hex.EncodeToString(secret)) || strings.Contains(line, base64.StdEncoding.EncodeToString(secret)) {
				t.Fatalf("audit memuat HMAC: %s", line)
			}
		}
	}
}

func TestZonaEnrolmentDariKartu(t *testing.T) {
	// Zona sertifikat dari kartu terdaftar, fail-closed bila bitmap 0 (Review Focus 4).
	s := freshStore(t)
	ctx := context.Background()
	siteID, deviceID := registrySite(t, s,
		PhysicalCard{CardHMAC: cardHMAC("lobi-parkir"), ZonesBitmap: 0b101},
		PhysicalCard{CardHMAC: cardHMAC("tanpa-zona"), ZonesBitmap: 0},
		PhysicalCard{CardHMAC: cardHMAC("bit63"), ZonesBitmap: 1 << 63})
	if err := s.SetSitePolicy(ctx, siteID, []byte(`{"zones": ["Lobi", "Lift A", "Parkir"], "zones_bitmap": 7}`)); err != nil {
		t.Fatal(err)
	}
	want := map[string]struct {
		bitmap uint64
		zones  string
	}{"lobi-parkir": {5, "Lobi,Parkir"}, "tanpa-zona": {0, ""}, "bit63": {1 << 63, ""}}
	for label, w := range want {
		id, _, err := s.StartCardEnrollment(ctx, deviceID, siteID, cardHMAC(label), time.Now())
		if err != nil {
			t.Fatal(err)
		}
		_, _, err = s.Idempotent(ctx, "zona-"+label, []byte("h"), func(ctx context.Context, tx *Tx) (int, []byte, error) {
			e, err := tx.EnrollmentForUpdate(ctx, id)
			if err != nil {
				return 0, nil, err
			}
			if e.ZonesBitmap != w.bitmap || strings.Join(e.Zones, ",") != w.zones {
				t.Errorf("%s: bitmap=%d zona=%v", label, e.ZonesBitmap, e.Zones)
			}
			return 200, []byte("{}"), nil
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}

func TestNamaZonaGedung(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()
	siteID, _ := seed(t, s)
	if names, err := s.SiteZoneNames(ctx, siteID); err != nil || len(names) != 0 {
		t.Fatalf("tanpa kebijakan: %v %v", names, err)
	}
	if err := s.SetSitePolicy(ctx, siteID, []byte(`{"zones": ["Lobi", "Parkir"]}`)); err != nil {
		t.Fatal(err)
	}
	if names, err := s.SiteZoneNames(ctx, siteID); err != nil || strings.Join(names, ",") != "Lobi,Parkir" {
		t.Fatalf("zona: %v %v", names, err)
	}
	if _, err := s.SiteZoneNames(ctx, "00000000-0000-0000-0000-000000000000"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("gedung tak dikenal: %v", err)
	}
}
