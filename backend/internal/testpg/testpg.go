// Package testpg menyalakan PostgreSQL 16 sementara untuk test (initdb + pg_ctl).
// Hanya dipakai oleh test; tidak pernah ditautkan ke biner produksi.
package testpg

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
)

// ErrUnavailable: biner PostgreSQL tidak ada; test yang butuh database dilewati.
var ErrUnavailable = errors.New("testpg: PostgreSQL tidak tersedia")

// Start menyalakan server dan mengembalikan DSN admin serta fungsi penghenti.
func Start() (string, func(), error) {
	initdb, err1 := exec.LookPath("initdb")
	pgctl, err2 := exec.LookPath("pg_ctl")
	if err1 != nil || err2 != nil || os.Geteuid() == 0 { // initdb menolak berjalan sebagai root
		return "", func() {}, ErrUnavailable
	}
	if out, err := exec.Command(pgctl, "--version").Output(); err == nil && !atLeastMajor(string(out), 16) {
		return "", func() {}, fmt.Errorf("%w: butuh PostgreSQL ≥ 16, ditemukan %q", ErrUnavailable, strings.TrimSpace(string(out)))
	}
	var lastErr error
	for attempt := 0; attempt < 3; attempt++ { // port bisa direbut proses lain di antara pilih & start
		dsn, stop, err := start(initdb, pgctl)
		if err == nil {
			return dsn, stop, nil
		}
		lastErr = err
	}
	return "", func() {}, lastErr
}

// atLeastMajor membaca mis. "pg_ctl (PostgreSQL) 16.14 (Homebrew)". Versi yang tidak bisa
// dibaca dianggap memenuhi: lebih baik test berjalan daripada dilewati diam-diam.
func atLeastMajor(version string, major int) bool {
	m := regexp.MustCompile(`\(PostgreSQL\)\s+(\d+)`).FindStringSubmatch(version)
	if m == nil {
		return true
	}
	got, err := strconv.Atoi(m[1])
	return err != nil || got >= major
}

// Skip melewati test bila PostgreSQL tidak tersedia, atau menggagalkannya bila
// ANASTROPHE_REQUIRE_PG=1 (CI) agar tidak ada test database yang hilang diam-diam.
func Skip(t interface {
	Helper()
	Skip(...any)
	Fatal(...any)
}, reason string) {
	t.Helper()
	if os.Getenv("ANASTROPHE_REQUIRE_PG") == "1" {
		t.Fatal("PostgreSQL wajib (ANASTROPHE_REQUIRE_PG=1): " + reason)
	}
	t.Skip(reason)
}

func start(initdb, pgctl string) (string, func(), error) {
	dir, err := os.MkdirTemp("", "anastrophe-pg-")
	if err != nil {
		return "", func() {}, err
	}
	data := filepath.Join(dir, "data")
	if out, err := exec.Command(initdb, "-D", data, "-U", "postgres", "--auth=trust", "-E", "UTF8").CombinedOutput(); err != nil {
		os.RemoveAll(dir)
		return "", func() {}, fmt.Errorf("initdb: %v: %s", err, out)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		os.RemoveAll(dir)
		return "", func() {}, err
	}
	port := listener.Addr().(*net.TCPAddr).Port
	listener.Close()
	opts := fmt.Sprintf("-p %d -c listen_addresses=127.0.0.1 -c unix_socket_directories='' -c fsync=off", port)
	if out, err := exec.Command(pgctl, "-D", data, "-o", opts, "-l", filepath.Join(dir, "pg.log"), "-w", "start").CombinedOutput(); err != nil {
		os.RemoveAll(dir)
		return "", func() {}, fmt.Errorf("pg_ctl start: %v: %s", err, out)
	}
	stop := func() {
		exec.Command(pgctl, "-D", data, "-m", "immediate", "stop").Run()
		os.RemoveAll(dir)
	}
	return fmt.Sprintf("postgres://postgres@127.0.0.1:%d/postgres?sslmode=disable", port), stop, nil
}

// NewDatabase membuat database kosong baru dan mengembalikan DSN-nya.
func NewDatabase(ctx context.Context, adminDSN string) (string, error) {
	conn, err := pgx.Connect(ctx, adminDSN)
	if err != nil {
		return "", err
	}
	defer conn.Close(ctx)
	b := make([]byte, 6)
	_, _ = rand.Read(b)
	name := "t_" + hex.EncodeToString(b)
	if _, err := conn.Exec(ctx, "CREATE DATABASE "+name); err != nil {
		return "", err
	}
	return strings.Replace(adminDSN, "/postgres?", "/"+name+"?", 1), nil
}
