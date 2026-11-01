package store

import (
	"context"
	"crypto/rand"
	"errors"
	"strings"
	"time"
	"unicode"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// joinCodeAlphabet adalah Crockford base32 tanpa I, L, O, U (ADR-0044). Panjangnya 32, jadi 5 bit acak
// per simbol memberi sebaran merata.
const joinCodeAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

const joinCodeLength = 8

// SiteRef adalah gedung hasil pencarian kode gedung.
type SiteRef struct {
	ID   string
	Name string
}

// NormalizeJoinCode membaca kode yang diketik penghuni: huruf besar, "-" dan spasi dibuang, O dibaca 0,
// I dan L dibaca 1. Hasilnya harus tepat 8 simbol alfabet; aturan yang sama dipakai app (SiteJoinCode).
func NormalizeJoinCode(s string) (string, bool) {
	var b strings.Builder
	for _, r := range strings.ToUpper(s) {
		switch {
		case r == '-' || unicode.IsSpace(r):
			continue
		case r == 'O':
			r = '0'
		case r == 'I' || r == 'L':
			r = '1'
		}
		if !strings.ContainsRune(joinCodeAlphabet, r) || b.Len() == joinCodeLength {
			return "", false
		}
		b.WriteRune(r)
	}
	if b.Len() != joinCodeLength {
		return "", false
	}
	return b.String(), true
}

// FormatJoinCode menampilkan kode sebagai XXXX-XXXX agar mudah dibaca dan diketik.
func FormatJoinCode(code string) string {
	if len(code) != joinCodeLength {
		return code
	}
	return code[:4] + "-" + code[4:]
}

func newJoinCode() string {
	buf := make([]byte, joinCodeLength)
	_, _ = rand.Read(buf) // crypto/rand.Read tidak pernah gagal sejak Go 1.24
	for i, v := range buf {
		buf[i] = joinCodeAlphabet[v&31]
	}
	return string(buf)
}

// RotateSiteJoinCode membuat kode gedung baru dan menggantikan yang lama (kode lama langsung tidak
// berlaku), lalu mencatat audit site.join_code_rotated tanpa nilai kode. replaced bernilai true bila
// gedung sebelumnya sudah punya kode.
func (s *Store) RotateSiteJoinCode(ctx context.Context, siteID, operator string, at time.Time) (string, bool, error) {
	if !operatorName.MatchString(operator) {
		return "", false, ErrInvalidOperator
	}
	if !looksLikeUUID(siteID) {
		return "", false, ErrNotFound
	}
	for range 5 {
		code := newJoinCode()
		var replaced bool
		err := s.InTx(ctx, func(t *Tx) error {
			err := t.tx.QueryRow(ctx, `
				WITH old AS (SELECT id, join_code FROM sites WHERE id = $1 FOR UPDATE)
				UPDATE sites s SET join_code = $2 FROM old WHERE s.id = old.id
				RETURNING old.join_code IS NOT NULL`, siteID, code).Scan(&replaced)
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrNotFound
			}
			if err != nil {
				return err
			}
			return t.AppendAudit(ctx, AuditEvent{SiteID: siteID, Actor: "operator:" + operator, Action: "site.join_code_rotated", Subject: "site:" + siteID, At: at})
		})
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "sites_join_code_key" {
			continue // bentrok dengan kode gedung lain: coba kode baru
		}
		if err != nil {
			return "", false, err
		}
		return code, replaced, nil
	}
	return "", false, errors.New("store: gagal membuat kode gedung unik")
}

// SiteByJoinCode mencari gedung dari kode yang diketik penghuni. Kode tidak sah dan tak dikenal sama-sama
// ErrNotFound, sehingga endpoint lookup menjawab keduanya identik.
func (s *Store) SiteByJoinCode(ctx context.Context, code string) (SiteRef, error) {
	normalized, ok := NormalizeJoinCode(code)
	if !ok {
		return SiteRef{}, ErrNotFound
	}
	var ref SiteRef
	err := s.pool.QueryRow(ctx, `SELECT id::text, name FROM sites WHERE join_code = $1`, normalized).Scan(&ref.ID, &ref.Name)
	if errors.Is(err, pgx.ErrNoRows) {
		return SiteRef{}, ErrNotFound
	}
	return ref, err
}
