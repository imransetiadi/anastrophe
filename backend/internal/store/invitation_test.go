package store

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

func invite(t *testing.T, s *Store, inv Invitation, at time.Time) string {
	t.Helper()
	if inv.TTL == 0 {
		inv.TTL = 7 * 24 * time.Hour
	}
	token, _, err := s.CreateInvitation(context.Background(), inv, "staf-01", at)
	if err != nil {
		t.Fatal(err)
	}
	return token
}

func redeem(t *testing.T, s *Store, device, token string, at time.Time) (CardEnrollment, error) {
	t.Helper()
	hash, err := InvitationTokenHash(token)
	if err != nil {
		return CardEnrollment{}, err
	}
	return s.EnrollInvitation(context.Background(), device, hash, at)
}

func TestBentukTokenUndangan(t *testing.T) {
	valid := base64.RawURLEncoding.EncodeToString(make([]byte, 32))
	if hash, err := InvitationTokenHash(valid); err != nil || len(hash) != 32 {
		t.Fatalf("token valid: %d %v", len(hash), err)
	}
	for _, bad := range []string{"", valid[:42], valid + "A", strings.Replace(valid, "A", "+", 1), base64.URLEncoding.EncodeToString(make([]byte, 32))} {
		if _, err := InvitationTokenHash(bad); !errors.Is(err, ErrInvitationInvalid) {
			t.Errorf("%q: %v", bad, err)
		}
	}
}

func TestUndanganDipakaiSekali(t *testing.T) {
	s := freshStore(t)
	siteID, a := seed(t, s)
	b := newDevice(t, s)
	token := invite(t, s, Invitation{SiteID: siteID, ZonesBitmap: 1}, time.Now())
	if r, err := redeem(t, s, a, token, time.Now()); err != nil || r.Status != "PROVISIONING" || r.Resumed {
		t.Fatalf("pertama: %+v %v", r, err)
	}
	if _, err := redeem(t, s, b, token, time.Now()); !errors.Is(err, ErrInvitationInvalid) {
		t.Fatalf("perangkat lain dengan token terpakai: %v", err)
	}
}

func TestUndanganDilanjutkanPerangkatSama(t *testing.T) {
	// ADR-0034: token yang sama dari perangkat yang sama melanjutkan instance-nya.
	s := freshStore(t)
	siteID, a := seed(t, s)
	token := invite(t, s, Invitation{SiteID: siteID}, time.Now())
	first, _ := redeem(t, s, a, token, time.Now())
	if again, err := redeem(t, s, a, token, time.Now()); err != nil || !again.Resumed || again.ID != first.ID {
		t.Fatalf("ulang: %+v %v", again, err)
	}
}

func TestUndanganKedaluwarsaDitolak(t *testing.T) {
	s := freshStore(t)
	siteID, a := seed(t, s)
	t0 := time.Unix(1_794_000_000, 0)
	token := invite(t, s, Invitation{SiteID: siteID, TTL: 24 * time.Hour}, t0)
	if _, err := redeem(t, s, a, token, t0.Add(25*time.Hour)); !errors.Is(err, ErrInvitationInvalid) {
		t.Fatalf("kedaluwarsa: %v", err)
	}
	if _, _, err := s.CreateInvitation(context.Background(), Invitation{SiteID: siteID, TTL: 31 * 24 * time.Hour}, "staf-01", t0); err == nil {
		t.Fatal("masa berlaku > 30 hari seharusnya ditolak")
	}
}

func TestUndanganBersamaanSekaliPakai(t *testing.T) {
	// Review Focus 1: dua perangkat memakai undangan yang sama serentak; tepat satu berhasil. Diulang
	// untuk 20 undangan dengan penghalang start agar kedua transaksi benar-benar bertumpuk.
	s := freshStore(t)
	ctx := context.Background()
	siteID, _ := seed(t, s)
	for round := range 20 {
		token := invite(t, s, Invitation{SiteID: siteID}, time.Now())
		var wg sync.WaitGroup
		var mu sync.Mutex
		ok, invalid := 0, 0
		start := make(chan struct{})
		for _, device := range []string{newDevice(t, s), newDevice(t, s)} {
			wg.Add(1)
			go func() {
				defer wg.Done()
				<-start
				_, err := redeem(t, s, device, token, time.Now())
				mu.Lock()
				defer mu.Unlock()
				switch {
				case err == nil:
					ok++
				case errors.Is(err, ErrInvitationInvalid):
					invalid++
				default:
					t.Error(err)
				}
			}()
		}
		close(start)
		wg.Wait()
		if ok != 1 || invalid != 1 {
			t.Fatalf("putaran %d: berhasil %d, ditolak %d (ingin 1 dan 1)", round, ok, invalid)
		}
	}
	var instances int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM card_instances WHERE invitation_id IS NOT NULL`).Scan(&instances); err != nil || instances != 20 {
		t.Fatalf("instance dari undangan = %d (%v), ingin 20", instances, err)
	}
}

func TestUndanganUntukKartuTerpegang(t *testing.T) {
	// Review Focus 5: undangan adalah niat pengelola, jadi tetap PROVISIONING walau kartu dipegang
	// perangkat lain; perangkat yang sudah memegang kartu itu mendapat duplikat.
	s := freshStore(t)
	ctx := context.Background()
	siteID, holder := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 4})
	invited := newDevice(t, s)
	held, err := s.EnrollCard(ctx, holder, siteID, cardHMAC("A"), time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err := s.SetCardInstanceStatus(ctx, held.ID, "ACTIVE"); err != nil {
		t.Fatal(err)
	}
	if r, err := redeem(t, s, invited, invite(t, s, Invitation{SiteID: siteID, CardHMAC: cardHMAC("A")}, time.Now()), time.Now()); err != nil || r.Status != "PROVISIONING" {
		t.Fatalf("perangkat diundang: %+v %v", r, err)
	}
	if _, err := redeem(t, s, holder, invite(t, s, Invitation{SiteID: siteID, CardHMAC: cardHMAC("A")}, time.Now()), time.Now()); !errors.Is(err, ErrDuplicateEnrollment) {
		t.Fatalf("pemegang kartu: %v", err)
	}
}

func TestUndanganKartuTidakTerdaftarDitolakSaatDibuat(t *testing.T) {
	s := freshStore(t)
	siteID, _ := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A")})
	if _, _, err := s.CreateInvitation(context.Background(), Invitation{SiteID: siteID, CardHMAC: cardHMAC("B"), TTL: time.Hour * 24}, "staf-01", time.Now()); !errors.Is(err, ErrNotRegistered) {
		t.Fatalf("err=%v", err)
	}
}

func TestZonaUndangan(t *testing.T) {
	// Review Focus 4: zona undangan tanpa kartu fail-closed; undangan berkartu memakai zona kartu.
	s := freshStore(t)
	ctx := context.Background()
	siteID, _ := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 4})
	if err := s.SetSitePolicy(ctx, siteID, []byte(`{"zones": ["Lobi", "Lift A", "Parkir"], "zones_bitmap": 7}`)); err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name string
		inv  Invitation
		want uint64
	}{
		{"zona-undangan", Invitation{SiteID: siteID, ZonesBitmap: 2}, 2},
		{"tanpa-zona", Invitation{SiteID: siteID}, 0},
		{"berkartu", Invitation{SiteID: siteID, CardHMAC: cardHMAC("A"), ZonesBitmap: 1}, 4},
	}
	for _, c := range cases {
		r, err := redeem(t, s, newDevice(t, s), invite(t, s, c.inv, time.Now()), time.Now())
		if err != nil {
			t.Fatal(err)
		}
		_, _, err = s.Idempotent(ctx, "zona-"+c.name, []byte("h"), func(ctx context.Context, tx *Tx) (int, []byte, error) {
			e, err := tx.EnrollmentForUpdate(ctx, r.ID)
			if err == nil && e.ZonesBitmap != c.want {
				t.Errorf("%s: bitmap %d, ingin %d", c.name, e.ZonesBitmap, c.want)
			}
			return 200, []byte("{}"), err
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}

func TestUndanganTanpaTokenMentah(t *testing.T) {
	// Review Focus 3: token mentah tidak tersimpan di tabel undangan maupun audit.
	s := freshStore(t)
	ctx := context.Background()
	siteID, a := seed(t, s)
	token := invite(t, s, Invitation{SiteID: siteID}, time.Now())
	if _, err := redeem(t, s, a, token, time.Now()); err != nil {
		t.Fatal(err)
	}
	raw, _ := base64.RawURLEncoding.DecodeString(token)
	rows, err := s.pool.Query(ctx, `SELECT row_to_json(i)::text FROM invitations i UNION ALL SELECT row_to_json(e)::text FROM audit_events e`)
	if err != nil {
		t.Fatal(err)
	}
	lines, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		t.Fatal(err)
	}
	for _, line := range lines {
		if strings.Contains(line, token) || strings.Contains(strings.ToLower(line), hex.EncodeToString(raw)) {
			t.Fatalf("token mentah tersimpan: %s", line)
		}
	}
}

func TestUndanganTerbengkalaiBisaDipakaiLagi(t *testing.T) {
	// ADR-0034: undangan yang instance-nya terbengkalai dibebaskan lagi sampai kedaluwarsa.
	s := freshStore(t)
	siteID, a := seed(t, s)
	b := newDevice(t, s)
	t0 := time.Unix(1_794_000_000, 0)
	token := invite(t, s, Invitation{SiteID: siteID}, t0)
	if _, err := redeem(t, s, a, token, t0); err != nil {
		t.Fatal(err)
	}
	if r, err := redeem(t, s, b, token, t0.Add(AbandonedEnrollmentTTL+time.Minute)); err != nil || r.Status != "PROVISIONING" {
		t.Fatalf("setelah terbengkalai: %+v %v", r, err)
	}
}

type auditEntry struct {
	Action, Actor string
	Data          map[string]any
}

// auditOf mengembalikan audit untuk satu subject, urut kejadian.
func auditOf(t *testing.T, s *Store, subject string) []auditEntry {
	t.Helper()
	rows, err := s.pool.Query(context.Background(), `SELECT action, actor, data::text FROM audit_events WHERE subject = $1 ORDER BY at, seq`, subject)
	if err != nil {
		t.Fatal(err)
	}
	entries, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (auditEntry, error) {
		var e auditEntry
		var data string
		if err := row.Scan(&e.Action, &e.Actor, &data); err != nil {
			return e, err
		}
		return e, json.Unmarshal([]byte(data), &e.Data)
	})
	if err != nil {
		t.Fatal(err)
	}
	return entries
}

func invitationIDOf(t *testing.T, s *Store, token string) string {
	t.Helper()
	hash, err := InvitationTokenHash(token)
	if err != nil {
		t.Fatal(err)
	}
	var id string
	if err := s.pool.QueryRow(context.Background(), `SELECT id::text FROM invitations WHERE token_hash = $1`, hash).Scan(&id); err != nil {
		t.Fatal(err)
	}
	return id
}

func instanceInvitation(t *testing.T, s *Store, instance string) string {
	t.Helper()
	var id *string
	if err := s.pool.QueryRow(context.Background(), `SELECT invitation_id::text FROM card_instances WHERE id = $1`, instance).Scan(&id); err != nil {
		t.Fatal(err)
	}
	if id == nil {
		return ""
	}
	return *id
}

func TestUndanganMenyetujuiInstanceMenunggu(t *testing.T) {
	// ADR-0035 (review akhir I1): undangan berkartu menyetujui instance PENDING_APPROVAL milik perangkat
	// itu untuk kartu yang sama; tidak ada instance baru, dan audit menunjuk undangannya.
	s := freshStore(t)
	ctx := context.Background()
	now := time.Now()
	siteID, holder := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 4})
	if _, err := s.EnrollCard(ctx, holder, siteID, cardHMAC("A"), now); err != nil {
		t.Fatal(err)
	}
	second := newDevice(t, s)
	pending, err := s.EnrollCard(ctx, second, siteID, cardHMAC("A"), now)
	if err != nil || pending.Status != "PENDING_APPROVAL" {
		t.Fatalf("perangkat kedua: %+v %v", pending, err)
	}
	token := invite(t, s, Invitation{SiteID: siteID, CardHMAC: cardHMAC("A")}, now)
	r, err := redeem(t, s, second, token, now.Add(time.Minute))
	if err != nil || r.ID != pending.ID || r.Status != "PROVISIONING" || !r.Resumed {
		t.Fatalf("undangan untuk instance menunggu: %+v %v", r, err)
	}
	invitationID := invitationIDOf(t, s, token)
	if got := instanceInvitation(t, s, pending.ID); got != invitationID {
		t.Fatalf("invitation_id = %q, ingin %q", got, invitationID)
	}
	var instances int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM card_instances WHERE device_id = $1`, second).Scan(&instances); err != nil || instances != 1 {
		t.Fatalf("instance perangkat kedua = %d (%v), ingin 1", instances, err)
	}
	events := auditOf(t, s, "card_instance:"+pending.ID)
	last := events[len(events)-1]
	if last.Action != "enrollment.approved" || last.Actor != "device:"+second ||
		last.Data["method"] != "invitation" || last.Data["invitation"] != invitationID || last.Data["from"] != "PENDING_APPROVAL" {
		t.Fatalf("audit = %+v", events)
	}
	if _, err := redeem(t, s, newDevice(t, s), token, now.Add(2*time.Minute)); !errors.Is(err, ErrInvitationInvalid) {
		t.Fatalf("undangan dipakai ulang perangkat lain: %v", err)
	}
}

func TestUndanganMelanjutkanInstanceKartuSendiri(t *testing.T) {
	// ADR-0035: instance PROVISIONING dari jalur kartu dilanjutkan dan ditautkan ke undangan (terpakai).
	s := freshStore(t)
	ctx := context.Background()
	now := time.Now()
	siteID, device := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 4})
	started, err := s.EnrollCard(ctx, device, siteID, cardHMAC("A"), now)
	if err != nil || started.Status != "PROVISIONING" {
		t.Fatalf("jalur kartu: %+v %v", started, err)
	}
	token := invite(t, s, Invitation{SiteID: siteID, CardHMAC: cardHMAC("A")}, now)
	r, err := redeem(t, s, device, token, now.Add(time.Minute))
	if err != nil || r.ID != started.ID || r.Status != "PROVISIONING" || !r.Resumed {
		t.Fatalf("undangan untuk instance PROVISIONING: %+v %v", r, err)
	}
	if got := instanceInvitation(t, s, started.ID); got != invitationIDOf(t, s, token) {
		t.Fatalf("invitation_id = %q", got)
	}
	events := auditOf(t, s, "card_instance:"+started.ID)
	if last := events[len(events)-1]; last.Action != "enrollment.approved" || last.Data["from"] != "PROVISIONING" {
		t.Fatalf("audit = %+v", events)
	}
	if _, err := redeem(t, s, newDevice(t, s), token, now.Add(2*time.Minute)); !errors.Is(err, ErrInvitationInvalid) {
		t.Fatalf("undangan dipakai ulang perangkat lain: %v", err)
	}
}

func TestUndanganLainTidakMenimpaInstance(t *testing.T) {
	// ADR-0035: instance yang sudah milik undangan lain dilanjutkan apa adanya; undangan baru tidak terpakai.
	s := freshStore(t)
	now := time.Now()
	siteID, device := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 4})
	first := invite(t, s, Invitation{SiteID: siteID, CardHMAC: cardHMAC("A")}, now)
	second := invite(t, s, Invitation{SiteID: siteID, CardHMAC: cardHMAC("A")}, now)
	r1, err := redeem(t, s, device, first, now)
	if err != nil || r1.Status != "PROVISIONING" {
		t.Fatalf("undangan pertama: %+v %v", r1, err)
	}
	r2, err := redeem(t, s, device, second, now.Add(time.Minute))
	if err != nil || r2.ID != r1.ID || r2.Status != "PROVISIONING" || !r2.Resumed {
		t.Fatalf("undangan kedua: %+v %v", r2, err)
	}
	if got := instanceInvitation(t, s, r1.ID); got != invitationIDOf(t, s, first) {
		t.Fatalf("invitation_id tertimpa: %q", got)
	}
	if r, err := redeem(t, s, newDevice(t, s), second, now.Add(2*time.Minute)); err != nil || r.Status != "PROVISIONING" {
		t.Fatalf("undangan kedua seharusnya belum terpakai: %+v %v", r, err)
	}
}

func TestUndanganKartuDihapusDitolak(t *testing.T) {
	// Review akhir I2: kartu REMOVED di registri dijawab seperti undangan tak berlaku, termasuk saat melanjutkan.
	s := freshStore(t)
	ctx := context.Background()
	now := time.Now()
	siteID, device := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 4})
	unused := invite(t, s, Invitation{SiteID: siteID, CardHMAC: cardHMAC("A")}, now)
	started := invite(t, s, Invitation{SiteID: siteID, CardHMAC: cardHMAC("A")}, now)
	if r, err := redeem(t, s, device, started, now); err != nil || r.Status != "PROVISIONING" {
		t.Fatalf("sebelum dihapus: %+v %v", r, err)
	}
	if _, err := s.pool.Exec(ctx, `UPDATE physical_cards SET status = 'REMOVED' WHERE site_id = $1`, siteID); err != nil {
		t.Fatal(err)
	}
	if _, err := redeem(t, s, newDevice(t, s), unused, now.Add(time.Minute)); !errors.Is(err, ErrInvitationInvalid) {
		t.Fatalf("undangan untuk kartu REMOVED: %v", err)
	}
	if _, err := redeem(t, s, device, started, now.Add(time.Minute)); !errors.Is(err, ErrInvitationInvalid) {
		t.Fatalf("melanjutkan undangan untuk kartu REMOVED: %v", err)
	}
}

func TestUndanganBatasDelapanKartu(t *testing.T) {
	// Review akhir I4 (CLAUDE.md aturan 8): perangkat penuh ditolak di jalur undangan, berkartu maupun
	// tidak, dan undangannya tetap bisa dipakai perangkat lain.
	s := freshStore(t)
	ctx := context.Background()
	now := time.Now()
	siteID, device := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 4})
	for i := 0; i < MaxActiveCardsPerDevice; i++ {
		if _, err := s.StartEnrollment(ctx, device, siteID, now); err != nil {
			t.Fatalf("kartu ke-%d: %v", i+1, err)
		}
	}
	for name, inv := range map[string]Invitation{
		"berkartu":    {SiteID: siteID, CardHMAC: cardHMAC("A")},
		"tanpa-kartu": {SiteID: siteID, ZonesBitmap: 4},
	} {
		token := invite(t, s, inv, now)
		if _, err := redeem(t, s, device, token, now); !errors.Is(err, ErrCardLimit) {
			t.Fatalf("%s: perangkat penuh: %v", name, err)
		}
		if r, err := redeem(t, s, newDevice(t, s), token, now); err != nil || r.Status != "PROVISIONING" {
			t.Fatalf("%s: undangan terpakai oleh percobaan yang ditolak: %+v %v", name, r, err)
		}
	}
}

func TestAuditEnrolmentUndanganMenautkanUndangan(t *testing.T) {
	// ADR-0035 (requirement 2) / review akhir M8: audit enrolment lewat undangan memuat id internal
	// undangannya, agar rantai audit menghubungkan invitation.created dengan instance yang dibuatnya.
	s := freshStore(t)
	now := time.Now()
	siteID, device := registrySite(t, s, PhysicalCard{CardHMAC: cardHMAC("A"), ZonesBitmap: 4})
	token := invite(t, s, Invitation{SiteID: siteID, ZonesBitmap: 4}, now)
	r, err := redeem(t, s, device, token, now)
	if err != nil {
		t.Fatal(err)
	}
	events := auditOf(t, s, "card_instance:"+r.ID)
	if len(events) != 1 || events[0].Action != "enrollment.started" || events[0].Data["method"] != "invitation" || events[0].Data["invitation"] != invitationIDOf(t, s, token) {
		t.Fatalf("audit = %+v", events)
	}
}
