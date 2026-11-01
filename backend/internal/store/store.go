// Package store menyimpan data backend di PostgreSQL 16 (SDD §8.1).
package store

import (
	"context"
	"crypto/rand"
	"embed"
	"encoding/hex"
	"errors"
	"fmt"
	"sort"

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
		if err := tx.QueryRow(ctx, `SELECT id FROM devices WHERE id = $1 FOR UPDATE`, deviceID).Scan(&locked); err != nil {
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
