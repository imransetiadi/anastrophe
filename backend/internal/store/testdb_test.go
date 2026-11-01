package store

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

var testDSN string

// TestMain menyalakan PostgreSQL 16 sementara (initdb + pg_ctl) untuk paket ini.
func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "anastrophe-pg-")
	if err != nil {
		fmt.Println("tmp:", err)
		os.Exit(1)
	}
	code := func() int {
		defer os.RemoveAll(dir)
		initdb, err1 := exec.LookPath("initdb")
		pgctl, err2 := exec.LookPath("pg_ctl")
		if err1 != nil || err2 != nil {
			fmt.Println("PostgreSQL tidak tersedia; test store dilewati")
			return m.Run()
		}
		data := filepath.Join(dir, "data")
		if out, err := exec.Command(initdb, "-D", data, "-U", "postgres", "--auth=trust", "-E", "UTF8").CombinedOutput(); err != nil {
			fmt.Printf("initdb: %v\n%s", err, out)
			return 1
		}
		listener, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			return 1
		}
		port := listener.Addr().(*net.TCPAddr).Port
		listener.Close()
		opts := fmt.Sprintf("-p %d -c listen_addresses=127.0.0.1 -c unix_socket_directories='' -c fsync=off", port)
		if out, err := exec.Command(pgctl, "-D", data, "-o", opts, "-l", filepath.Join(dir, "pg.log"), "-w", "start").CombinedOutput(); err != nil {
			fmt.Printf("pg_ctl start: %v\n%s", err, out)
			return 1
		}
		defer exec.Command(pgctl, "-D", data, "-m", "immediate", "stop").Run()
		testDSN = fmt.Sprintf("postgres://postgres@127.0.0.1:%d/postgres?sslmode=disable", port)
		return m.Run()
	}()
	os.Exit(code)
}

// freshStore membuat database baru per test lalu menjalankan migrasi.
func freshStore(t *testing.T) *Store {
	t.Helper()
	if testDSN == "" {
		t.Skip("PostgreSQL tidak tersedia")
	}
	ctx := context.Background()
	admin, err := Open(ctx, testDSN)
	if err != nil {
		t.Fatal(err)
	}
	defer admin.Close()
	name := fmt.Sprintf("t_%d", os.Getpid()) + "_" + randomHex(4)
	if _, err := admin.pool.Exec(ctx, "CREATE DATABASE "+name); err != nil {
		t.Fatal(err)
	}
	s, err := Open(ctx, testDSN[:len(testDSN)-len("postgres?sslmode=disable")]+name+"?sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(s.Close)
	if err := s.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	return s
}
