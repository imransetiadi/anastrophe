package store

import (
	"context"
	"errors"
	"fmt"
	"os"
	"testing"

	"github.com/imransetiadi/anastrophe/backend/internal/testpg"
)

var adminDSN string

// skipReason menjelaskan kenapa test database dilewati (dicetak, tidak diam-diam).
var skipReason = "PostgreSQL tidak tersedia"

func TestMain(m *testing.M) {
	dsn, stop, err := testpg.Start()
	if err != nil && !errors.Is(err, testpg.ErrUnavailable) {
		fmt.Println(err)
		os.Exit(1)
	}
	if err != nil {
		fmt.Println("test database dilewati:", err)
		skipReason = err.Error()
	}
	adminDSN = dsn
	code := m.Run()
	stop()
	os.Exit(code)
}

// freshStore membuat database baru per test lalu menjalankan migrasi.
func freshStore(t *testing.T) *Store {
	t.Helper()
	if adminDSN == "" {
		testpg.Skip(t, skipReason)
	}
	ctx := context.Background()
	dsn, err := testpg.NewDatabase(ctx, adminDSN)
	if err != nil {
		t.Fatal(err)
	}
	s, err := Open(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(s.Close)
	if err := s.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	return s
}
