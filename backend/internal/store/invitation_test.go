package store

import (
	"context"
	"encoding/base64"
	"encoding/hex"
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
