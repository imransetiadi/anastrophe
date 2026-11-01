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
	"crypto/x509"
	"encoding/pem"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
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
	der, err := x509.MarshalPKIXPublicKey(devCA.Public())
	if err != nil {
		return err
	}
	slog.Warn("memakai Site CA perangkat lunak sementara; sertifikat tidak berlaku setelah restart",
		"site_ca_public_key_pem", string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der})))
	enabledChannels := []string{"ble"}
	handlers := &enroll.Handler{
		Store:           db,
		Signers:         func(string) (certs.Signer, error) { return devCA, nil },
		Now:             time.Now,
		Validity:        7 * 24 * time.Hour,
		EnabledChannels: enabledChannels,
	}
	go func() {
		for range time.Tick(time.Hour) {
			if n, err := db.PurgeIdempotencyKeys(ctx, time.Now().Add(-24*time.Hour)); err != nil {
				slog.Error("purge idempotency keys failed")
			} else if n > 0 {
				slog.Info("purged idempotency keys", "count", n)
			}
		}
	}()
	addr := os.Getenv("ANASTROPHE_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	server := &http.Server{
		Addr:              addr,
		WriteTimeout:      httpapi.RequestTimeout + 5*time.Second,
		Handler:           httpapi.New(httpapi.Config{EnabledChannels: enabledChannels}, httpapi.Deps{Routes: handlers.Register}),
		ReadHeaderTimeout: 5 * time.Second,
	}
	// SIGTERM (deploy/failover ADR-0014): berhenti menerima permintaan baru dan tunggu
	// permintaan berjalan selesai, agar transaksi tidak terputus di tengah.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, os.Interrupt)
	errs := make(chan error, 1)
	go func() {
		slog.Info("listening", "addr", addr)
		errs <- server.ListenAndServe()
	}()
	select {
	case err := <-errs:
		return err
	case <-stop:
		shutdownCtx, cancel := context.WithTimeout(context.Background(), httpapi.RequestTimeout+5*time.Second)
		defer cancel()
		return server.Shutdown(shutdownCtx)
	}
}
