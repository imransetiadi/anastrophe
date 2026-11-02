package store

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"testing"
	"time"
)

func TestHashRahasiaTidakDipasangPadaInstanceAktif(t *testing.T) {
	// Review akhir provisioning M1: enrolment ulang yang menunggu kunci tidak boleh memasang hash pada
	// instance yang sudah ACTIVE.
	s := freshStore(t)
	ctx := context.Background()
	_, _, id, _ := activeCard(t, s, "ble")
	sum := sha256.Sum256([]byte("rahasia"))
	err := s.InTx(ctx, func(tx *Tx) error { return tx.SetProvisioningKeyHash(ctx, id, sum[:]) })
	if !errors.Is(err, ErrDuplicateEnrollment) {
		t.Fatalf("hash pada instance ACTIVE: %v", err)
	}
	var stored []byte
	if err := s.pool.QueryRow(ctx, `SELECT provisioning_key_hash FROM card_instances WHERE id = $1`, id).Scan(&stored); err != nil || stored != nil {
		t.Fatalf("hash tersimpan %x (%v)", stored, err)
	}
}

func TestHashRahasiaBukan32ByteGalatSendiri(t *testing.T) {
	// Review akhir provisioning M5: galat hash provisioning tidak menyebut token status.
	s := freshStore(t)
	ctx := context.Background()
	_, _, id, _ := activeCard(t, s)
	err := s.InTx(ctx, func(tx *Tx) error { return tx.SetProvisioningKeyHash(ctx, id, make([]byte, 31)) })
	if !errors.Is(err, ErrInvalidProvisioningHash) || errors.Is(err, ErrInvalidTokenHash) {
		t.Fatalf("galat = %v", err)
	}
}

// abandonConcurrently mengunci instance dan menandainya ABANDONED dalam transaksi yang belum di-commit,
// seperti sapuan per jam yang sedang berjalan; commit() menyelesaikannya.
func abandonConcurrently(t *testing.T, s *Store, id string) (commit func()) {
	t.Helper()
	ctx := context.Background()
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(ctx, `UPDATE card_instances SET status = 'ABANDONED' WHERE id = $1`, id); err != nil {
		t.Fatal(err)
	}
	return func() {
		if err := tx.Commit(ctx); err != nil {
			t.Fatal(err)
		}
	}
}

func TestResumeKartuTidakMenghidupkanInstanceTerbengkalai(t *testing.T) {
	// Review akhir undangan M4 (jalur kartu): bila sapuan menandai instance ABANDONED saat enrolment
	// melanjutkannya, enrolment tidak boleh mengembalikan instance itu sebagai PROVISIONING.
	s := freshStore(t)
	ctx := context.Background()
	siteID, _ := registrySite(t, s)
	device, old, _ := activeCardOn(t, s, siteID, "A")
	commit := abandonConcurrently(t, s, old)
	done := make(chan CardEnrollment, 1)
	errs := make(chan error, 1)
	go func() {
		r, err := s.EnrollCard(ctx, device, siteID, cardHMAC("A"), time.Now())
		done <- r
		errs <- err
	}()
	time.Sleep(300 * time.Millisecond)
	commit()
	r, err := <-done, <-errs
	if err != nil || r.ID == old || r.Status != "PROVISIONING" {
		t.Fatalf("enrolment setelah instance terbengkalai: %+v %v (lama %s)", r, err, old)
	}
}

func TestResumeUndanganTidakMenghidupkanInstanceTerbengkalai(t *testing.T) {
	// Review akhir undangan M4 (jalur undangan): sama, untuk perangkat yang melanjutkan undangannya.
	s := freshStore(t)
	now := time.Now()
	siteID, device := registrySite(t, s)
	token := invite(t, s, Invitation{SiteID: siteID, ZonesBitmap: 1}, now)
	first, err := redeem(t, s, device, token, now)
	if err != nil {
		t.Fatal(err)
	}
	commit := abandonConcurrently(t, s, first.ID)
	done := make(chan CardEnrollment, 1)
	errs := make(chan error, 1)
	go func() {
		r, err := redeem(t, s, device, token, now)
		done <- r
		errs <- err
	}()
	time.Sleep(300 * time.Millisecond)
	commit()
	r, err := <-done, <-errs
	if err != nil || r.ID == first.ID || r.Status != "PROVISIONING" {
		t.Fatalf("undangan setelah instance terbengkalai: %+v %v (lama %s)", r, err, first.ID)
	}
}

func TestRevokeOperatorMenulisAuditKredensial(t *testing.T) {
	// Review akhir siklus hidup M8: pencabutan operator juga menulis credential.revoked per kredensial,
	// pemicu Site Sync yang sama dengan hapus kartu (SDD §8.4.3).
	s := freshStore(t)
	ctx := context.Background()
	_, _, id, creds := activeCard(t, s, "ble")
	if _, err := s.RevokeCardInstance(ctx, id, "hilang", "staf-01", time.Now()); err != nil {
		t.Fatal(err)
	}
	events := auditOf(t, s, "credential:"+hex.EncodeToString(creds[0]))
	if len(events) != 1 || events[0].Action != "credential.revoked" || events[0].Actor != "operator:staf-01" ||
		events[0].Data["channel"] != "ble" || events[0].Data["reason"] != "hilang" {
		t.Fatalf("audit kredensial = %+v", events)
	}
}

func TestDenylistMemakaiMasaBerlakuTerpanjang(t *testing.T) {
	// Review akhir siklus hidup M3: bila perpanjangan memendekkan masa berlaku, sertifikat lama yang lebih
	// panjang masih ada di tangan pemegang; denylist harus bertahan sampai sertifikat terpanjang itu habis.
	s := freshStore(t)
	ctx := context.Background()
	now := time.Now().Truncate(time.Second)
	_, _, id, creds := activeCard(t, s, "ble")
	var credentialID string
	var longest time.Time
	if err := s.pool.QueryRow(ctx, `SELECT id::text, not_after FROM credentials WHERE cred_id = $1`, creds[0]).Scan(&credentialID, &longest); err != nil {
		t.Fatal(err)
	}
	nonce := make([]byte, 32)
	nonce[0] = 7
	if _, err := s.CreateRenewalChallenge(ctx, creds[0], nonce, now.Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	shorter := now.Add(24 * time.Hour)
	if err := s.InTx(ctx, func(tx *Tx) error { return tx.CompleteRenewal(ctx, credentialID, nonce, []byte{2}, shorter, now) }); err != nil {
		t.Fatal(err)
	}
	if _, err := s.RevokeCardInstance(ctx, id, "hilang", "staf-01", now); err != nil {
		t.Fatal(err)
	}
	var expires time.Time
	if err := s.pool.QueryRow(ctx, `SELECT expires_at FROM denylist_entries WHERE cred_id = $1`, creds[0]).Scan(&expires); err != nil {
		t.Fatal(err)
	}
	if !expires.Equal(longest) {
		t.Fatalf("expires_at = %v, ingin %v (sertifikat terpanjang)", expires, longest)
	}
}

func TestPurgeDenylistKedaluwarsa(t *testing.T) {
	// Review akhir siklus hidup M3: baris yang sertifikatnya sudah habis dibuang agar denylist terbatas.
	s := freshStore(t)
	ctx := context.Background()
	now := time.Now()
	siteID, _ := registrySite(t, s)
	for i, expires := range []time.Time{now.Add(-time.Hour), now.Add(time.Hour)} {
		if _, err := s.pool.Exec(ctx, `INSERT INTO denylist_entries (site_id, cred_id, revoked_at, expires_at) VALUES ($1, $2, $3, $4)`, siteID, []byte{byte(i), 1, 2, 3}, now, expires); err != nil {
			t.Fatal(err)
		}
	}
	n, err := s.PurgeDenylist(ctx, now)
	if err != nil || n != 1 {
		t.Fatalf("purge = %d (%v), ingin 1", n, err)
	}
	var left int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM denylist_entries`).Scan(&left); err != nil || left != 1 {
		t.Fatalf("tersisa %d (%v), ingin 1", left, err)
	}
}

func TestDenylistMemakaiYangTerpanjangDariKeduaKolom(t *testing.T) {
	// Review akhir perbaikan minor 2: server lama (sebelum 0012) memperpanjang not_after tanpa menyentuh
	// max_not_after; denylist tetap harus bertahan sampai sertifikat yang masih hidup habis.
	s := freshStore(t)
	ctx := context.Background()
	_, _, id, creds := activeCard(t, s, "ble")
	var later time.Time
	if err := s.pool.QueryRow(ctx, `UPDATE credentials SET not_after = not_after + interval '20 days' WHERE cred_id = $1 RETURNING not_after`, creds[0]).Scan(&later); err != nil {
		t.Fatal(err)
	}
	if _, err := s.RevokeCardInstance(ctx, id, "hilang", "staf-01", time.Now()); err != nil {
		t.Fatal(err)
	}
	var expires time.Time
	if err := s.pool.QueryRow(ctx, `SELECT expires_at FROM denylist_entries WHERE cred_id = $1`, creds[0]).Scan(&expires); err != nil {
		t.Fatal(err)
	}
	if !expires.Equal(later) {
		t.Fatalf("expires_at = %v, ingin %v", expires, later)
	}
}
