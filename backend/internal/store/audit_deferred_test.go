package store

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// fakeAuditTx implementasi minimal pgx.Tx untuk unit test murni (tanpa PostgreSQL hidup) atas
// withDeferredAudits (ADR-0051, ADR-0063). Hanya Exec yang benar-benar dipakai jalur ini
// (pg_advisory_xact_lock); method lain tidak terjangkau dan memanggil t.Fatal bila dipanggil.
type fakeAuditTx struct {
	pgx.Tx
	t       *testing.T
	execErr error
}

func (f *fakeAuditTx) Exec(ctx context.Context, sql string, arguments ...any) (pgconn.CommandTag, error) {
	return pgconn.CommandTag{}, f.execErr
}

func (f *fakeAuditTx) QueryRow(ctx context.Context, sql string, args ...any) pgx.Row {
	f.t.Fatal("QueryRow tidak boleh terjangkau: Exec (advisory lock) harus gagal lebih dulu")
	return nil
}

// TestWithDeferredAuditsGalatFnMenangAtasGalatFlush mem-pin kontrak yang sudah dinyatakan di
// komentar withDeferredAudits ("Galat fn didahulukan") tapi belum pernah diuji eksplisit
// (ADR-0051 review, dicatat ADR-0063): bila fn dan flushAudits sama-sama gagal, galat fn yang
// dikembalikan, bukan galat flush.
func TestWithDeferredAuditsGalatFnMenangAtasGalatFlush(t *testing.T) {
	flushErr := errors.New("flush gagal (DB turun)")
	fnErr := errors.New("fn gagal")
	tx := &Tx{tx: &fakeAuditTx{t: t, execErr: flushErr}}

	_, err := withDeferredAudits(context.Background(), tx, func() (int, error) {
		// fn menambah event audit tertahan sebelum gagal — flushAudits akan mencobanya dan gagal
		// di kunci advisory (fakeAuditTx.execErr), sebelum menyentuh data event itu sendiri.
		if err := tx.AppendAudit(context.Background(), AuditEvent{
			Actor: "device:d1", Action: "credential.provisioned", Subject: "credential:1", At: time.Now(),
		}); err != nil {
			t.Fatalf("AppendAudit saat deferring seharusnya tidak gagal: %v", err)
		}
		return 0, fnErr
	})

	if !errors.Is(err, fnErr) {
		t.Fatalf("galat = %v, ingin galat fn %v (bukan galat flush %v)", err, fnErr, flushErr)
	}
}

// TestWithDeferredAuditsFlushBerhasilMengembalikanHasilFn: jalur baseline (tanpa galat) tidak
// berubah — hasil dan galat berasal dari fn, bukan disembunyikan oleh flush yang berhasil.
func TestWithDeferredAuditsFlushBerhasilMengembalikanHasilFn(t *testing.T) {
	tx := &Tx{tx: &fakeAuditTx{t: t, execErr: nil}}

	r, err := withDeferredAudits(context.Background(), tx, func() (string, error) {
		return "ok", nil
	})
	if err != nil || r != "ok" {
		t.Fatalf("r=%q err=%v, ingin r=\"ok\" err=nil", r, err)
	}
}

// TestInTxMenolakAuditTertahanYangTidakDiFlush: guard ADR-0063 — bila fn memanggil deferAudits()
// langsung (bukan lewat withDeferredAudits) dan lupa flushAudits(), event tertahan tidak boleh
// hilang diam-diam saat transaksi commit; InTx mengembalikan errUnflushedAudits.
func TestInTxMenolakAuditTertahanYangTidakDiFlush(t *testing.T) {
	tx := &Tx{}
	tx.deferAudits()
	if err := tx.AppendAudit(context.Background(), AuditEvent{
		Actor: "device:d1", Action: "credential.provisioned", Subject: "credential:1", At: time.Now(),
	}); err != nil {
		t.Fatalf("AppendAudit saat deferring seharusnya tidak gagal: %v", err)
	}

	if err := tx.checkFlushed(); !errors.Is(err, errUnflushedAudits) {
		t.Fatalf("checkFlushed = %v, ingin errUnflushedAudits (deferring masih true, 1 event tertahan)", err)
	}
}

func TestCheckFlushedLulusBilaTidakAdaYangTertahan(t *testing.T) {
	if err := (&Tx{}).checkFlushed(); err != nil {
		t.Fatalf("checkFlushed = %v, ingin nil untuk Tx baru", err)
	}
}

// TestInTxMenegakkanGuardFlush: integrasi (PostgreSQL asli via freshStore) — membuktikan InTx
// benar-benar memanggil checkFlushed di jalur produksi (bukan cuma diuji berdiri sendiri di atas),
// dan transaksi dibatalkan (bukan commit diam-diam) saat fn lupa flush.
func TestInTxMenegakkanGuardFlush(t *testing.T) {
	s := freshStore(t)
	ctx := context.Background()

	err := s.InTx(ctx, func(tx *Tx) error {
		tx.deferAudits()
		return tx.AppendAudit(ctx, AuditEvent{
			Actor: "device:d1", Action: "credential.provisioned", Subject: "credential:1", At: time.Now(),
		})
	})
	if !errors.Is(err, errUnflushedAudits) {
		t.Fatalf("InTx = %v, ingin errUnflushedAudits", err)
	}
}
