package store

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// ErrSiteExists: site_code sudah dipakai gedung lain.
var ErrSiteExists = errors.New("store: site_code sudah ada")

// ErrReaderGroupExists: group_id reader sudah dipakai gedung lain (mis. -lab-dir yang sama
// dengan -site-code baru).
var ErrReaderGroupExists = errors.New("store: group_id reader sudah dipakai")

// SeedInput adalah data lab untuk cmd/anastrophe-devseed (dev saja).
type SeedInput struct {
	OrgName     string
	SiteName    string
	SiteCode    []byte // 8 B
	Zones       []string
	ZonesBitmap uint64
	GroupID     []byte // 8 B
	GroupKey    []byte // x963 65 B
}

type SeedOutput struct {
	SiteID   string `json:"site_id"`
	DeviceID string `json:"device_id"`
}

// SeedLab membuat organisasi, gedung (dengan kebijakan zona), reader group, dan satu
// perangkat dalam satu transaksi.
func (s *Store) SeedLab(ctx context.Context, in SeedInput) (SeedOutput, error) {
	policy, err := json.Marshal(map[string]any{"zones": in.Zones, "zones_bitmap": in.ZonesBitmap})
	if err != nil {
		return SeedOutput{}, err
	}
	out := SeedOutput{SiteID: newUUID(), DeviceID: newUUID()}
	orgID := newUUID()
	err = pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `INSERT INTO organizations (id, name, region) VALUES ($1, $2, 'ID')`, orgID, in.OrgName); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `INSERT INTO sites (id, org_id, name, country, timezone, site_code, policy) VALUES ($1, $2, $3, 'ID', 'Asia/Jakarta', $4, $5::jsonb)`,
			out.SiteID, orgID, in.SiteName, in.SiteCode, string(policy)); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `INSERT INTO reader_groups (id, site_id, pubkey) VALUES ($1, $2, $3)`, in.GroupID, out.SiteID, in.GroupKey); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `INSERT INTO devices (id) VALUES ($1)`, out.DeviceID)
		return err
	})
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		switch pgErr.ConstraintName {
		case "sites_site_code_key":
			return SeedOutput{}, ErrSiteExists
		case "reader_groups_pkey":
			return SeedOutput{}, ErrReaderGroupExists
		}
	}
	if err != nil {
		return SeedOutput{}, err
	}
	return out, nil
}

// AddLabDevice membuat perangkat baru untuk gedung lab yang sudah ada, misalnya setelah
// slot kartu perangkat lama habis oleh percobaan yang gagal.
func (s *Store) AddLabDevice(ctx context.Context, siteCode []byte) (SeedOutput, error) {
	var out SeedOutput
	err := s.pool.QueryRow(ctx, `SELECT id FROM sites WHERE site_code = $1`, siteCode).Scan(&out.SiteID)
	if errors.Is(err, pgx.ErrNoRows) {
		return SeedOutput{}, ErrNotFound
	}
	if err != nil {
		return SeedOutput{}, err
	}
	out.DeviceID, err = s.CreateDevice(ctx)
	if err != nil {
		return SeedOutput{}, err
	}
	return out, nil
}
