// Command anastrophe-audit memverifikasi rantai audit (FR-54, ADR-0024) sesuai permintaan
// operator: mencetak head tiap rantai sebagai baris JSON dan keluar dengan kode 1 bila ada
// rantai yang rusak.
//
//	ANASTROPHE_DATABASE_URL=postgres://… go -C backend run ./cmd/anastrophe-audit
//
// Pemotongan ekor tidak terdeteksi dari rantai saja; bandingkan head dengan log head per jam
// dari anastrophe-api (anchor parsial).
package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"

	"github.com/imransetiadi/anastrophe/backend/internal/store"
)

func main() {
	tampered, err := run(context.Background(), os.Stdout)
	if err != nil {
		fmt.Fprintln(os.Stderr, "anastrophe-audit:", err)
		os.Exit(2)
	}
	if tampered > 0 {
		os.Exit(1)
	}
}

func run(ctx context.Context, w io.Writer) (int, error) {
	dsn := os.Getenv("ANASTROPHE_DATABASE_URL")
	if dsn == "" {
		return 0, errors.New("ANASTROPHE_DATABASE_URL wajib diisi")
	}
	db, err := store.Open(ctx, dsn)
	if err != nil {
		return 0, err
	}
	defer db.Close()
	return verifyAll(ctx, db, w)
}

// verifyAll memverifikasi setiap rantai dan mengembalikan jumlah rantai yang rusak.
func verifyAll(ctx context.Context, db *store.Store, w io.Writer) (int, error) {
	heads, err := db.AuditHeads(ctx)
	if err != nil {
		return 0, err
	}
	enc := json.NewEncoder(w)
	tampered := 0
	for _, h := range heads {
		_, verr := db.VerifyAuditChain(ctx, h.Chain)
		if verr != nil && !errors.Is(verr, store.ErrAuditTampered) {
			return tampered, verr
		}
		ok := verr == nil
		if !ok {
			tampered++
		}
		if err := enc.Encode(map[string]any{"chain": h.Chain, "seq": h.Seq, "hash": hex.EncodeToString(h.Hash), "ok": ok}); err != nil {
			return tampered, err
		}
	}
	return tampered, nil
}
