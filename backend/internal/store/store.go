// Package store menyimpan data backend di PostgreSQL 16 (SDD §8.1).
package store

import (
	"bytes"
	"context"
	"crypto/rand"
	"embed"
	"encoding/hex"
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed migrations/*.sql
var migrations embed.FS

// ErrCardLimit: perangkat sudah memegang 8 card instance aktif (FR-15).
var ErrCardLimit = errors.New("store: batas 8 kartu per perangkat")

// MaxActiveCardsPerDevice ditegakkan juga di app (CardLimit, ANCore).
const MaxActiveCardsPerDevice = 8

// activeStatuses mengikuti invarian SDD §8.1.
var activeStatuses = []string{"PENDING_APPROVAL", "PROVISIONING", "ACTIVE", "SUSPENDED"}

type Store struct{ pool *pgxpool.Pool }

func Open(ctx context.Context, dsn string) (*Store, error) {
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	return &Store{pool: pool}, nil
}

func (s *Store) Close() { s.pool.Close() }

// migrationLockKey adalah kunci advisory sesi untuk menyerialkan migrasi antar-replika.
const migrationLockKey = 0x414E_5354_4D49_47 // "ANSTMIG"

// Migrate menjalankan migrasi yang belum diterapkan, masing-masing dalam satu transaksi.
// Replika yang start bersamaan diserialkan dengan advisory lock; di database read-only
// (hot standby ADR-0014) migrasi dilewati karena primer yang memigrasi.
func (s *Store) Migrate(ctx context.Context) error {
	var readOnly bool
	if err := s.pool.QueryRow(ctx, `SELECT pg_is_in_recovery() OR current_setting('transaction_read_only') = 'on'`).Scan(&readOnly); err != nil {
		return err
	}
	if readOnly {
		return nil
	}
	conn, err := s.pool.Acquire(ctx)
	if err != nil {
		return err
	}
	defer conn.Release()
	if _, err := conn.Exec(ctx, `SELECT pg_advisory_lock($1)`, int64(migrationLockKey)); err != nil {
		return err
	}
	defer conn.Exec(context.Background(), `SELECT pg_advisory_unlock($1)`, int64(migrationLockKey))
	if _, err := conn.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`); err != nil {
		return err
	}
	entries, err := migrations.ReadDir("migrations")
	if err != nil {
		return err
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, e.Name())
	}
	sort.Strings(names)
	for _, name := range names {
		sql, err := migrations.ReadFile("migrations/" + name)
		if err != nil {
			return err
		}
		err = pgx.BeginFunc(ctx, conn, func(tx pgx.Tx) error {
			tag, err := tx.Exec(ctx, `INSERT INTO schema_migrations (name) VALUES ($1) ON CONFLICT DO NOTHING`, name)
			if err != nil || tag.RowsAffected() == 0 {
				return err // sudah diterapkan
			}
			_, err = tx.Exec(ctx, string(sql))
			return err
		})
		if err != nil {
			return fmt.Errorf("migrasi %s: %w", name, err)
		}
	}
	return nil
}

func (s *Store) CreateOrganization(ctx context.Context, name, region string) (string, error) {
	id := newUUID()
	_, err := s.pool.Exec(ctx, `INSERT INTO organizations (id, name, region) VALUES ($1, $2, $3)`, id, name, region)
	return id, err
}

func (s *Store) CreateSite(ctx context.Context, orgID, name, country, timezone string, siteCode []byte) (string, error) {
	id := newUUID()
	_, err := s.pool.Exec(ctx, `INSERT INTO sites (id, org_id, name, country, timezone, site_code) VALUES ($1, $2, $3, $4, $5, $6)`, id, orgID, name, country, timezone, siteCode)
	return id, err
}

func (s *Store) CreateDevice(ctx context.Context) (string, error) {
	id := newUUID()
	_, err := s.pool.Exec(ctx, `INSERT INTO devices (id) VALUES ($1)`, id)
	return id, err
}

// AddCardInstance menambah kartu dengan mengunci baris perangkat lebih dulu, sehingga dua
// permintaan paralel tidak bisa sama-sama melewati batas 8 (TC-ENR-12).
// StartEnrollment membuat card instance dan mencatat enrollment.started di transaksi yang sama.
func (s *Store) StartEnrollment(ctx context.Context, deviceID, siteID string, at time.Time) (string, error) {
	var id string
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var err error
		id, err = (&Tx{tx: tx}).StartEnrollment(ctx, deviceID, siteID, at)
		return err
	})
	if err != nil {
		return "", err
	}
	return id, nil
}

// StartEnrollment di dalam transaksi idempotency.
func (t *Tx) StartEnrollment(ctx context.Context, deviceID, siteID string, at time.Time) (string, error) {
	id, device, site, err := addCardInstance(ctx, t.tx, deviceID, siteID)
	if err != nil {
		return "", err
	}
	// ID kanonik dari database, bukan dari klien (review audit C1).
	err = t.AppendAudit(ctx, AuditEvent{
		SiteID: site, Actor: "device:" + device, Action: "enrollment.started", Subject: "card_instance:" + id, At: at,
	})
	if err != nil {
		return "", err
	}
	return id, nil
}

// addCardInstance mengembalikan id card instance serta device/site dalam bentuk kanonik.
func addCardInstance(ctx context.Context, tx pgx.Tx, deviceID, siteID string) (id, device, site string, err error) {
	id = newUUID()
	err = func() error {
		if !looksLikeUUID(deviceID) || !looksLikeUUID(siteID) {
			return ErrNotFound
		}
		_, active, err := lockDevice(ctx, tx, deviceID)
		if err != nil {
			return err
		}
		if active >= MaxActiveCardsPerDevice {
			return ErrCardLimit
		}
		return tx.QueryRow(ctx, `INSERT INTO card_instances (id, device_id, site_id, status) VALUES ($1, $2, $3, 'PROVISIONING') RETURNING device_id::text, site_id::text`,
			id, deviceID, siteID).Scan(&device, &site)
	}()
	if err != nil {
		return "", "", "", err
	}
	return id, device, site, nil
}

func (s *Store) ActiveCardCount(ctx context.Context, deviceID string) (int, error) {
	var n int
	err := s.pool.QueryRow(ctx, `SELECT count(*) FROM card_instances WHERE device_id = $1 AND status = ANY($2)`, deviceID, activeStatuses).Scan(&n)
	return n, err
}

func newUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = b[6]&0x0f | 0x40 // versi 4
	b[8] = b[8]&0x3f | 0x80 // varian RFC 4122
	h := hex.EncodeToString(b)
	return h[:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:]
}

// IdempotencyKeyCount dipakai test dan observabilitas.
func (s *Store) IdempotencyKeyCount(ctx context.Context) (int, error) {
	var n int
	err := s.pool.QueryRow(ctx, `SELECT count(*) FROM idempotency_keys`).Scan(&n)
	return n, err
}

// PurgeIdempotencyKeys menghapus baris yang dibuat sebelum batas waktu (TTL).
func (s *Store) PurgeIdempotencyKeys(ctx context.Context, before time.Time) (int64, error) {
	tag, err := s.pool.Exec(ctx, `DELETE FROM idempotency_keys WHERE created_at < $1`, before)
	return tag.RowsAffected(), err
}

// ErrNotFound: data yang diminta tidak ada.
var ErrNotFound = errors.New("store: tidak ditemukan")

// ErrIdempotencyConflict: Idempotency-Key dipakai ulang dengan permintaan berbeda.
var ErrIdempotencyConflict = errors.New("store: idempotency key dipakai untuk permintaan lain")

func (s *Store) AddReaderGroup(ctx context.Context, groupID []byte, siteID string, pubkey []byte) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO reader_groups (id, site_id, pubkey) VALUES ($1, $2, $3)`, groupID, siteID, pubkey)
	return err
}

// Enrollment adalah card instance yang sedang diprovisikan beserta data gedungnya.
type Enrollment struct {
	ID     string
	Status string
	// DeviceID pemilik card instance (aktor event audit).
	DeviceID string
	SiteID   string
	SiteName string
	SiteCode []byte
	// Zones dan ZonesBitmap berasal dari kartu terdaftar bila card instance tertaut (FR-52), selain itu
	// dari sites.policy. Tanpa bitmap, nilainya 0 (fail-closed: sertifikat tidak membuka zona mana pun).
	Zones       []string
	ZonesBitmap uint64
	// CertValidityDays dari sites.policy (ADR-0010: 1–30); 0 = pakai default.
	CertValidityDays int
}

// Credential yang diterbitkan untuk satu kanal.
type Credential struct {
	CardInstanceID string
	Channel        string
	CredID         []byte
	PubKey         []byte
	Cert           []byte
	NotAfter       time.Time
}

// ErrNotProvisionable: status card instance tidak mengizinkan penerbitan kredensial (SDD §8.2).
var ErrNotProvisionable = errors.New("store: card instance tidak dapat diprovisikan")

// Tx adalah transaksi yang memegang advisory lock idempotency. Semua kerja satu permintaan
// berjalan di koneksi ini, sehingga permintaan tidak pernah butuh koneksi kedua (review C1)
// dan hasilnya ter-commit atomik bersama baris idempotency (review I1).
type Tx struct{ tx pgx.Tx }

// EnrollmentForUpdate membaca card instance dan mengunci barisnya sampai transaksi selesai.
func (t *Tx) EnrollmentForUpdate(ctx context.Context, id string) (Enrollment, error) {
	if !looksLikeUUID(id) {
		return Enrollment{}, ErrNotFound
	}
	var e Enrollment
	var zones []string
	var bitmap, validity *string
	var cardBitmap, invitationBitmap *int64
	err := t.tx.QueryRow(ctx, `
		SELECT ci.id, ci.status, ci.device_id, s.id, s.name, s.site_code,
		       COALESCE(ARRAY(SELECT jsonb_array_elements_text(s.policy -> 'zones')), '{}'),
		       s.policy ->> 'zones_bitmap',
		       s.policy ->> 'cert_validity_days',
		       pc.zones_bitmap,
		       inv.zones_bitmap
		FROM card_instances ci JOIN sites s ON s.id = ci.site_id
		LEFT JOIN physical_cards pc ON pc.id = ci.physical_card_id
		LEFT JOIN invitations inv ON inv.id = ci.invitation_id
		WHERE ci.id = $1
		FOR UPDATE OF ci`, id).Scan(&e.ID, &e.Status, &e.DeviceID, &e.SiteID, &e.SiteName, &e.SiteCode, &zones, &bitmap, &validity, &cardBitmap, &invitationBitmap)
	if errors.Is(err, pgx.ErrNoRows) {
		return Enrollment{}, ErrNotFound
	}
	if err != nil {
		return Enrollment{}, err
	}
	e.applyZones(zones, bitmap, validity, cardBitmap, invitationBitmap)
	return e, nil
}

// applyZones mengisi zona dan masa berlaku untuk penerbitan maupun perpanjangan: kartu terdaftar
// menentukan zona bila card instance tertaut (FR-52), lalu undangan tanpa kartu, selain itu sites.policy. Satu helper untuk
// EnrollmentForUpdate dan CredentialForRenewal agar keduanya tidak menyimpang (review registri C1).
func (e *Enrollment) applyZones(zones []string, policyBitmap, validity *string, cardBitmap, invitationBitmap *int64) {
	e.applyPolicy(zones, policyBitmap, validity)
	switch {
	case cardBitmap != nil:
		e.applyCardZones(zones, uint64(*cardBitmap))
	case invitationBitmap != nil:
		e.applyCardZones(zones, uint64(*invitationBitmap)) // undangan tanpa kartu (ADR-0033)
	}
}

// applyPolicy mengisi zona dan masa berlaku dari sites.policy (fail-closed: tanpa bitmap = 0).
func (e *Enrollment) applyPolicy(zones []string, bitmap, validity *string) {
	e.Zones = append([]string{}, zones...)
	if bitmap != nil {
		// Dibaca sebagai teks: nilai ≥ 2^63 (bit 63) tidak muat di bigint.
		if v, err := strconv.ParseUint(*bitmap, 10, 64); err == nil {
			e.ZonesBitmap = v
		}
	}
	if validity != nil {
		if days, err := strconv.Atoi(*validity); err == nil && days >= 1 && days <= 30 {
			e.CertValidityDays = days
		}
	}
}

// ErrNotRenewable: kredensial atau card instance tidak ACTIVE (SDD §8.4.2).
var ErrNotRenewable = errors.New("store: kredensial tidak dapat diperpanjang")

// RenewableCredential adalah kredensial beserta kebijakan gedung saat ini untuk perpanjangan.
type RenewableCredential struct {
	ID         string
	Channel    string
	Status     string
	CardStatus string
	CredID     []byte
	PubKey     []byte
	// Site memuat gedung dan kebijakannya (Zones, ZonesBitmap, CertValidityDays).
	Site Enrollment
}

// Renewable: kredensial dan card instance-nya sama-sama ACTIVE.
func (c RenewableCredential) Renewable() bool {
	return c.Status == "ACTIVE" && c.CardStatus == "ACTIVE"
}

// ErrGone: kartu atau kredensial sudah dicabut/dihapus (ADR-0027: app boleh menghapus lokal).
var ErrGone = errors.New("store: kartu sudah dicabut")

// gone dan deletable mengikuti mesin status SDD §8.2.
func gone(status string) bool      { return status == "REVOKED" || status == "DELETED" }
func deletable(status string) bool { return status == "ACTIVE" || status == "SUSPENDED" }

// CreateRenewalChallenge menyimpan nonce untuk kredensial ACTIVE atau SUSPENDED dan mengembalikan
// ID card instance-nya. Nonce dipakai untuk perpanjangan (yang tetap mensyaratkan ACTIVE dan kanal
// aktif) dan hapus kartu (ADR-0026/0027).
func (s *Store) CreateRenewalChallenge(ctx context.Context, credID, nonce []byte, expiresAt time.Time) (string, error) {
	var id, status, cardID, cardStatus string
	err := s.pool.QueryRow(ctx, `
		SELECT c.id, c.status, ci.id, ci.status
		FROM credentials c JOIN card_instances ci ON ci.id = c.card_instance_id
		WHERE c.cred_id = $1`, credID).Scan(&id, &status, &cardID, &cardStatus)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	if err != nil {
		return "", err
	}
	switch {
	case gone(status) || gone(cardStatus):
		return "", ErrGone
	case !deletable(status) || !deletable(cardStatus):
		return "", ErrNotRenewable
	}
	_, err = s.pool.Exec(ctx, `INSERT INTO renewal_challenges (nonce, credential_id, expires_at) VALUES ($1, $2, $3)`, nonce, id, expiresAt)
	return cardID, err
}

// CardGone dan CardDeletable: status card instance untuk hapus kartu (ADR-0027).
func CardGone(status string) bool      { return gone(status) }
func CardDeletable(status string) bool { return deletable(status) }

// PurgeRenewalChallenges menghapus nonce yang kedaluwarsa sebelum batas waktu.
func (s *Store) PurgeRenewalChallenges(ctx context.Context, before time.Time) (int64, error) {
	tag, err := s.pool.Exec(ctx, `DELETE FROM renewal_challenges WHERE expires_at < $1`, before)
	return tag.RowsAffected(), err
}

// RevokedCredential adalah kredensial yang baru dicabut bersama kartunya.
type RevokedCredential struct {
	CredID  []byte
	Channel string
}

// RevokeCard menandai nonce terpakai, lalu mencabut semua kredensial ACTIVE kartu dan card
// instance-nya dalam transaksi pemanggil (hapus kartu, ADR-0026). Slot batas 8 kartu terbebas.
func (t *Tx) RevokeCard(ctx context.Context, cardID string, nonce []byte, reason string, now time.Time) ([]RevokedCredential, error) {
	tag, err := t.tx.Exec(ctx, `UPDATE renewal_challenges SET used_at = $2 WHERE nonce = $1 AND used_at IS NULL`, nonce, now)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() != 1 {
		return nil, ErrNotRenewable
	}
	rows, err := t.tx.Query(ctx, `
		UPDATE credentials SET status = 'REVOKED', revoked_at = $2, revoke_reason = $3
		WHERE card_instance_id = $1 AND status IN ('ACTIVE', 'SUSPENDED')
		RETURNING cred_id, channel`, cardID, now, reason)
	if err != nil {
		return nil, err
	}
	var revoked []RevokedCredential
	for rows.Next() {
		var r RevokedCredential
		if err := rows.Scan(&r.CredID, &r.Channel); err != nil {
			rows.Close()
			return nil, err
		}
		revoked = append(revoked, r)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if _, err := t.tx.Exec(ctx, `UPDATE card_instances SET status = 'REVOKED' WHERE id = $1`, cardID); err != nil {
		return nil, err
	}
	return revoked, nil
}

// CredentialCert membaca sertifikat dan masa berlaku yang tersimpan (diagnostik dan test).
func (s *Store) CredentialCert(ctx context.Context, credID []byte) ([]byte, time.Time, error) {
	var cert []byte
	var notAfter time.Time
	err := s.pool.QueryRow(ctx, `SELECT cert, not_after FROM credentials WHERE cred_id = $1`, credID).Scan(&cert, &notAfter)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, time.Time{}, ErrNotFound
	}
	return cert, notAfter, err
}

// CredentialForRenewal membaca kredensial dan mengunci barisnya sampai transaksi selesai,
// sehingga dua perpanjangan untuk kredensial yang sama berjalan berurutan.
func (t *Tx) CredentialForRenewal(ctx context.Context, credID []byte) (RenewableCredential, error) {
	var c RenewableCredential
	var zones []string
	var bitmap, validity *string
	var cardBitmap, invitationBitmap *int64
	err := t.tx.QueryRow(ctx, `
		SELECT c.id, c.channel, c.status, c.cred_id, c.pubkey, ci.id, ci.status, ci.device_id, s.id, s.name, s.site_code,
		       COALESCE(ARRAY(SELECT jsonb_array_elements_text(s.policy -> 'zones')), '{}'),
		       s.policy ->> 'zones_bitmap',
		       s.policy ->> 'cert_validity_days',
		       pc.zones_bitmap,
		       inv.zones_bitmap
		FROM credentials c
		JOIN card_instances ci ON ci.id = c.card_instance_id
		JOIN sites s ON s.id = ci.site_id
		LEFT JOIN physical_cards pc ON pc.id = ci.physical_card_id
		LEFT JOIN invitations inv ON inv.id = ci.invitation_id
		WHERE c.cred_id = $1
		FOR NO KEY UPDATE OF c`, credID).Scan(&c.ID, &c.Channel, &c.Status, &c.CredID, &c.PubKey, &c.Site.ID, &c.CardStatus, &c.Site.DeviceID,
		&c.Site.SiteID, &c.Site.SiteName, &c.Site.SiteCode, &zones, &bitmap, &validity, &cardBitmap, &invitationBitmap)
	if errors.Is(err, pgx.ErrNoRows) {
		return RenewableCredential{}, ErrNotFound
	}
	if err != nil {
		return RenewableCredential{}, err
	}
	c.Site.Status = c.CardStatus
	c.Site.applyZones(zones, bitmap, validity, cardBitmap, invitationBitmap)
	return c, nil
}

// RenewalChallengeValid mengunci nonce bila milik kredensial ini, belum dipakai, dan belum
// kedaluwarsa pada waktu now.
func (t *Tx) RenewalChallengeValid(ctx context.Context, credentialID string, nonce []byte, now time.Time) (bool, error) {
	var one int
	err := t.tx.QueryRow(ctx, `
		SELECT 1 FROM renewal_challenges
		WHERE nonce = $1 AND credential_id = $2 AND used_at IS NULL AND expires_at > $3
		FOR UPDATE`, nonce, credentialID, now).Scan(&one)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}

// CompleteRenewal menandai nonce terpakai dan menyimpan sertifikat baru dalam transaksi yang sama.
func (t *Tx) CompleteRenewal(ctx context.Context, credentialID string, nonce, cert []byte, notAfter, now time.Time) error {
	tag, err := t.tx.Exec(ctx, `UPDATE renewal_challenges SET used_at = $2 WHERE nonce = $1 AND used_at IS NULL`, nonce, now)
	if err != nil {
		return err
	}
	if tag.RowsAffected() != 1 {
		return ErrNotRenewable
	}
	_, err = t.tx.Exec(ctx, `UPDATE credentials SET cert = $2, not_after = $3 WHERE id = $1`, credentialID, cert, notAfter)
	return err
}

// ReaderGroupKeys: hex group_id → [kunci aktif, kunci berikutnya] untuk satu gedung.
func (t *Tx) ReaderGroupKeys(ctx context.Context, siteID string) (map[string][][]byte, error) {
	rows, err := t.tx.Query(ctx, `SELECT id, pubkey, next_pubkey FROM reader_groups WHERE site_id = $1`, siteID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	keys := map[string][][]byte{}
	for rows.Next() {
		var id, pub, next []byte
		if err := rows.Scan(&id, &pub, &next); err != nil {
			return nil, err
		}
		list := [][]byte{pub}
		if next != nil {
			list = append(list, next)
		}
		keys[hex.EncodeToString(id)] = list
	}
	return keys, rows.Err()
}

func (t *Tx) HasActiveCredential(ctx context.Context, cardInstanceID, channel string) (bool, error) {
	var exists bool
	err := t.tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM credentials WHERE card_instance_id = $1 AND channel = $2 AND status = 'ACTIVE')`, cardInstanceID, channel).Scan(&exists)
	return exists, err
}

// SaveCredential menyimpan kredensial dan mengaktifkan card instance (hanya dari
// PROVISIONING atau ACTIVE). Indeks unik parsial menolak kredensial aktif kedua per kanal.
func (t *Tx) SaveCredential(ctx context.Context, c Credential) error {
	tag, err := t.tx.Exec(ctx, `UPDATE card_instances SET status = 'ACTIVE' WHERE id = $1 AND status IN ('PROVISIONING', 'ACTIVE')`, c.CardInstanceID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() != 1 {
		return ErrNotProvisionable
	}
	_, err = t.tx.Exec(ctx, `INSERT INTO credentials (id, card_instance_id, channel, cred_id, pubkey, cert, not_after) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		newUUID(), c.CardInstanceID, c.Channel, c.CredID, c.PubKey, c.Cert, c.NotAfter)
	return err
}

func (s *Store) CredentialCount(ctx context.Context, cardInstanceID string) (int, error) {
	var n int
	err := s.pool.QueryRow(ctx, `SELECT count(*) FROM credentials WHERE card_instance_id = $1`, cardInstanceID).Scan(&n)
	return n, err
}

// Idempotent menjalankan fn paling banyak sekali per key, di dalam satu transaksi yang
// memegang advisory lock key tersebut. Bila fn gagal (error atau status ≥ 500) seluruh
// transaksi di-rollback sehingga retry aman; selain itu respons disimpan dan di-commit
// bersama hasil kerja fn.
func (s *Store) Idempotent(ctx context.Context, key string, requestHash []byte, fn func(ctx context.Context, tx *Tx) (int, []byte, error)) (int, []byte, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return 0, nil, err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, key); err != nil {
		return 0, nil, err
	}
	var storedHash, body []byte
	var status int
	err = tx.QueryRow(ctx, `SELECT request_hash, status, body FROM idempotency_keys WHERE key = $1`, key).Scan(&storedHash, &status, &body)
	switch {
	case err == nil:
		if !bytes.Equal(storedHash, requestHash) {
			return 0, nil, ErrIdempotencyConflict
		}
		return status, body, nil
	case !errors.Is(err, pgx.ErrNoRows):
		return 0, nil, err
	}
	status, body, err = fn(ctx, &Tx{tx: tx})
	if err != nil || status >= 500 {
		return status, body, err // rollback lewat defer: tidak ada yang tersimpan
	}
	if status < 200 || status > 299 {
		return status, body, nil // 4xx tidak disimpan: tabel tak bisa ditumbuhkan penyerang
	}
	if body == nil {
		body = []byte{}
	}
	if _, err := tx.Exec(ctx, `INSERT INTO idempotency_keys (key, request_hash, status, body) VALUES ($1, $2, $3, $4)`, key, requestHash, status, body); err != nil {
		return 0, nil, err
	}
	return status, body, tx.Commit(ctx)
}

func looksLikeUUID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for i, c := range s {
		switch {
		case i == 8 || i == 13 || i == 18 || i == 23:
			if c != '-' {
				return false
			}
		case !strings.ContainsRune("0123456789abcdefABCDEF", c):
			return false
		}
	}
	return true
}

// SetSitePolicy menyimpan kebijakan gedung (JSON; mis. zones, zones_bitmap, cert_validity_days).
func (s *Store) SetSitePolicy(ctx context.Context, siteID string, policy []byte) error {
	tag, err := s.pool.Exec(ctx, `UPDATE sites SET policy = $2::jsonb WHERE id = $1`, siteID, string(policy))
	if err == nil && tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return err
}

// SetCardInstanceStatus mengubah status card instance (aksi admin/lifecycle, SDD §8.2).
func (s *Store) SetCardInstanceStatus(ctx context.Context, id, status string) error {
	tag, err := s.pool.Exec(ctx, `UPDATE card_instances SET status = $2 WHERE id = $1`, id, status)
	if err == nil && tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return err
}
