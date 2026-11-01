package store

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
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

// AuditChain: satu rantai per gedung (ADR-0024), "platform" untuk event tanpa gedung. UUID
// dinormalkan ke huruf kecil (bentuk kanonik PostgreSQL) agar satu gedung tidak punya dua rantai.
func AuditChain(siteID string) string {
	if siteID == "" {
		return "platform"
	}
	return "site:" + strings.ToLower(siteID)
}

// auditHashTag berversi: format input hash tidak boleh berubah tanpa tag baru.
const auditHashTag = "ANP1-AUDIT-v1"

// auditLockNamespace memisahkan kunci advisory audit dari kunci idempotency dan migrasi.
const auditLockNamespace int32 = 0x41554454 // "AUDT"

// auditHash = SHA-256("ANP1-AUDIT" ‖ prev ‖ u64be(seq) ‖ field(chain) ‖ field(at) ‖ field(actor)
// ‖ field(action) ‖ field(subject) ‖ field(data)), field = u32be(len) ‖ byte.
func auditHash(prev []byte, seq int64, chain string, at time.Time, actor, action, subject string, data []byte) []byte {
	h := sha256.New()
	h.Write([]byte(auditHashTag))
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

// AppendAudit menambah event dalam transaksi pemanggil, sehingga audit dan perubahan bisnis
// ter-commit atau dibatalkan bersama. Penambahan diserialkan per rantai, bukan global.
//
// Kontrak: transaksi READ COMMITTED (di REPEATABLE READ penambahan paralel gagal 23505); kunci
// audit diambil terakhir, setelah kunci idempotency dan kunci baris; satu rantai per transaksi
// (atau kunci rantai berurutan); jangan memegang FOR UPDATE pada baris sites sebelum memanggil,
// karena insert mengambil KEY SHARE pada sites lewat foreign key.
//
// Data yang di-hash adalah teks jsonb PostgreSQL (`jsonb::text`), sama persis dengan yang dibaca
// kembali saat verifikasi; pemeriksa eksternal memakai teks itu apa adanya.
func (t *Tx) AppendAudit(ctx context.Context, e AuditEvent) error {
	if e.At.IsZero() {
		return errors.New("store: waktu event audit kosong")
	}
	chain := AuditChain(e.SiteID)
	if _, err := t.tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1, hashtext($2))`, auditLockNamespace, chain); err != nil {
		return err
	}
	var seq int64
	var lastAt time.Time
	prev := make([]byte, 32)
	err := t.tx.QueryRow(ctx, `SELECT seq, hash, at FROM audit_events WHERE chain = $1 ORDER BY seq DESC LIMIT 1`, chain).Scan(&seq, &prev, &lastAt)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if e.Data == nil {
		e.Data = map[string]any{}
	}
	raw, err := json.Marshal(e.Data)
	if err != nil {
		return err
	}
	if bytes.Contains(raw, []byte(`\u0000`)) {
		return errors.New("store: data audit memuat NUL") // jsonb menolaknya; tolak lebih awal
	}
	var text string
	if err := t.tx.QueryRow(ctx, `SELECT $1::jsonb::text`, string(raw)).Scan(&text); err != nil {
		return err
	}
	data := []byte(text)
	at := e.At.UTC().Truncate(time.Microsecond) // presisi timestamptz
	// Waktu pemanggil diambil sebelum menunggu kunci, jadi bisa lebih awal dari baris sebelumnya;
	// urutan waktu sepanjang seq dijaga tidak mundur.
	if last := lastAt.UTC(); at.Before(last) {
		at = last
	}
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
// Yang terdeteksi: baris yang diubah, dihapus di tengah, atau disisipkan. Yang TIDAK terdeteksi
// tanpa anchoring eksternal: pemotongan ekor (baris terakhir atau seluruh rantai) dan penghitungan
// ulang hash oleh pemegang akses tulis; head per rantai dicatat berkala ke log terpusat sebagai
// anchor parsial (AuditHeads).
func (s *Store) VerifyAuditChain(ctx context.Context, chain string) (int, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT seq, at, actor, action, subject, data::text, prev_hash, hash, COALESCE(site_id::text, '')
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
		var actor, action, subject, data, siteID string
		var prevHash, hash []byte
		if err := rows.Scan(&seq, &at, &actor, &action, &subject, &data, &prevHash, &hash, &siteID); err != nil {
			return valid, err
		}
		if AuditChain(siteID) != chain || seq != expected || !bytes.Equal(prevHash, prev) ||
			!bytes.Equal(hash, auditHash(prev, seq, chain, at, actor, action, subject, []byte(data))) {
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

// AuditHead adalah baris terakhir sebuah rantai, dicatat berkala sebagai anchor parsial.
type AuditHead struct {
	Chain string
	Seq   int64
	Hash  []byte
}

// AuditHeads mengembalikan head setiap rantai.
func (s *Store) AuditHeads(ctx context.Context) ([]AuditHead, error) {
	rows, err := s.pool.Query(ctx, `SELECT DISTINCT ON (chain) chain, seq, hash FROM audit_events ORDER BY chain, seq DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []AuditHead
	for rows.Next() {
		var h AuditHead
		if err := rows.Scan(&h.Chain, &h.Seq, &h.Hash); err != nil {
			return nil, err
		}
		out = append(out, h)
	}
	return out, rows.Err()
}
