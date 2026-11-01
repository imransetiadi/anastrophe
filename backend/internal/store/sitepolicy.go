package store

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
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

func parseSitePolicy(raw []byte) SitePolicy {
	var p struct {
		CertValidityDays int      `json:"cert_validity_days"`
		Channels         []string `json:"channels"`
		Zones            []string `json:"zones"`
	}
	_ = json.Unmarshal(raw, &p) // kebijakan rusak dibaca sebagai default, sama dengan applyPolicy
	if p.CertValidityDays < 1 || p.CertValidityDays > 30 {
		p.CertValidityDays = 0
	}
	return SitePolicy{CertValidityDays: p.CertValidityDays, Channels: p.Channels, ZoneCount: len(p.Zones)}
}

// SitePolicyOf membaca kebijakan gedung.
func (s *Store) SitePolicyOf(ctx context.Context, siteID string) (SitePolicy, error) {
	if !looksLikeUUID(siteID) {
		return SitePolicy{}, ErrNotFound
	}
	var raw []byte
	err := s.pool.QueryRow(ctx, `SELECT policy::text FROM sites WHERE id = $1`, siteID).Scan(&raw)
	if errors.Is(err, pgx.ErrNoRows) {
		return SitePolicy{}, ErrNotFound
	}
	if err != nil {
		return SitePolicy{}, err
	}
	return parseSitePolicy(raw), nil
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
	var raw []byte
	err := s.InTx(ctx, func(t *Tx) error {
		if err := t.tx.QueryRow(ctx, `SELECT policy::text FROM sites WHERE id = $1 FOR UPDATE`, siteID).Scan(&raw); err != nil {
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
		if err := t.tx.QueryRow(ctx, `SELECT policy::text FROM sites WHERE id = $1`, siteID).Scan(&raw); err != nil {
			return err
		}
		return t.AppendAudit(ctx, AuditEvent{SiteID: siteID, Actor: "operator:" + operator, Action: "site.policy_updated", Subject: "site:" + siteID, Data: data, At: at})
	})
	if err != nil {
		return SitePolicy{}, err
	}
	return parseSitePolicy(raw), nil
}

// sitePolicyChannelsSQL: kanal kebijakan gedung sebagai text[], NULL bila tidak dibatasi.
const sitePolicyChannelsSQL = `CASE WHEN s.policy ? 'channels' THEN ARRAY(SELECT jsonb_array_elements_text(s.policy -> 'channels')) END`

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
