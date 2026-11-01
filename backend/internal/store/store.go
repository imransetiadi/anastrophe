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

// Migrate menjalankan migrasi yang belum diterapkan, masing-masing dalam satu transaksi.
func (s *Store) Migrate(ctx context.Context) error {
	if _, err := s.pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`); err != nil {
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
		err = pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
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
func (s *Store) AddCardInstance(ctx context.Context, deviceID, siteID string) (string, error) {
	id := newUUID()
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var locked string
		if !looksLikeUUID(deviceID) || !looksLikeUUID(siteID) {
			return ErrNotFound
		}
		if err := tx.QueryRow(ctx, `SELECT id FROM devices WHERE id = $1 FOR UPDATE`, deviceID).Scan(&locked); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrNotFound
			}
			return err
		}
		var active int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM card_instances WHERE device_id = $1 AND status = ANY($2)`, deviceID, activeStatuses).Scan(&active); err != nil {
			return err
		}
		if active >= MaxActiveCardsPerDevice {
			return ErrCardLimit
		}
		_, err := tx.Exec(ctx, `INSERT INTO card_instances (id, device_id, site_id, status) VALUES ($1, $2, $3, 'PROVISIONING')`, id, deviceID, siteID)
		return err
	})
	if err != nil {
		return "", err
	}
	return id, nil
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

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
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
	ID          string
	Status      string
	SiteID      string
	SiteName    string
	SiteCode    []byte
	Zones       []string
	ZonesBitmap uint64
}

func (s *Store) Enrollment(ctx context.Context, id string) (Enrollment, error) {
	if !looksLikeUUID(id) {
		return Enrollment{}, ErrNotFound
	}
	var e Enrollment
	var zones []string
	var bitmap *int64
	err := s.pool.QueryRow(ctx, `
		SELECT ci.id, ci.status, s.id, s.name, s.site_code,
		       COALESCE(ARRAY(SELECT jsonb_array_elements_text(s.policy -> 'zones')), '{}'),
		       (s.policy ->> 'zones_bitmap')::bigint
		FROM card_instances ci JOIN sites s ON s.id = ci.site_id
		WHERE ci.id = $1`, id).Scan(&e.ID, &e.Status, &e.SiteID, &e.SiteName, &e.SiteCode, &zones, &bitmap)
	if errors.Is(err, pgx.ErrNoRows) {
		return Enrollment{}, ErrNotFound
	}
	if err != nil {
		return Enrollment{}, err
	}
	e.Zones = append([]string{}, zones...)
	e.ZonesBitmap = 1
	if bitmap != nil && *bitmap > 0 {
		e.ZonesBitmap = uint64(*bitmap)
	}
	return e, nil
}

// ReaderGroupKeys: hex group_id → [kunci aktif, kunci berikutnya] untuk satu gedung.
func (s *Store) ReaderGroupKeys(ctx context.Context, siteID string) (map[string][][]byte, error) {
	rows, err := s.pool.Query(ctx, `SELECT id, pubkey, next_pubkey FROM reader_groups WHERE site_id = $1`, siteID)
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

// Credential yang diterbitkan untuk satu kanal.
type Credential struct {
	CardInstanceID string
	Channel        string
	CredID         []byte
	PubKey         []byte
	Cert           []byte
	NotAfter       time.Time
}

// SaveCredential menyimpan kredensial dan mengaktifkan card instance dalam satu transaksi.
func (s *Store) SaveCredential(ctx context.Context, c Credential) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `INSERT INTO credentials (id, card_instance_id, channel, cred_id, pubkey, cert, not_after) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
			newUUID(), c.CardInstanceID, c.Channel, c.CredID, c.PubKey, c.Cert, c.NotAfter); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE card_instances SET status = 'ACTIVE' WHERE id = $1 AND status = 'PROVISIONING'`, c.CardInstanceID)
		return err
	})
}

func (s *Store) CredentialCount(ctx context.Context, cardInstanceID string) (int, error) {
	var n int
	err := s.pool.QueryRow(ctx, `SELECT count(*) FROM credentials WHERE card_instance_id = $1`, cardInstanceID).Scan(&n)
	return n, err
}

// Idempotent menjalankan fn paling banyak sekali per key. Permintaan dengan key yang sama
// diserialkan lewat advisory lock; ulangan dengan isi sama mendapat respons tersimpan.
func (s *Store) Idempotent(ctx context.Context, key string, requestHash []byte, fn func() (int, []byte, error)) (int, []byte, error) {
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
	status, body, err = fn()
	if err != nil {
		return 0, nil, err
	}
	if status < 500 {
		if _, err := tx.Exec(ctx, `INSERT INTO idempotency_keys (key, request_hash, status, body) VALUES ($1, $2, $3, $4)`, key, requestHash, status, body); err != nil {
			return 0, nil, err
		}
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
