package store

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"
)

// activeCard membuat gedung beregistri dan card instance ACTIVE untuk kartu "A" dengan satu kredensial
// per kanal (kanal harus berbeda); tanpa kanal, instance tetap PROVISIONING.
func activeCard(t *testing.T, s *Store, channels ...string) (siteID, deviceID, instanceID string, credIDs [][]byte) {
	t.Helper()
	siteID, _ = registrySite(t, s)
	deviceID, instanceID, credIDs = activeCardOn(t, s, siteID, "A", channels...)
	return siteID, deviceID, instanceID, credIDs
}

// activeCardOn mendaftarkan kartu label di gedung yang ada, lalu perangkat baru mengenrolnya dan
// menerima satu kredensial per kanal.
func activeCardOn(t *testing.T, s *Store, siteID, label string, channels ...string) (deviceID, instanceID string, credIDs [][]byte) {
	t.Helper()
	ctx := context.Background()
	if _, _, err := s.UpsertPhysicalCards(ctx, siteID, "uji", []PhysicalCard{{CardHMAC: cardHMAC(label), ZonesBitmap: 1}}, 0, time.Now()); err != nil {
		t.Fatal(err)
	}
	deviceID = newDevice(t, s)
	r, err := s.EnrollCard(ctx, deviceID, siteID, cardHMAC(label), time.Now())
	if err != nil || r.Status != "PROVISIONING" {
		t.Fatalf("enrolment %s: %+v %v", label, r, err)
	}
	pub := append([]byte{0x04}, make([]byte, 64)...)
	for _, ch := range channels {
		credID := make([]byte, 16)
		if _, err := rand.Read(credID); err != nil {
			t.Fatal(err)
		}
		_, _, err := s.Idempotent(ctx, "aktif-"+ch+"-"+r.ID, []byte("h"), func(ctx context.Context, tx *Tx) (int, []byte, error) {
			return 200, []byte("{}"), tx.SaveCredential(ctx, Credential{CardInstanceID: r.ID, Channel: ch, CredID: credID, PubKey: pub, Cert: []byte{1}, NotAfter: time.Now().Add(7 * 24 * time.Hour).Truncate(time.Second)})
		})
		if err != nil {
			t.Fatal(err)
		}
		credIDs = append(credIDs, credID)
	}
	return deviceID, r.ID, credIDs
}

// statusesOf mengembalikan status instance dan status kredensialnya (terurut).
func statusesOf(t *testing.T, s *Store, instance string) (string, []string) {
	t.Helper()
	ctx := context.Background()
	var status string
	if err := s.pool.QueryRow(ctx, `SELECT status FROM card_instances WHERE id = $1`, instance).Scan(&status); err != nil {
		t.Fatal(err)
	}
	var creds []string
	if err := s.pool.QueryRow(ctx, `SELECT coalesce(array_agg(status ORDER BY status), '{}') FROM credentials WHERE card_instance_id = $1`, instance).Scan(&creds); err != nil {
		t.Fatal(err)
	}
	return status, creds
}

func TestTangguhkanDanPulihkan(t *testing.T) {
	// FR-51: kredensial mengikuti status instance; setiap transisi tercatat di audit.
	s := freshStore(t)
	ctx := context.Background()
	_, _, id, _ := activeCard(t, s, "ble", "nfcHCE")
	if err := s.SuspendCard(ctx, id, "staf-01", time.Now()); err != nil {
		t.Fatal(err)
	}
	if inst, creds := statusesOf(t, s, id); inst != "SUSPENDED" || strings.Join(creds, ",") != "SUSPENDED,SUSPENDED" {
		t.Fatalf("setelah suspend: %s %v", inst, creds)
	}
	if err := s.ResumeCard(ctx, id, "staf-01", time.Now()); err != nil {
		t.Fatal(err)
	}
	if inst, creds := statusesOf(t, s, id); inst != "ACTIVE" || strings.Join(creds, ",") != "ACTIVE,ACTIVE" {
		t.Fatalf("setelah resume: %s %v", inst, creds)
	}
	events := auditOf(t, s, "card_instance:"+id)
	got := []string{events[len(events)-2].Action, events[len(events)-1].Action}
	if !slices.Equal(got, []string{"card.suspended", "card.resumed"}) || events[len(events)-1].Actor != "operator:staf-01" {
		t.Fatalf("audit = %+v", events)
	}
}

func TestTransisiIlegalDitolak(t *testing.T) {
	// Review Focus 3: transisi yang tidak diizinkan tidak mengubah apa pun dan tidak diaudit.
	s := freshStore(t)
	ctx := context.Background()
	now := time.Now()
	siteID, _, id, _ := activeCard(t, s, "ble")
	pending, err := s.EnrollCard(ctx, newDevice(t, s), siteID, cardHMAC("A"), now)
	if err != nil || pending.Status != "PENDING_APPROVAL" {
		t.Fatalf("perangkat kedua: %+v %v", pending, err)
	}
	auditCount := func(id string) int { return len(auditOf(t, s, "card_instance:"+id)) }
	beforeActive, beforePending := auditCount(id), auditCount(pending.ID)
	if err := s.ResumeCard(ctx, id, "staf-01", now); !errors.Is(err, ErrInvalidTransition) {
		t.Errorf("resume dari ACTIVE: %v", err)
	}
	if err := s.SuspendCard(ctx, pending.ID, "staf-01", now); !errors.Is(err, ErrInvalidTransition) {
		t.Errorf("suspend dari PENDING_APPROVAL: %v", err)
	}
	if _, err := s.RevokeCardInstance(ctx, pending.ID, "operator", "staf-01", now); !errors.Is(err, ErrInvalidTransition) {
		t.Errorf("revoke dari PENDING_APPROVAL: %v", err)
	}
	if _, err := s.RevokeCardInstance(ctx, id, "Bukan Kode", "staf-01", now); !errors.Is(err, ErrInvalidReason) {
		t.Errorf("alasan teks bebas: %v", err)
	}
	if err := s.SuspendCard(ctx, id, "", now); !errors.Is(err, ErrInvalidOperator) {
		t.Errorf("tanpa operator: %v", err)
	}
	if err := s.SuspendCard(ctx, newUUID(), "staf-01", now); !errors.Is(err, ErrNotFound) {
		t.Errorf("instance tak dikenal: %v", err)
	}
	if inst, creds := statusesOf(t, s, id); inst != "ACTIVE" || strings.Join(creds, ",") != "ACTIVE" {
		t.Fatalf("status berubah: %s %v", inst, creds)
	}
	if auditCount(id) != beforeActive || auditCount(pending.ID) != beforePending {
		t.Fatal("transisi yang ditolak tercatat di audit")
	}
	if _, err := s.RevokeCardInstance(ctx, id, "hilang", "staf-01", now); err != nil {
		t.Fatal(err)
	}
	afterRevoke := auditCount(id)
	for name, err := range map[string]error{
		"suspend": s.SuspendCard(ctx, id, "staf-01", now),
		"resume":  s.ResumeCard(ctx, id, "staf-01", now),
		"revoke":  func() error { _, err := s.RevokeCardInstance(ctx, id, "operator", "staf-01", now); return err }(),
	} {
		if !errors.Is(err, ErrInvalidTransition) {
			t.Errorf("%s dari REVOKED: %v", name, err)
		}
	}
	if auditCount(id) != afterRevoke {
		t.Fatal("transisi dari REVOKED tercatat di audit")
	}
}

func TestCabutKartuOperator(t *testing.T) {
	// FR-51, SDD §8.4.3: kredensial dicabut dan masuk denylist sampai sertifikatnya kedaluwarsa;
	// slot batas 8 kartu terbebas.
	s := freshStore(t)
	ctx := context.Background()
	now := time.Now().Truncate(time.Second)
	siteID, deviceID, id, creds := activeCard(t, s, "ble")
	n, err := s.RevokeCardInstance(ctx, id, "hilang", "staf-01", now)
	if err != nil || n != 1 {
		t.Fatalf("revoke: %d %v", n, err)
	}
	if inst, statuses := statusesOf(t, s, id); inst != "REVOKED" || strings.Join(statuses, ",") != "REVOKED" {
		t.Fatalf("status: %s %v", inst, statuses)
	}
	var reason string
	var notAfter time.Time
	if err := s.pool.QueryRow(ctx, `SELECT revoke_reason, not_after FROM credentials WHERE card_instance_id = $1 AND revoked_at IS NOT NULL`, id).Scan(&reason, &notAfter); err != nil || reason != "hilang" {
		t.Fatalf("revoke_reason = %q (%v)", reason, err)
	}
	var site string
	var cred []byte
	var expires time.Time
	if err := s.pool.QueryRow(ctx, `SELECT site_id::text, cred_id, expires_at FROM denylist_entries`).Scan(&site, &cred, &expires); err != nil {
		t.Fatalf("denylist: %v", err)
	}
	if site != siteID || !bytes.Equal(cred, creds[0]) || !expires.Equal(notAfter) {
		t.Fatalf("denylist = %s %x %v, ingin %s %x %v", site, cred, expires, siteID, creds[0], notAfter)
	}
	events := auditOf(t, s, "card_instance:"+id)
	last := events[len(events)-1]
	if last.Action != "card.revoked" || last.Data["reason"] != "hilang" || last.Data["credentials"] != float64(1) {
		t.Fatalf("audit = %+v", last)
	}
	var active int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM card_instances WHERE device_id = $1 AND status = ANY($2)`, deviceID, activeStatuses).Scan(&active); err != nil || active != 0 {
		t.Fatalf("slot aktif = %d (%v), ingin 0", active, err)
	}
	_, provisioning, _ := activeCardOn(t, s, siteID, "B")
	if n, err := s.RevokeCardInstance(ctx, provisioning, "operator", "staf-01", now); err != nil || n != 0 {
		t.Fatalf("revoke PROVISIONING: %d %v", n, err)
	}
	if inst, _ := statusesOf(t, s, provisioning); inst != "REVOKED" {
		t.Fatalf("PROVISIONING menjadi %s", inst)
	}
}

func TestHapusKartuMasukDenylist(t *testing.T) {
	// Spesifikasi: hapus kartu oleh pengguna (ADR-0026) memakai helper pencabutan yang sama.
	s := freshStore(t)
	ctx := context.Background()
	now := time.Now()
	_, _, id, creds := activeCard(t, s, "ble")
	nonce := bytes.Repeat([]byte{9}, 32)
	if _, err := s.CreateRenewalChallenge(ctx, creds[0], nonce, now.Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	_, _, err := s.Idempotent(ctx, "hapus-"+id, []byte("h"), func(ctx context.Context, tx *Tx) (int, []byte, error) {
		_, err := tx.RevokeCard(ctx, id, nonce, "user_deleted", now)
		return 200, []byte("{}"), err
	})
	if err != nil {
		t.Fatal(err)
	}
	var n int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM denylist_entries WHERE cred_id = $1`, creds[0]).Scan(&n); err != nil || n != 1 {
		t.Fatalf("denylist hapus kartu = %d (%v)", n, err)
	}
}

func TestDaftarCardInstance(t *testing.T) {
	// FR-50 (sebagian): operator melihat id, status, kanal, dan asal tanpa identitas kartu.
	s := freshStore(t)
	ctx := context.Background()
	now := time.Now()
	siteID, _, active, _ := activeCard(t, s, "ble")
	if _, err := s.EnrollCard(ctx, newDevice(t, s), siteID, cardHMAC("A"), now); err != nil {
		t.Fatal(err)
	}
	if _, err := redeem(t, s, newDevice(t, s), invite(t, s, Invitation{SiteID: siteID, ZonesBitmap: 1}, now), now); err != nil {
		t.Fatal(err)
	}
	if _, err := s.StartEnrollment(ctx, newDevice(t, s), siteID, now); err != nil {
		t.Fatal(err)
	}
	all, err := s.ListCardInstances(ctx, siteID, "")
	if err != nil || len(all) != 4 {
		t.Fatalf("daftar: %+v %v", all, err)
	}
	var origins []string
	for _, c := range all {
		origins = append(origins, c.Origin)
	}
	slices.Sort(origins)
	if !slices.Equal(origins, []string{"-", "kartu", "kartu", "undangan"}) {
		t.Fatalf("asal = %v", origins)
	}
	only, err := s.ListCardInstances(ctx, siteID, "ACTIVE")
	if err != nil || len(only) != 1 || only[0].ID != active || !slices.Equal(only[0].Channels, []string{"ble"}) {
		t.Fatalf("filter ACTIVE: %+v %v", only, err)
	}
	if _, err := s.ListCardInstances(ctx, siteID, "BOGUS"); !errors.Is(err, ErrInvalidStatus) {
		t.Fatalf("filter status tak dikenal: %v", err)
	}
}

func TestHashTokenStatusSaja(t *testing.T) {
	// Review Focus 2 (ADR-0037): kolom hanya menerima hash 32 byte.
	s := freshStore(t)
	ctx := context.Background()
	_, _, id, _ := activeCard(t, s, "ble")
	token := bytes.Repeat([]byte{7}, 32)
	hash := sha256.Sum256(token)
	_, _, err := s.Idempotent(ctx, "token-"+id, []byte("h"), func(ctx context.Context, tx *Tx) (int, []byte, error) {
		if err := tx.SetStatusTokenHash(ctx, id, hash[:31]); !errors.Is(err, ErrInvalidTokenHash) {
			t.Errorf("hash 31 byte: %v", err)
		}
		return 200, []byte("{}"), tx.SetStatusTokenHash(ctx, id, hash[:])
	})
	if err != nil {
		t.Fatal(err)
	}
	var stored []byte
	if err := s.pool.QueryRow(ctx, `SELECT status_token_hash FROM card_instances WHERE id = $1`, id).Scan(&stored); err != nil || !bytes.Equal(stored, hash[:]) {
		t.Fatalf("tersimpan %x (%v), ingin hash", stored, err)
	}
}

func TestStatusKartuDenganToken(t *testing.T) {
	// ADR-0037: status dibaca dengan hash token; semua kegagalan ErrNotFound.
	s := freshStore(t)
	ctx := context.Background()
	now := time.Now()
	siteID, _, id, _ := activeCard(t, s, "ble")
	_, other, _ := activeCardOn(t, s, siteID, "B", "ble")
	set := func(id string, token byte) []byte {
		hash := sha256.Sum256(bytes.Repeat([]byte{token}, 32))
		_, _, err := s.Idempotent(ctx, "token-"+id+string(rune(token)), []byte("h"), func(ctx context.Context, tx *Tx) (int, []byte, error) {
			return 200, []byte("{}"), tx.SetStatusTokenHash(ctx, id, hash[:])
		})
		if err != nil {
			t.Fatal(err)
		}
		return hash[:]
	}
	first := set(id, 1)
	if status, err := s.CardStatusByToken(ctx, id, first); err != nil || status != "ACTIVE" {
		t.Fatalf("status: %q %v", status, err)
	}
	wrong := sha256.Sum256([]byte("salah"))
	for name, call := range map[string]func() error{
		"token salah":    func() error { _, err := s.CardStatusByToken(ctx, id, wrong[:]); return err },
		"tanpa hash":     func() error { _, err := s.CardStatusByToken(ctx, other, first); return err },
		"tak dikenal":    func() error { _, err := s.CardStatusByToken(ctx, newUUID(), first); return err },
		"bukan uuid":     func() error { _, err := s.CardStatusByToken(ctx, "bukan-uuid", first); return err },
		"hash bukan 32B": func() error { _, err := s.CardStatusByToken(ctx, id, first[:16]); return err },
	} {
		if err := call(); !errors.Is(err, ErrNotFound) {
			t.Errorf("%s: %v", name, err)
		}
	}
	second := set(id, 2)
	if _, err := s.CardStatusByToken(ctx, id, first); !errors.Is(err, ErrNotFound) {
		t.Fatalf("hash lama masih berlaku: %v", err)
	}
	if err := s.SuspendCard(ctx, id, "staf-01", now); err != nil {
		t.Fatal(err)
	}
	if status, err := s.CardStatusByToken(ctx, id, second); err != nil || status != "SUSPENDED" {
		t.Fatalf("setelah suspend: %q %v", status, err)
	}
	if _, err := s.RevokeCardInstance(ctx, id, "operator", "staf-01", now); err != nil {
		t.Fatal(err)
	}
	if status, err := s.CardStatusByToken(ctx, id, second); err != nil || status != "REVOKED" {
		t.Fatalf("setelah revoke: %q %v", status, err)
	}
}

func filteredIDs(t *testing.T, s *Store, site string, f CardInstanceFilter) []string {
	t.Helper()
	list, err := s.ListCardInstancesFiltered(context.Background(), site, f)
	if err != nil {
		t.Fatal(err)
	}
	ids := []string{}
	for _, c := range list {
		ids = append(ids, c.ID)
	}
	return ids
}

func TestFilterDaftarKanalDanAwalan(t *testing.T) {
	// FR-50 (ADR-0050): filter kanal dan awalan id digabung AND dengan status.
	s := freshStore(t)
	site, _ := registrySite(t, s)
	_, bleID, _ := activeCardOn(t, s, site, "A", "ble")
	_, hceID, _ := activeCardOn(t, s, site, "B", "nfcHCE")
	for _, c := range []struct {
		name string
		f    CardInstanceFilter
		want []string
	}{
		{"kanal ble", CardInstanceFilter{Channel: "ble"}, []string{bleID}},
		{"kanal nfcHCE", CardInstanceFilter{Channel: "nfcHCE"}, []string{hceID}},
		{"awalan huruf besar", CardInstanceFilter{IDPrefix: strings.ToUpper(hceID[:8])}, []string{hceID}},
		{"kanal dan awalan lain", CardInstanceFilter{Channel: "ble", IDPrefix: hceID[:8]}, []string{}},
		{"status dan kanal", CardInstanceFilter{Status: "ACTIVE", Channel: "nfcHCE"}, []string{hceID}},
		{"id lengkap", CardInstanceFilter{IDPrefix: bleID}, []string{bleID}},
	} {
		if got := filteredIDs(t, s, site, c.f); !slices.Equal(got, c.want) {
			t.Fatalf("%s: %v, ingin %v", c.name, got, c.want)
		}
	}
}

func TestFilterDaftarMenolakPolaLike(t *testing.T) {
	// Review Focus 1: masukan tidak pernah menjadi pola LIKE.
	s := freshStore(t)
	site, _ := registrySite(t, s)
	ctx := context.Background()
	for _, bad := range []CardInstanceFilter{
		{IDPrefix: "%"}, {IDPrefix: "_"}, {IDPrefix: "a%"}, {IDPrefix: "zz"}, {IDPrefix: strings.Repeat("a", 37)}, {IDPrefix: "a b"},
		{Channel: "wallet"}, {Channel: "BLE "},
	} {
		if _, err := s.ListCardInstancesFiltered(ctx, site, bad); !errors.Is(err, ErrInvalidFilter) {
			t.Fatalf("%+v: %v, ingin ErrInvalidFilter", bad, err)
		}
	}
}

func TestFilterKanalAbaikanKredensialDicabut(t *testing.T) {
	// Review Focus 3: kanal mengikuti kredensial ACTIVE/SUSPENDED, bukan yang dicabut.
	s := freshStore(t)
	site, _ := registrySite(t, s)
	_, id, _ := activeCardOn(t, s, site, "A", "ble")
	if _, err := s.RevokeCardInstance(context.Background(), id, "hilang", "staf-01", time.Now()); err != nil {
		t.Fatal(err)
	}
	if got := filteredIDs(t, s, site, CardInstanceFilter{Channel: "ble"}); len(got) != 0 {
		t.Fatalf("kartu dicabut masih muncul untuk kanal ble: %v", got)
	}
	if got := filteredIDs(t, s, site, CardInstanceFilter{IDPrefix: id[:8]}); !slices.Equal(got, []string{id}) {
		t.Fatalf("awalan: %v", got)
	}
}

func TestFilterDaftarStatusSuspendedDanAND(t *testing.T) {
	// Review akhir #1 dan #2 (ADR-0050): kredensial SUSPENDED ikut kanal, dan --status benar-benar digabung
	// AND dengan --channel dan --id.
	s := freshStore(t)
	site, _ := registrySite(t, s)
	_, bleID, _ := activeCardOn(t, s, site, "A", "ble")
	_, hceID, _ := activeCardOn(t, s, site, "B", "nfcHCE")
	if err := s.SuspendCard(context.Background(), bleID, "staf-01", time.Now()); err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct {
		name string
		f    CardInstanceFilter
		want []string
	}{
		{"SUSPENDED dihitung", CardInstanceFilter{Channel: "ble"}, []string{bleID}},
		{"status+kanal", CardInstanceFilter{Status: "ACTIVE", Channel: "ble"}, []string{}},
		{"status+awalan", CardInstanceFilter{Status: "SUSPENDED", IDPrefix: hceID[:8]}, []string{}},
		{"ketiganya", CardInstanceFilter{Status: "SUSPENDED", Channel: "ble", IDPrefix: bleID[:13]}, []string{bleID}},
	} {
		if got := filteredIDs(t, s, site, c.f); !slices.Equal(got, c.want) {
			t.Fatalf("%s: %v, ingin %v", c.name, got, c.want)
		}
	}
}
