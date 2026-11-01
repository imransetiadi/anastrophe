package store

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// Invitation adalah undangan enrolment sekali pakai dari pengelola gedung (FR-12, FR-53).
type Invitation struct {
	SiteID      string
	CardHMAC    []byte        // opsional: undangan diikat ke kartu terdaftar (zona dari kartu)
	ContactHMAC []byte        // opsional; pencocokan dengan akun menyusul (FR-03)
	ZonesBitmap uint64        // zona bila tidak diikat ke kartu; 0 = tidak membuka zona apa pun
	TTL         time.Duration // 1–30 hari (SDD §5.6: default 7 hari)
}

var (
	// ErrInvitationInvalid: undangan tidak dikenal, kedaluwarsa, atau sudah dipakai; dijawab identik.
	ErrInvitationInvalid = errors.New("store: undangan tidak berlaku")
	errInvalidTTL        = errors.New("store: masa berlaku undangan harus 1–30 hari")
)

// InvitationTokenHash memvalidasi bentuk token (32 byte, base64url tanpa padding = 43 karakter) lalu
// mengembalikan SHA-256 dari byte-nya. Token berentropi 256 bit, jadi hash tanpa kunci aman dari tebakan.
func InvitationTokenHash(token string) ([]byte, error) {
	raw, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(token) != 43 || len(raw) != 32 {
		return nil, ErrInvitationInvalid
	}
	sum := sha256.Sum256(raw)
	return sum[:], nil
}

// CreateInvitation membuat undangan dan mengembalikan token mentahnya satu kali; yang disimpan hanya
// hash-nya. Undangan berkartu wajib menunjuk kartu ACTIVE di registri gedung.
func (s *Store) CreateInvitation(ctx context.Context, inv Invitation, operator string, at time.Time) (string, time.Time, error) {
	if !operatorName.MatchString(operator) {
		return "", time.Time{}, ErrInvalidOperator
	}
	if !looksLikeUUID(inv.SiteID) {
		return "", time.Time{}, ErrNotFound
	}
	if inv.TTL < 24*time.Hour || inv.TTL > 30*24*time.Hour {
		return "", time.Time{}, errInvalidTTL
	}
	if (inv.CardHMAC != nil && len(inv.CardHMAC) != 32) || (inv.ContactHMAC != nil && len(inv.ContactHMAC) != 32) {
		return "", time.Time{}, errInvalidHMAC
	}
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", time.Time{}, err
	}
	hash := sha256.Sum256(raw)
	expiresAt := at.Add(inv.TTL)
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var site string
		if err := tx.QueryRow(ctx, `SELECT id::text FROM sites WHERE id = $1`, inv.SiteID).Scan(&site); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrNotFound
			}
			return err
		}
		var card *string
		if inv.CardHMAC != nil {
			var id string
			err := tx.QueryRow(ctx, `SELECT id::text FROM physical_cards WHERE site_id = $1 AND card_id_hmac = $2 AND status = 'ACTIVE'`, site, inv.CardHMAC).Scan(&id)
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrNotRegistered
			}
			if err != nil {
				return err
			}
			card = &id
		}
		id := newUUID()
		if _, err := tx.Exec(ctx, `
			INSERT INTO invitations (id, site_id, physical_card_id, contact_hmac, token_hash, zones_bitmap, expires_at, created_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
			id, site, card, inv.ContactHMAC, hash[:], int64(inv.ZonesBitmap), expiresAt, at); err != nil {
			return err
		}
		return (&Tx{tx: tx}).AppendAudit(ctx, AuditEvent{
			SiteID: site, Actor: "operator:" + operator, Action: "invitation.created", Subject: "invitation:" + id,
			Data: map[string]any{"expires_at": expiresAt.UTC().Format(time.RFC3339), "bound_to_card": card != nil}, At: at,
		})
	})
	if err != nil {
		return "", time.Time{}, err
	}
	return base64.RawURLEncoding.EncodeToString(raw), expiresAt, nil
}

// EnrollInvitation memakai undangan, dalam transaksi sendiri.
func (s *Store) EnrollInvitation(ctx context.Context, deviceID string, tokenHash []byte, at time.Time) (CardEnrollment, error) {
	var r CardEnrollment
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var err error
		r, err = (&Tx{tx: tx}).EnrollInvitation(ctx, deviceID, tokenHash, at)
		return err
	})
	if err != nil {
		return CardEnrollment{}, err
	}
	return r, nil
}

// EnrollInvitation membuat card instance PROVISIONING dari undangan: undangan adalah niat eksplisit
// pengelola, jadi aturan perangkat tambahan ADR-0032 tidak berlaku (SDD §8.2). Undangan dianggap
// terpakai selama punya instance yang tidak ABANDONED; perangkat yang sama melanjutkan instance-nya
// (ADR-0034). Undangan berkartu menyetujui instance perangkat itu yang belum selesai untuk kartu yang
// sama (ADR-0035). Tak dikenal, kedaluwarsa, terpakai, dan kartu yang keluar dari registri sama-sama
// ErrInvitationInvalid.
func (t *Tx) EnrollInvitation(ctx context.Context, deviceID string, tokenHash []byte, at time.Time) (CardEnrollment, error) {
	return t.enrollInvitation(ctx, deviceID, tokenHash, at, true)
}

func (t *Tx) enrollInvitation(ctx context.Context, deviceID string, tokenHash []byte, at time.Time, retry bool) (CardEnrollment, error) {
	if !looksLikeUUID(deviceID) {
		return CardEnrollment{}, ErrNotFound
	}
	if len(tokenHash) != 32 {
		return CardEnrollment{}, ErrInvitationInvalid
	}
	device, _, err := lockDevice(ctx, t.tx, deviceID)
	if err != nil {
		return CardEnrollment{}, err
	}
	var id, site string
	var card *string
	var expiresAt time.Time
	err = t.tx.QueryRow(ctx, `SELECT id::text, site_id::text, physical_card_id::text, expires_at FROM invitations WHERE token_hash = $1 FOR UPDATE`, tokenHash).
		Scan(&id, &site, &card, &expiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return CardEnrollment{}, ErrInvitationInvalid
	}
	if err != nil {
		return CardEnrollment{}, err
	}
	if !at.Before(expiresAt) {
		return CardEnrollment{}, ErrInvitationInvalid
	}
	cardID := ""
	if card != nil {
		cardID = *card
		// Review akhir I2: kartu yang tidak lagi ACTIVE di registri dijawab seperti undangan tak berlaku
		// (SDD §8.1). Urutan kunci: perangkat, undangan, lalu baris kartu.
		var cardStatus string
		if err := t.tx.QueryRow(ctx, `SELECT status FROM physical_cards WHERE id = $1 FOR UPDATE`, cardID).Scan(&cardStatus); err != nil {
			return CardEnrollment{}, err
		}
		if cardStatus != "ACTIVE" {
			return CardEnrollment{}, ErrInvitationInvalid
		}
	}
	if _, err := t.abandonStale(ctx, at, device, cardID, id); err != nil {
		return CardEnrollment{}, err
	}
	var existing, holder, status string
	err = t.tx.QueryRow(ctx, `
		SELECT id::text, device_id::text, status FROM card_instances
		WHERE invitation_id = $1 AND status <> 'ABANDONED' ORDER BY created_at DESC LIMIT 1`, id).Scan(&existing, &holder, &status)
	switch {
	case err == nil:
		if holder != device || (status != "PROVISIONING" && status != "PENDING_APPROVAL") {
			return CardEnrollment{}, ErrInvitationInvalid
		}
		if status == "PROVISIONING" {
			// Dijaga status (review akhir undangan M4), seperti jalur kartu.
			tag, err := t.tx.Exec(ctx, `UPDATE card_instances SET status_changed_at = $2 WHERE id = $1 AND status = 'PROVISIONING'`, existing, at)
			if err != nil {
				return CardEnrollment{}, err
			}
			if tag.RowsAffected() != 1 {
				if retry {
					return t.enrollInvitation(ctx, deviceID, tokenHash, at, false)
				}
				return CardEnrollment{}, errInstanceChanged
			}
		}
		return CardEnrollment{ID: existing, Status: status, Resumed: true}, nil
	case !errors.Is(err, pgx.ErrNoRows):
		return CardEnrollment{}, err
	}
	if card != nil {
		var held, heldStatus string
		var heldInvitation *string
		err := t.tx.QueryRow(ctx, `
			SELECT id::text, status, invitation_id::text FROM card_instances
			WHERE physical_card_id = $1 AND device_id = $2 AND status = ANY($3)
			ORDER BY created_at DESC LIMIT 1 FOR UPDATE`, *card, device, activeStatuses).Scan(&held, &heldStatus, &heldInvitation)
		switch {
		case err == nil:
			return t.approveHeldInstance(ctx, device, site, id, held, heldStatus, heldInvitation, at)
		case !errors.Is(err, pgx.ErrNoRows):
			return CardEnrollment{}, err
		}
	}
	var active int
	if err := t.tx.QueryRow(ctx, `SELECT count(*) FROM card_instances WHERE device_id = $1 AND status = ANY($2)`, device, activeStatuses).Scan(&active); err != nil {
		return CardEnrollment{}, err
	}
	if active >= MaxActiveCardsPerDevice {
		return CardEnrollment{}, ErrCardLimit
	}
	instance := newUUID()
	if _, err := t.tx.Exec(ctx, `
		INSERT INTO card_instances (id, device_id, site_id, physical_card_id, invitation_id, status, status_changed_at)
		VALUES ($1, $2, $3, $4, $5, 'PROVISIONING', $6)`, instance, device, site, card, id, at); err != nil {
		return CardEnrollment{}, err
	}
	if _, err := t.tx.Exec(ctx, `UPDATE invitations SET used_at = $2 WHERE id = $1`, id, at); err != nil {
		return CardEnrollment{}, err
	}
	err = t.AppendAudit(ctx, AuditEvent{
		SiteID: site, Actor: "device:" + device, Action: "enrollment.started", Subject: "card_instance:" + instance,
		Data: map[string]any{"status": "PROVISIONING", "method": "invitation", "invitation": id}, At: at,
	})
	if err != nil {
		return CardEnrollment{}, err
	}
	return CardEnrollment{ID: instance, Status: "PROVISIONING"}, nil
}

// approveHeldInstance menangani perangkat yang sudah memegang instance aktif untuk kartu undangan
// (ADR-0035). ACTIVE/SUSPENDED tetap duplikat. Instance yang belum selesai menjadi PROVISIONING dan
// ditautkan ke undangan, dengan audit enrollment.approved; tidak ada instance baru, jadi batas kartu
// tidak berubah. Instance milik undangan lain dilanjutkan apa adanya tanpa memakai undangan ini.
func (t *Tx) approveHeldInstance(ctx context.Context, device, site, invitation, instance, status string, linked *string, at time.Time) (CardEnrollment, error) {
	if status != "PROVISIONING" && status != "PENDING_APPROVAL" {
		return CardEnrollment{}, ErrDuplicateEnrollment
	}
	if linked != nil {
		if status == "PROVISIONING" {
			if _, err := t.tx.Exec(ctx, `UPDATE card_instances SET status_changed_at = $2 WHERE id = $1`, instance, at); err != nil {
				return CardEnrollment{}, err
			}
		}
		return CardEnrollment{ID: instance, Status: status, Resumed: true}, nil
	}
	if _, err := t.tx.Exec(ctx, `UPDATE card_instances SET status = 'PROVISIONING', invitation_id = $2, status_changed_at = $3 WHERE id = $1`, instance, invitation, at); err != nil {
		return CardEnrollment{}, err
	}
	if _, err := t.tx.Exec(ctx, `UPDATE invitations SET used_at = $2 WHERE id = $1`, invitation, at); err != nil {
		return CardEnrollment{}, err
	}
	err := t.AppendAudit(ctx, AuditEvent{
		SiteID: site, Actor: "device:" + device, Action: "enrollment.approved", Subject: "card_instance:" + instance,
		Data: map[string]any{"method": "invitation", "invitation": invitation, "from": status}, At: at,
	})
	if err != nil {
		return CardEnrollment{}, err
	}
	return CardEnrollment{ID: instance, Status: "PROVISIONING", Resumed: true}, nil
}
