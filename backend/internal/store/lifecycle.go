package store

import (
	"context"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

var (
	// ErrInvalidTransition: status card instance saat ini tidak mengizinkan tindakan operator.
	ErrInvalidTransition = errors.New("store: transisi status tidak diizinkan")
	// ErrInvalidReason: alasan pencabutan bukan kode pendek.
	ErrInvalidReason = errors.New("store: alasan pencabutan tidak valid")
	// ErrInvalidStatus: filter status tidak dikenal.
	ErrInvalidStatus = errors.New("store: status tidak dikenal")
	// ErrInvalidTokenHash: hash token baca status harus SHA-256 (32 byte).
	ErrInvalidTokenHash = errors.New("store: hash token status harus 32 byte")
	// ErrInvalidProvisioningHash: hash rahasia enrolment harus SHA-256 (32 byte).
	ErrInvalidProvisioningHash = errors.New("store: hash rahasia enrolment harus 32 byte")
)

// reasonCode: kode pendek, bukan teks bebas, karena audit append-only tidak boleh memuat data pribadi.
var reasonCode = regexp.MustCompile(`^[a-z_]{1,32}$`)

var cardStatuses = []string{"PENDING_APPROVAL", "PROVISIONING", "ACTIVE", "SUSPENDED", "REVOKED", "DELETED", "REJECTED", "ABANDONED"}

// CardInstanceSummary adalah satu baris daftar operator: tanpa identitas kartu, kontak, maupun token.
type CardInstanceSummary struct {
	ID, Status string
	// Origin: "kartu" (registri), "undangan", atau "-" (data lama tanpa keduanya).
	Origin    string
	Channels  []string
	CreatedAt time.Time
}

// SuspendCard menangguhkan card instance ACTIVE beserta kredensial ACTIVE-nya (FR-51).
func (s *Store) SuspendCard(ctx context.Context, cardInstanceID, operator string, at time.Time) error {
	return s.transition(ctx, cardInstanceID, operator, at, []string{"ACTIVE"}, func(t *Tx, id, _ string) (string, map[string]any, error) {
		if _, err := t.tx.Exec(ctx, `UPDATE credentials SET status = 'SUSPENDED' WHERE card_instance_id = $1 AND status = 'ACTIVE'`, id); err != nil {
			return "", nil, err
		}
		_, err := t.tx.Exec(ctx, `UPDATE card_instances SET status = 'SUSPENDED', status_changed_at = $2 WHERE id = $1`, id, at)
		return "card.suspended", nil, err
	})
}

// ResumeCard memulihkan card instance SUSPENDED beserta kredensial SUSPENDED-nya (FR-51).
func (s *Store) ResumeCard(ctx context.Context, cardInstanceID, operator string, at time.Time) error {
	return s.transition(ctx, cardInstanceID, operator, at, []string{"SUSPENDED"}, func(t *Tx, id, _ string) (string, map[string]any, error) {
		if _, err := t.tx.Exec(ctx, `UPDATE credentials SET status = 'ACTIVE' WHERE card_instance_id = $1 AND status = 'SUSPENDED'`, id); err != nil {
			return "", nil, err
		}
		_, err := t.tx.Exec(ctx, `UPDATE card_instances SET status = 'ACTIVE', status_changed_at = $2 WHERE id = $1`, id, at)
		return "card.resumed", nil, err
	})
}

// RevokeCardInstance mencabut card instance ACTIVE, SUSPENDED, atau PROVISIONING (FR-51); kredensialnya
// masuk denylist. Mengembalikan jumlah kredensial yang dicabut.
func (s *Store) RevokeCardInstance(ctx context.Context, cardInstanceID, reason, operator string, at time.Time) (int, error) {
	if !reasonCode.MatchString(reason) {
		return 0, ErrInvalidReason
	}
	var n int
	err := s.transition(ctx, cardInstanceID, operator, at, []string{"ACTIVE", "SUSPENDED", "PROVISIONING"}, func(t *Tx, id, site string) (string, map[string]any, error) {
		revoked, err := t.revokeInstance(ctx, id, reason, at)
		if err != nil {
			return "", nil, err
		}
		n = len(revoked)
		// Review akhir siklus hidup M8: event per kredensial, pemicu Site Sync yang sama dengan hapus kartu.
		for _, c := range revoked {
			err := t.AppendAudit(ctx, AuditEvent{
				SiteID: site, Actor: "operator:" + operator, Action: "credential.revoked",
				Subject: "credential:" + hex.EncodeToString(c.CredID),
				Data:    map[string]any{"channel": c.Channel, "reason": reason}, At: at,
			})
			if err != nil {
				return "", nil, err
			}
		}
		return "card.revoked", map[string]any{"reason": reason, "credentials": n}, nil
	})
	return n, err
}

// transition mengunci baris instance, memeriksa status asal, menjalankan apply, lalu mencatat audit
// dalam satu transaksi. Urutan kunci: instance, lalu kredensial (sama dengan hapus kartu).
func (s *Store) transition(ctx context.Context, cardInstanceID, operator string, at time.Time, from []string, apply func(t *Tx, id, site string) (string, map[string]any, error)) error {
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
		if !slices.Contains(from, status) {
			return ErrInvalidTransition
		}
		t := &Tx{tx: tx}
		action, data, err := apply(t, id, site)
		if err != nil {
			return err
		}
		return t.AppendAudit(ctx, AuditEvent{SiteID: site, Actor: "operator:" + operator, Action: action, Subject: "card_instance:" + id, Data: data, At: at})
	})
}

// revokeInstance mencabut kredensial ACTIVE/SUSPENDED dan card instance-nya, lalu mencatat kredensial
// itu di denylist sampai sertifikatnya kedaluwarsa (SDD §8.4.3). Pemanggil sudah mengunci baris instance.
func (t *Tx) revokeInstance(ctx context.Context, cardID, reason string, now time.Time) ([]RevokedCredential, error) {
	rows, err := t.tx.Query(ctx, `
		UPDATE credentials SET status = 'REVOKED', revoked_at = $2, revoke_reason = $3
		WHERE card_instance_id = $1 AND status IN ('ACTIVE', 'SUSPENDED')
		RETURNING cred_id, channel, GREATEST(max_not_after, not_after)`, cardID, now, reason)
	if err != nil {
		return nil, err
	}
	revoked, err := pgx.CollectRows(rows, func(row pgx.CollectableRow) (RevokedCredential, error) {
		var r RevokedCredential
		err := row.Scan(&r.CredID, &r.Channel, &r.NotAfter)
		return r, err
	})
	if err != nil {
		return nil, err
	}
	var site string
	if err := t.tx.QueryRow(ctx, `UPDATE card_instances SET status = 'REVOKED', status_changed_at = $2 WHERE id = $1 RETURNING site_id::text`, cardID, now).Scan(&site); err != nil {
		return nil, err
	}
	for _, r := range revoked {
		if _, err := t.tx.Exec(ctx, `
			INSERT INTO denylist_entries (site_id, cred_id, revoked_at, expires_at) VALUES ($1, $2, $3, $4)
			ON CONFLICT (site_id, cred_id) DO NOTHING`, site, r.CredID, now, r.NotAfter); err != nil {
			return nil, err
		}
	}
	return revoked, nil
}

// ListCardInstances mendaftar card instance satu gedung untuk operator, terurut waktu dibuat; status
// kosong berarti semua.
func (s *Store) ListCardInstances(ctx context.Context, siteID, status string) ([]CardInstanceSummary, error) {
	return s.ListCardInstancesFiltered(ctx, siteID, CardInstanceFilter{Status: status})
}

// ErrInvalidFilter: kanal di luar ble/nfcHCE atau awalan id yang bukan karakter id card instance.
var ErrInvalidFilter = errors.New("store: filter daftar tidak valid")

// idPrefix: awalan id card instance (UUID huruf kecil); karakter lain ditolak sehingga masukan tidak pernah
// menjadi pola LIKE (ADR-0050).
var idPrefix = regexp.MustCompile(`^[0-9a-f-]{1,36}$`)

// CardInstanceFilter menyaring daftar card instance (FR-50); kolom kosong berarti tanpa filter, dan semua
// filter digabung AND.
type CardInstanceFilter struct {
	Status   string
	Channel  string
	IDPrefix string
}

// ListCardInstancesFiltered mendaftar card instance gedung dengan filter status, kanal (kredensial ACTIVE
// atau SUSPENDED, sama dengan kolom kanal), dan awalan id. Tanpa identitas kartu atau kontak (aturan 6).
func (s *Store) ListCardInstancesFiltered(ctx context.Context, siteID string, f CardInstanceFilter) ([]CardInstanceSummary, error) {
	if !looksLikeUUID(siteID) {
		return nil, ErrNotFound
	}
	if f.Status != "" && !slices.Contains(cardStatuses, f.Status) {
		return nil, ErrInvalidStatus
	}
	if f.Channel != "" && !slices.Contains(policyChannels, f.Channel) {
		return nil, ErrInvalidFilter
	}
	prefix := strings.ToLower(f.IDPrefix)
	if f.IDPrefix != "" && !idPrefix.MatchString(prefix) {
		return nil, ErrInvalidFilter
	}
	var exists bool
	if err := s.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM sites WHERE id = $1)`, siteID).Scan(&exists); err != nil {
		return nil, err
	}
	if !exists {
		return nil, ErrNotFound
	}
	rows, err := s.pool.Query(ctx, `
		SELECT ci.id::text, ci.status,
		       CASE WHEN ci.invitation_id IS NOT NULL THEN 'undangan' WHEN ci.physical_card_id IS NOT NULL THEN 'kartu' ELSE '-' END,
		       ARRAY(SELECT c.channel FROM credentials c WHERE c.card_instance_id = ci.id AND c.status IN ('ACTIVE', 'SUSPENDED') ORDER BY c.channel),
		       ci.created_at
		FROM card_instances ci
		WHERE ci.site_id = $1 AND ($2 = '' OR ci.status = $2)
		  AND ($3 = '' OR EXISTS (SELECT 1 FROM credentials c WHERE c.card_instance_id = ci.id AND c.channel = $3 AND c.status IN ('ACTIVE', 'SUSPENDED')))
		  AND ($4 = '' OR left(ci.id::text, length($4)) = $4)
		ORDER BY ci.created_at, ci.id`, siteID, f.Status, f.Channel, prefix)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (CardInstanceSummary, error) {
		var c CardInstanceSummary
		err := row.Scan(&c.ID, &c.Status, &c.Origin, &c.Channels, &c.CreatedAt)
		return c, err
	})
}

// SetStatusTokenHash menyimpan SHA-256 token baca status untuk card instance (ADR-0037), menimpa
// yang lama.
func (t *Tx) SetStatusTokenHash(ctx context.Context, cardInstanceID string, hash []byte) error {
	if len(hash) != 32 {
		return ErrInvalidTokenHash
	}
	if !looksLikeUUID(cardInstanceID) {
		return ErrNotFound
	}
	tag, err := t.tx.Exec(ctx, `UPDATE card_instances SET status_token_hash = $2 WHERE id = $1`, cardInstanceID, hash)
	if err != nil {
		return err
	}
	if tag.RowsAffected() != 1 {
		return ErrNotFound
	}
	return nil
}

// InitStatusTokenHash memasang hash token baca status hanya bila instance belum punya (review akhir
// siklus hidup I1); penggantian hanya lewat perpanjangan bertanda tangan. Provisioning kini juga butuh
// rahasia enrolment (ADR-0040), tetapi aturan ini tetap mencegah penggantian lewat provisioning.
func (t *Tx) InitStatusTokenHash(ctx context.Context, cardInstanceID string, hash []byte) error {
	if len(hash) != 32 {
		return ErrInvalidTokenHash
	}
	_, err := t.tx.Exec(ctx, `UPDATE card_instances SET status_token_hash = $2 WHERE id = $1 AND status_token_hash IS NULL`, cardInstanceID, hash)
	return err
}

// SetProvisioningKeyHash memasang SHA-256 rahasia enrolment pada card instance (ADR-0040), menimpa
// yang lama. Dipanggil dalam transaksi enrolment untuk instance PROVISIONING atau PENDING_APPROVAL
// yang dikembalikan kepada perangkat itu (baru, dilanjutkan, atau dipromosikan).
func (t *Tx) SetProvisioningKeyHash(ctx context.Context, cardInstanceID string, hash []byte) error {
	if len(hash) != 32 {
		return ErrInvalidProvisioningHash
	}
	// Dijaga status (review akhir provisioning M1): enrolment ulang yang menunggu kunci tidak boleh
	// memasang hash pada instance yang sudah aktif selama menunggu.
	tag, err := t.tx.Exec(ctx, `UPDATE card_instances SET provisioning_key_hash = $2 WHERE id = $1 AND status IN ('PROVISIONING', 'PENDING_APPROVAL')`, cardInstanceID, hash)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 1 {
		return nil
	}
	var status string
	if err := t.tx.QueryRow(ctx, `SELECT status FROM card_instances WHERE id = $1`, cardInstanceID).Scan(&status); errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	} else if err != nil {
		return err
	}
	return ErrDuplicateEnrollment
}

// PurgeDenylist membuang baris denylist yang sertifikatnya sudah habis sebelum batas waktu, sehingga
// denylist tetap terbatas (SDD §8.1).
func (s *Store) PurgeDenylist(ctx context.Context, before time.Time) (int64, error) {
	tag, err := s.pool.Exec(ctx, `DELETE FROM denylist_entries WHERE expires_at < $1`, before)
	return tag.RowsAffected(), err
}

// LockInstanceOfCredential mengunci card instance milik kredensial sebelum baris kredensial dikunci,
// agar perpanjangan memakai urutan kunci yang sama dengan transisi operator dan hapus kartu (instance,
// lalu kredensial; review akhir siklus hidup M1). Kredensial tak dikenal tidak dianggap galat di sini.
func (t *Tx) LockInstanceOfCredential(ctx context.Context, credID []byte) error {
	_, err := t.tx.Exec(ctx, `
		SELECT ci.id FROM card_instances ci JOIN credentials c ON c.card_instance_id = ci.id
		WHERE c.cred_id = $1 FOR UPDATE OF ci`, credID)
	return err
}

// InTx menjalankan fn dalam satu transaksi; galat dari fn membatalkan semuanya.
func (s *Store) InTx(ctx context.Context, fn func(tx *Tx) error) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		t := &Tx{tx: tx}
		if err := fn(t); err != nil {
			return err
		}
		return t.checkFlushed()
	})
}

// CardStatusByToken mengembalikan status card instance bila hash token cocok (ADR-0037). Id tak dikenal,
// instance tanpa token, dan token salah sama-sama ErrNotFound.
func (s *Store) CardStatusByToken(ctx context.Context, cardInstanceID string, tokenHash []byte) (string, error) {
	if !looksLikeUUID(cardInstanceID) || len(tokenHash) != 32 {
		return "", ErrNotFound
	}
	var status string
	var stored []byte
	err := s.pool.QueryRow(ctx, `SELECT status, status_token_hash FROM card_instances WHERE id = $1`, cardInstanceID).Scan(&status, &stored)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	if err != nil {
		return "", err
	}
	if len(stored) != 32 || subtle.ConstantTimeCompare(stored, tokenHash) != 1 {
		return "", ErrNotFound
	}
	return status, nil
}
