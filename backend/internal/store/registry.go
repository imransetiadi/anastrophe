package store

import (
	"context"
	"errors"
	"regexp"
	"time"

	"github.com/jackc/pgx/v5"
)

// PhysicalCard adalah satu baris registri gedung: hanya HMAC per gedung, tidak pernah identitas
// kartu atau kontak mentah (CLAUDE.md aturan 6; FR-52).
type PhysicalCard struct {
	CardHMAC    []byte // 32 B
	ContactHMAC []byte // 32 B, atau nil bila registri tidak memuat kontak
	ZonesBitmap uint64
}

var (
	// ErrSiteUnsupported: gedung belum punya satu pun kartu aktif di registri (ENR-SITE-UNSUPPORTED).
	ErrSiteUnsupported = errors.New("store: gedung belum punya registri kartu")
	// ErrNotRegistered: tidak ada kartu ACTIVE dengan HMAC itu; kartu REMOVED dijawab sama.
	ErrNotRegistered = errors.New("store: kartu tidak terdaftar")
	// ErrDuplicateEnrollment: perangkat ini sudah memegang card instance aktif untuk kartu itu.
	ErrDuplicateEnrollment = errors.New("store: kartu sudah ada di perangkat ini")
	// ErrNotPending: card instance tidak berstatus PENDING_APPROVAL.
	ErrNotPending = errors.New("store: card instance tidak menunggu persetujuan")
	// ErrInvalidOperator: nama operator kosong atau di luar [A-Za-z0-9._-]{1,64}.
	ErrInvalidOperator = errors.New("store: nama operator tidak valid")

	errInvalidHMAC = errors.New("store: HMAC registri harus 32 byte")
	operatorName   = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)
)

// UpsertPhysicalCards menambah atau memperbarui kartu registri gedung dalam satu transaksi, lalu
// mencatat audit registry.imported yang hanya berisi jumlah.
func (s *Store) UpsertPhysicalCards(ctx context.Context, siteID, operator string, cards []PhysicalCard, rejected int, at time.Time) (added, updated int, err error) {
	if !operatorName.MatchString(operator) {
		return 0, 0, ErrInvalidOperator
	}
	if !looksLikeUUID(siteID) {
		return 0, 0, ErrNotFound
	}
	for _, c := range cards {
		if len(c.CardHMAC) != 32 || (c.ContactHMAC != nil && len(c.ContactHMAC) != 32) {
			return 0, 0, errInvalidHMAC
		}
	}
	err = pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		added, updated = 0, 0
		var site string
		if err := tx.QueryRow(ctx, `SELECT id::text FROM sites WHERE id = $1`, siteID).Scan(&site); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrNotFound
			}
			return err
		}
		for _, c := range cards {
			var inserted bool
			err := tx.QueryRow(ctx, `
				INSERT INTO physical_cards (id, site_id, card_id_hmac, holder_contact_hmac, zones_bitmap)
				VALUES ($1, $2, $3, $4, $5)
				ON CONFLICT (site_id, card_id_hmac) DO UPDATE
				SET holder_contact_hmac = EXCLUDED.holder_contact_hmac, zones_bitmap = EXCLUDED.zones_bitmap,
				    status = 'ACTIVE', updated_at = now()
				RETURNING xmax = 0`, newUUID(), site, c.CardHMAC, c.ContactHMAC, int64(c.ZonesBitmap)).Scan(&inserted)
			if err != nil {
				return err
			}
			if inserted {
				added++
			} else {
				updated++
			}
		}
		return (&Tx{tx: tx}).AppendAudit(ctx, AuditEvent{
			SiteID: site, Actor: "operator:" + operator, Action: "registry.imported", Subject: "site:" + site,
			Data: map[string]any{"added": added, "updated": updated, "rejected": rejected}, At: at,
		})
	})
	if err != nil {
		return 0, 0, err
	}
	return added, updated, nil
}

// StartCardEnrollment memulai enrolment untuk kartu fisik yang cocok dengan registri gedung
// (SDD §8.4.1), dalam transaksi sendiri.
func (s *Store) StartCardEnrollment(ctx context.Context, deviceID, siteID string, cardHMAC []byte, at time.Time) (id, status string, err error) {
	err = pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var err error
		id, status, err = (&Tx{tx: tx}).StartCardEnrollment(ctx, deviceID, siteID, cardHMAC, at)
		return err
	})
	if err != nil {
		return "", "", err
	}
	return id, status, nil
}

// StartCardEnrollment: perangkat pertama mendapat PROVISIONING; perangkat lain untuk kartu yang sama
// mendapat PENDING_APPROVAL sampai akun dan keanggotaan ada (ADR-0032). Kunci diambil berurutan
// (perangkat, lalu kartu) sehingga enrolment bersamaan tersusun tanpa deadlock.
func (t *Tx) StartCardEnrollment(ctx context.Context, deviceID, siteID string, cardHMAC []byte, at time.Time) (string, string, error) {
	if !looksLikeUUID(deviceID) || !looksLikeUUID(siteID) {
		return "", "", ErrNotFound
	}
	if len(cardHMAC) != 32 {
		return "", "", errInvalidHMAC
	}
	device, active, err := lockDevice(ctx, t.tx, deviceID)
	if err != nil {
		return "", "", err
	}
	var site string
	var hasCards bool
	err = t.tx.QueryRow(ctx, `
		SELECT s.id::text, EXISTS (SELECT 1 FROM physical_cards pc WHERE pc.site_id = s.id AND pc.status = 'ACTIVE')
		FROM sites s WHERE s.id = $1`, siteID).Scan(&site, &hasCards)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", ErrNotFound
	}
	if err != nil {
		return "", "", err
	}
	if !hasCards {
		return "", "", ErrSiteUnsupported
	}
	var card string
	err = t.tx.QueryRow(ctx, `SELECT id::text FROM physical_cards WHERE site_id = $1 AND card_id_hmac = $2 AND status = 'ACTIVE' FOR UPDATE`, site, cardHMAC).Scan(&card)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", ErrNotRegistered
	}
	if err != nil {
		return "", "", err
	}
	rows, err := t.tx.Query(ctx, `SELECT device_id::text FROM card_instances WHERE physical_card_id = $1 AND status = ANY($2)`, card, activeStatuses)
	if err != nil {
		return "", "", err
	}
	holders, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return "", "", err
	}
	status := "PROVISIONING"
	for _, holder := range holders {
		if holder == device {
			return "", "", ErrDuplicateEnrollment
		}
		status = "PENDING_APPROVAL"
	}
	if active >= MaxActiveCardsPerDevice {
		return "", "", ErrCardLimit
	}
	id := newUUID()
	if _, err := t.tx.Exec(ctx, `INSERT INTO card_instances (id, device_id, site_id, physical_card_id, status) VALUES ($1, $2, $3, $4, $5)`,
		id, device, site, card, status); err != nil {
		return "", "", err
	}
	err = t.AppendAudit(ctx, AuditEvent{
		SiteID: site, Actor: "device:" + device, Action: "enrollment.started", Subject: "card_instance:" + id,
		Data: map[string]any{"status": status}, At: at,
	})
	if err != nil {
		return "", "", err
	}
	return id, status, nil
}

// DecideEnrollment: operator menyetujui (PROVISIONING) atau menolak (REJECTED) card instance
// PENDING_APPROVAL (ADR-0032), dengan audit enrollment.approved atau enrollment.rejected.
func (s *Store) DecideEnrollment(ctx context.Context, cardInstanceID string, approve bool, operator string, at time.Time) error {
	if !operatorName.MatchString(operator) {
		return ErrInvalidOperator
	}
	if !looksLikeUUID(cardInstanceID) {
		return ErrNotFound
	}
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var id, site, status string
		err := tx.QueryRow(ctx, `SELECT id::text, site_id::text, status FROM card_instances WHERE id = $1 FOR UPDATE`, cardInstanceID).Scan(&id, &site, &status)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if status != "PENDING_APPROVAL" {
			return ErrNotPending
		}
		next, action := "REJECTED", "enrollment.rejected"
		if approve {
			next, action = "PROVISIONING", "enrollment.approved"
		}
		if _, err := tx.Exec(ctx, `UPDATE card_instances SET status = $2 WHERE id = $1`, id, next); err != nil {
			return err
		}
		return (&Tx{tx: tx}).AppendAudit(ctx, AuditEvent{
			SiteID: site, Actor: "operator:" + operator, Action: action, Subject: "card_instance:" + id, At: at,
		})
	})
}

// lockDevice mengunci baris perangkat dan menghitung card instance aktifnya (FR-15).
func lockDevice(ctx context.Context, tx pgx.Tx, deviceID string) (device string, active int, err error) {
	if err := tx.QueryRow(ctx, `SELECT id::text FROM devices WHERE id = $1 FOR UPDATE`, deviceID).Scan(&device); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", 0, ErrNotFound
		}
		return "", 0, err
	}
	err = tx.QueryRow(ctx, `SELECT count(*) FROM card_instances WHERE device_id = $1 AND status = ANY($2)`, device, activeStatuses).Scan(&active)
	return device, active, err
}

// applyCardZones: kartu terdaftar menentukan zona (FR-52). Nama zona diambil dari daftar zona
// gedung untuk bit yang menyala; bitmap 0 tidak membuka zona apa pun (fail-closed).
func (e *Enrollment) applyCardZones(names []string, bitmap uint64) {
	e.ZonesBitmap = bitmap
	e.Zones = []string{}
	for i, name := range names {
		if i < 64 && bitmap&(1<<uint(i)) != 0 {
			e.Zones = append(e.Zones, name)
		}
	}
}
