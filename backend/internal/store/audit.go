package store

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// AuditEvent adalah satu baris log audit (FR-54). SiteID kosong = rantai platform.
// Data tidak boleh memuat identitas kartu fisik mentah, kontak, atau lokasi (CLAUDE.md aturan 6).
type AuditEvent struct {
	SiteID  string
	Actor   string
	Action  string
	Subject string
	Data    map[string]any
	At      time.Time
}

// ErrAuditTampered: rantai audit tidak cocok dengan hash tersimpan.
var ErrAuditTampered = errors.New("store: rantai audit rusak")

// AuditTamperedError menunjuk seq pertama yang rusak (diubah, dihapus, atau disisipkan).
type AuditTamperedError struct {
	Chain string
	Seq   int64
}

func (e *AuditTamperedError) Error() string {
	return fmt.Sprintf("store: rantai audit %s rusak di seq %d", e.Chain, e.Seq)
}

func (e *AuditTamperedError) Unwrap() error { return ErrAuditTampered }

// AuditChain: satu rantai per gedung (ADR-0024), "platform" untuk event tanpa gedung.
func AuditChain(siteID string) string {
	if siteID == "" {
		return "platform"
	}
	return "site:" + siteID
}

// auditHash = SHA-256("ANP1-AUDIT" ‖ prev ‖ u64be(seq) ‖ field(chain) ‖ field(at) ‖ field(actor)
// ‖ field(action) ‖ field(subject) ‖ field(data)), field = u32be(len) ‖ byte.
func auditHash(prev []byte, seq int64, chain string, at time.Time, actor, action, subject string, data []byte) []byte {
	h := sha256.New()
	h.Write([]byte("ANP1-AUDIT"))
	h.Write(prev)
	var n [8]byte
	binary.BigEndian.PutUint64(n[:], uint64(seq))
	h.Write(n[:])
	for _, f := range [][]byte{[]byte(chain), []byte(at.UTC().Format(time.RFC3339Nano)), []byte(actor), []byte(action), []byte(subject), data} {
		var l [4]byte
		binary.BigEndian.PutUint32(l[:], uint32(len(f)))
		h.Write(l[:])
		h.Write(f)
	}
	return h.Sum(nil)
}

// canonicalAuditData: JSON ringkas dengan kunci terurut. Didekode ulang dengan UseNumber agar
// teks yang dibaca kembali dari jsonb menghasilkan byte yang sama saat diverifikasi.
func canonicalAuditData(raw []byte) ([]byte, error) {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var v map[string]any
	if err := dec.Decode(&v); err != nil {
		return nil, err
	}
	if v == nil {
		v = map[string]any{}
	}
	return json.Marshal(v)
}

// AppendAudit menambah event dalam transaksi pemanggil, sehingga audit dan perubahan bisnis
// ter-commit atau dibatalkan bersama. Penambahan diserialkan per rantai, bukan global.
func (t *Tx) AppendAudit(ctx context.Context, e AuditEvent) error {
	chain := AuditChain(e.SiteID)
	if _, err := t.tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, "audit:"+chain); err != nil {
		return err
	}
	var seq int64
	prev := make([]byte, 32)
	err := t.tx.QueryRow(ctx, `SELECT seq, hash FROM audit_events WHERE chain = $1 ORDER BY seq DESC LIMIT 1`, chain).Scan(&seq, &prev)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	raw, err := json.Marshal(e.Data)
	if err != nil {
		return err
	}
	data, err := canonicalAuditData(raw)
	if err != nil {
		return err
	}
	at := e.At.UTC().Truncate(time.Microsecond) // presisi timestamptz
	seq++
	var site any
	if e.SiteID != "" {
		site = e.SiteID
	}
	_, err = t.tx.Exec(ctx, `
		INSERT INTO audit_events (chain, site_id, seq, at, actor, action, subject, data, prev_hash, hash)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9, $10)`,
		chain, site, seq, at, e.Actor, e.Action, e.Subject, string(data), prev,
		auditHash(prev, seq, chain, at, e.Actor, e.Action, e.Subject, data))
	return err
}

// AppendAudit menambah event dalam transaksinya sendiri (event tanpa perubahan bisnis).
func (s *Store) AppendAudit(ctx context.Context, e AuditEvent) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if err := (&Tx{tx: tx}).AppendAudit(ctx, e); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// VerifyAuditChain menghitung ulang seluruh rantai dan mengembalikan jumlah baris yang valid.
// Penghapusan baris terakhir tidak terdeteksi tanpa anchoring eksternal (di luar cakupan).
func (s *Store) VerifyAuditChain(ctx context.Context, chain string) (int, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT seq, at, actor, action, subject, data::text, prev_hash, hash
		FROM audit_events WHERE chain = $1 ORDER BY seq`, chain)
	if err != nil {
		return 0, err
	}
	defer rows.Close()
	prev := make([]byte, 32)
	expected, valid := int64(1), 0
	for rows.Next() {
		var seq int64
		var at time.Time
		var actor, action, subject, rawData string
		var prevHash, hash []byte
		if err := rows.Scan(&seq, &at, &actor, &action, &subject, &rawData, &prevHash, &hash); err != nil {
			return valid, err
		}
		data, err := canonicalAuditData([]byte(rawData))
		if err != nil || seq != expected || !bytes.Equal(prevHash, prev) ||
			!bytes.Equal(hash, auditHash(prev, seq, chain, at, actor, action, subject, data)) {
			return valid, &AuditTamperedError{Chain: chain, Seq: expected}
		}
		prev, expected, valid = hash, expected+1, valid+1
	}
	return valid, rows.Err()
}

// AuditRecord adalah baris audit yang dibaca kembali (ekspor per gedung, verifikasi manual).
type AuditRecord struct {
	Seq     int64
	At      time.Time
	Actor   string
	Action  string
	Subject string
	Data    map[string]any
}

// AuditEvents membaca seluruh rantai berurutan seq.
func (s *Store) AuditEvents(ctx context.Context, chain string) ([]AuditRecord, error) {
	rows, err := s.pool.Query(ctx, `SELECT seq, at, actor, action, subject, data FROM audit_events WHERE chain = $1 ORDER BY seq`, chain)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []AuditRecord
	for rows.Next() {
		var r AuditRecord
		if err := rows.Scan(&r.Seq, &r.At, &r.Actor, &r.Action, &r.Subject, &r.Data); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}
