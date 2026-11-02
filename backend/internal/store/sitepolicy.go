package store

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
)

// ErrInvalidPolicy: pembaruan kebijakan gedung di luar batas (masa berlaku 1–30 hari, kanal ble/nfcHCE)
// atau tanpa kunci yang diubah.
var ErrInvalidPolicy = errors.New("store: kebijakan gedung tidak valid")

// policyChannels: kanal yang boleh dibatasi per gedung, dalam urutan prioritas kanal in-app (SDD §4.2).
var policyChannels = []string{"nfcHCE", "ble"}

// SitePolicy adalah ringkasan sites.policy (FR-55, ADR-0049). CertValidityDays 0 berarti default handler;
// Channels nil berarti semua kanal global diizinkan.
type SitePolicy struct {
	CertValidityDays int
	Channels         []string
	ZoneCount        int
}

// PolicyUpdate mengubah hanya kunci yang tidak nil. Channels berisi slice kosong untuk menghapus
// pembatasan kanal ("semua").
type PolicyUpdate struct {
	CertValidityDays *int
	Channels         *[]string
}

// rowQuerier: pool maupun transaksi, agar CLI dan transaksi pembaruan membaca kebijakan dengan SQL yang
// sama persis dengan penerbitan sertifikat.
type rowQuerier interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// sitePolicySQL membaca kebijakan seperti yang ditegakkan server: masa berlaku lewat ->> (angka maupun
// teks), kanal lewat sitePolicyChannelsSQL, dan jumlah zona hanya bila zones berupa array.
const sitePolicySQL = `SELECT s.policy ->> 'cert_validity_days', ` + sitePolicyChannelsSQL + `,
	CASE WHEN jsonb_typeof(s.policy -> 'zones') = 'array' THEN jsonb_array_length(s.policy -> 'zones') ELSE 0 END
	FROM sites s WHERE s.id = $1`

func readSitePolicy(ctx context.Context, q rowQuerier, siteID string) (SitePolicy, error) {
	var validity *string
	var p SitePolicy
	err := q.QueryRow(ctx, sitePolicySQL, siteID).Scan(&validity, &p.Channels, &p.ZoneCount)
	if errors.Is(err, pgx.ErrNoRows) {
		return SitePolicy{}, ErrNotFound
	}
	if err != nil {
		return SitePolicy{}, err
	}
	if validity != nil {
		if days, err := strconv.Atoi(*validity); err == nil && days >= 1 && days <= 30 {
			p.CertValidityDays = days // sama dengan applyPolicy saat penerbitan
		}
	}
	return p, nil
}

// SitePolicyOf membaca kebijakan gedung persis seperti yang ditegakkan server.
func (s *Store) SitePolicyOf(ctx context.Context, siteID string) (SitePolicy, error) {
	if !looksLikeUUID(siteID) {
		return SitePolicy{}, ErrNotFound
	}
	return readSitePolicy(ctx, s.pool, siteID)
}

// UpdateSitePolicy mengubah masa berlaku sertifikat dan/atau kanal gedung, lalu mencatat audit
// site.policy_updated dengan nilai baru. Perubahan memakai jsonb_set dan operator '-' di SQL sehingga
// zona, zones_bitmap 64-bit, dan kunci lain tidak pernah melewati JSON Go (float64).
func (s *Store) UpdateSitePolicy(ctx context.Context, siteID, operator string, u PolicyUpdate, at time.Time) (SitePolicy, error) {
	if !operatorName.MatchString(operator) {
		return SitePolicy{}, ErrInvalidOperator
	}
	if u.CertValidityDays == nil && u.Channels == nil {
		return SitePolicy{}, ErrInvalidPolicy
	}
	if u.CertValidityDays != nil && (*u.CertValidityDays < 1 || *u.CertValidityDays > 30) {
		return SitePolicy{}, ErrInvalidPolicy
	}
	var channels []string
	if u.Channels != nil {
		for _, c := range *u.Channels {
			if !slices.Contains(policyChannels, c) {
				return SitePolicy{}, ErrInvalidPolicy
			}
		}
		for _, c := range policyChannels { // urutan kanonik, tanpa duplikat
			if slices.Contains(*u.Channels, c) {
				channels = append(channels, c)
			}
		}
	}
	if !looksLikeUUID(siteID) {
		return SitePolicy{}, ErrNotFound
	}
	var result SitePolicy
	err := s.InTx(ctx, func(t *Tx) error {
		var locked string
		if err := t.tx.QueryRow(ctx, `SELECT id::text FROM sites WHERE id = $1 FOR UPDATE`, siteID).Scan(&locked); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrNotFound
			}
			return err
		}
		data := map[string]any{}
		if u.CertValidityDays != nil {
			if _, err := t.tx.Exec(ctx, `UPDATE sites SET policy = jsonb_set(policy, '{cert_validity_days}', to_jsonb($2::int), true) WHERE id = $1`, siteID, *u.CertValidityDays); err != nil {
				return err
			}
			data["cert_validity_days"] = *u.CertValidityDays
		}
		if u.Channels != nil {
			if len(channels) == 0 {
				if _, err := t.tx.Exec(ctx, `UPDATE sites SET policy = policy - 'channels' WHERE id = $1`, siteID); err != nil {
					return err
				}
				data["channels"] = "semua"
			} else {
				encoded, _ := json.Marshal(channels)
				if _, err := t.tx.Exec(ctx, `UPDATE sites SET policy = jsonb_set(policy, '{channels}', $2::jsonb, true) WHERE id = $1`, siteID, string(encoded)); err != nil {
					return err
				}
				data["channels"] = channels
			}
		}
		var err error
		if result, err = readSitePolicy(ctx, t.tx, siteID); err != nil {
			return err
		}
		return t.AppendAudit(ctx, AuditEvent{SiteID: siteID, Actor: "operator:" + operator, Action: "site.policy_updated", Subject: "site:" + siteID, Data: data, At: at})
	})
	if err != nil {
		return SitePolicy{}, err
	}
	return result, nil
}

// sitePolicyChannelsSQL: kanal kebijakan gedung sebagai text[]. Kunci tidak ada atau JSON null → NULL (tanpa
// pembatasan); array → elemennya, tanpa elemen null; bentuk lain (string, objek, angka) → '{}' (fail-closed:
// tidak ada kanal). Nilai yang ditulis lewat SQL tidak pernah membuat lookup atau enrolment gagal (review
// akhir #1).
const sitePolicyChannelsSQL = `CASE
	WHEN s.policy -> 'channels' IS NULL OR jsonb_typeof(s.policy -> 'channels') = 'null' THEN NULL
	WHEN jsonb_typeof(s.policy -> 'channels') = 'array' THEN ARRAY(SELECT v FROM jsonb_array_elements_text(s.policy -> 'channels') AS v WHERE v IS NOT NULL)
	ELSE '{}'::text[] END`

// zonesSQL: nama zona dari kolom kebijakan sebagai text[] berurutan (indeks = nomor bit). Bukan array → '{}';
// elemen null menjadi string kosong agar posisi bit tidak bergeser.
func zonesSQL(policy string) string {
	return `COALESCE(CASE WHEN jsonb_typeof(` + policy + ` -> 'zones') = 'array' THEN ARRAY(SELECT COALESCE(v, '') FROM jsonb_array_elements_text(` + policy + ` -> 'zones') WITH ORDINALITY AS z(v, n) ORDER BY n) END, '{}')`
}

// SiteChannelsOfInstance membaca kanal kebijakan gedung untuk card instance di dalam transaksi enrolment,
// sehingga instance yang baru dibuat ikut terlihat. nil berarti semua kanal global.
func (t *Tx) SiteChannelsOfInstance(ctx context.Context, instanceID string) ([]string, error) {
	var channels []string
	err := t.tx.QueryRow(ctx, `SELECT `+sitePolicyChannelsSQL+` FROM card_instances ci JOIN sites s ON s.id = ci.site_id WHERE ci.id = $1`, instanceID).Scan(&channels)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return channels, err
}
