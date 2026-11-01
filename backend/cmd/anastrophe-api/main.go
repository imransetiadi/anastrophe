// Command anastrophe-api menjalankan REST /v1 Anastrophe.
//
// Variabel lingkungan:
//
//	ANASTROPHE_ADDR             alamat dengar (default :8080)
//	ANASTROPHE_DATABASE_URL     DSN PostgreSQL 16 (wajib)
//	ANASTROPHE_DEV_SOFTWARE_CA  "1" = Site CA perangkat lunak sementara (HANYA dev/lab;
//	                            produksi wajib KMS/HSM, belum diimplementasikan)
package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/certs"
	"github.com/imransetiadi/anastrophe/backend/internal/enroll"
	"github.com/imransetiadi/anastrophe/backend/internal/httpapi"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
)

func main() {
	if err := run(); err != nil {
		slog.Error("server stopped", "err", err)
		os.Exit(1)
	}
}

func run() error {
	ctx := context.Background()
	dsn := os.Getenv("ANASTROPHE_DATABASE_URL")
	if dsn == "" {
		return errors.New("ANASTROPHE_DATABASE_URL wajib diisi")
	}
	if os.Getenv("ANASTROPHE_DEV_SOFTWARE_CA") != "1" {
		return errors.New("Site CA KMS/HSM belum tersedia; set ANASTROPHE_DEV_SOFTWARE_CA=1 hanya untuk dev/lab")
	}
	db, err := store.Open(ctx, dsn)
	if err != nil {
		return err
	}
	defer db.Close()
	if err := db.Migrate(ctx); err != nil {
		return err
	}
	caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return err
	}
	devCA := certs.NewSoftwareSigner(caKey)
	slog.Warn("memakai Site CA perangkat lunak sementara; sertifikat tidak berlaku setelah restart")
	handlers := &enroll.Handler{
		Store:    db,
		Signers:  func(string) (certs.Signer, error) { return devCA, nil },
		Now:      time.Now,
		Validity: 7 * 24 * time.Hour,
	}
	addr := os.Getenv("ANASTROPHE_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	server := &http.Server{
		Addr:              addr,
		Handler:           httpapi.New(httpapi.Config{EnabledChannels: []string{"ble"}}, httpapi.Deps{Routes: handlers.Register}),
		ReadHeaderTimeout: 5 * time.Second,
	}
	slog.Info("listening", "addr", addr)
	return server.ListenAndServe()
}
