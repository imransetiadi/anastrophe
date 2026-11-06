// Command anastrophe-api menjalankan REST /v1 Anastrophe.
//
// Variabel lingkungan:
//
//	ANASTROPHE_ADDR             alamat dengar (default :8080)
//	ANASTROPHE_DATABASE_URL     DSN PostgreSQL 16 (wajib)
//	ANASTROPHE_DEV_SOFTWARE_CA  "1" = Site CA perangkat lunak sementara (HANYA dev/lab;
//	                            produksi wajib KMS/HSM, belum diimplementasikan)
//	ANASTROPHE_METRICS_ADDR     alamat listener internal untuk GET /metrics (kosong = tidak dibuat;
//	                            jangan diekspos ke publik, ADR-0054)
//	ANASTROPHE_LOG_FORMAT       "json" untuk log terpusat; selain itu teks
package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/certs"
	"github.com/imransetiadi/anastrophe/backend/internal/enroll"
	"github.com/imransetiadi/anastrophe/backend/internal/httpapi"
	"github.com/imransetiadi/anastrophe/backend/internal/registry"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
)

func main() {
	if err := run(); err != nil {
		slog.Error("server stopped", "err", err)
		os.Exit(1)
	}
}

func run() error {
	logger := loggerFromEnv(os.Getenv, os.Stderr)
	slog.SetDefault(logger)
	ctx := context.Background()
	dsn := os.Getenv("ANASTROPHE_DATABASE_URL")
	if dsn == "" {
		return errors.New("ANASTROPHE_DATABASE_URL wajib diisi")
	}
	if os.Getenv("ANASTROPHE_DEV_SOFTWARE_CA") != "1" {
		return errors.New("Site CA KMS/HSM belum tersedia; set ANASTROPHE_DEV_SOFTWARE_CA=1 hanya untuk dev/lab")
	}
	registryMAC, err := registryFromEnv(os.Getenv)
	if err != nil {
		return err
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
		Registry:        registryMAC,
	}
	go func() {
		for range time.Tick(time.Hour) {
			if n, err := db.PurgeIdempotencyKeys(ctx, time.Now().Add(-24*time.Hour)); err != nil {
				slog.Error("purge idempotency keys failed")
			} else if n > 0 {
				slog.Info("purged idempotency keys", "count", n)
			}
			if n, err := db.AbandonStaleEnrollments(ctx, time.Now()); err != nil {
				slog.Error("abandon stale enrollments failed")
			} else if n > 0 {
				slog.Info("abandoned stale enrollments", "count", n) // ADR-0034
			}
			if n, err := db.PurgeRenewalChallenges(ctx, time.Now()); err != nil {
				slog.Error("purge renewal challenges failed")
			} else if n > 0 {
				slog.Info("purged renewal challenges", "count", n)
			}
			if n, err := db.PurgeDenylist(ctx, time.Now()); err != nil {
				slog.Error("purge denylist failed")
			} else if n > 0 {
				slog.Info("purged denylist", "count", n) // sertifikatnya sudah habis
			}
			logAuditHeads(ctx, db)
		}
	}()
	addr := os.Getenv("ANASTROPHE_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	metrics := httpapi.NewMetrics()
	server := newAPIServer(addr, httpapi.New(httpapi.Config{EnabledChannels: enabledChannels}, httpapi.Deps{Routes: handlers.Register, Logger: logger, Metrics: metrics}), logger)
	metricsServer := newMetricsServer(os.Getenv("ANASTROPHE_METRICS_ADDR"), metrics)
	// SIGTERM (deploy/failover ADR-0014): berhenti menerima permintaan baru dan tunggu
	// permintaan berjalan selesai, agar transaksi tidak terputus di tengah.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, os.Interrupt)
	errs := make(chan error, 1)
	go func() {
		slog.Info("listening", "addr", addr)
		errs <- server.ListenAndServe()
	}()
	if metricsServer != nil {
		go func() {
			slog.Info("metrics listening", "addr", metricsServer.Addr)
			if err := metricsServer.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
				errs <- err
			}
		}()
	}
	select {
	case err := <-errs:
		return err
	case <-stop:
		shutdownCtx, cancel := context.WithTimeout(context.Background(), httpapi.RequestTimeout+5*time.Second)
		defer cancel()
		// Server publik dulu dengan seluruh anggaran, agar transaksi berjalan tidak terputus dan drain tetap
		// teramati di /metrics; listener metrik menyusul dengan anggarannya sendiri (review akhir ADR-0054).
		err := server.Shutdown(shutdownCtx)
		if metricsServer != nil {
			metricsCtx, cancelMetrics := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancelMetrics()
			_ = metricsServer.Shutdown(metricsCtx)
		}
		return err
	}
}

// loggerFromEnv memilih format log (ANASTROPHE_LOG_FORMAT=json untuk log terpusat, selain itu teks; nilai
// tidak peka huruf besar/kecil dan spasi tepi diabaikan, minor review akhir ADR-0054) dan membungkusnya agar
// log dengan context permintaan membawa request_id.
func loggerFromEnv(getenv func(string) string, w io.Writer) *slog.Logger {
	var h slog.Handler = slog.NewTextHandler(w, nil)
	if strings.EqualFold(strings.TrimSpace(getenv("ANASTROPHE_LOG_FORMAT")), "json") {
		h = slog.NewJSONHandler(w, nil)
	}
	return slog.New(httpapi.WithRequestID(h))
}

// newAPIServer merakit http.Server publik. ErrorLog diarahkan ke logger app di level Warn (minor review
// akhir ADR-0054): bawaannya menulis ke os.Stderr lewat paket log standar, di luar format dan tujuan log
// terpusat yang sama dengan log akses, padahal galat net/http sendiri (mis. TLS handshake gagal) bisa memuat
// alamat IP klien.
func newAPIServer(addr string, handler http.Handler, logger *slog.Logger) *http.Server {
	return &http.Server{
		Addr:              addr,
		WriteTimeout:      httpapi.RequestTimeout + 5*time.Second,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ErrorLog:          slog.NewLogLogger(logger.Handler(), slog.LevelWarn),
	}
}

// newMetricsServer membuat listener internal yang hanya melayani GET /metrics; nil bila addr kosong.
func newMetricsServer(addr string, metrics *httpapi.Metrics) *http.Server {
	if addr == "" {
		return nil
	}
	mux := http.NewServeMux()
	mux.Handle("GET /metrics", metrics)
	// Timeout membatasi scraper yang lambat atau macet (review akhir ADR-0054).
	return &http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: time.Minute}
}

// logAuditHeads memverifikasi setiap rantai audit dan mencatat head-nya ke log terpusat sebagai
// anchor parsial (review audit I2): pemotongan ekor terlihat dari head yang mundur di log.
func logAuditHeads(ctx context.Context, db *store.Store) {
	heads, err := db.AuditHeads(ctx)
	if err != nil {
		slog.Error("audit heads failed")
		return
	}
	for _, h := range heads {
		if _, err := db.VerifyAuditChain(ctx, h.Chain); err != nil {
			slog.Error("audit chain tampered", "chain", h.Chain)
			continue
		}
		slog.Info("audit chain head", "chain", h.Chain, "seq", h.Seq, "hash", hex.EncodeToString(h.Hash))
	}
}

// registryFromEnv memberi kunci registri per gedung (ADR-0031). Produksi memakai KMS (belum
// tersedia); dev/lab memakai ANASTROPHE_DEV_REGISTRY_KEY (32 byte hex). Tanpa kunci, API tidak start.
func registryFromEnv(getenv func(string) string) (registry.MAC, error) {
	key := getenv("ANASTROPHE_DEV_REGISTRY_KEY")
	if key == "" {
		return nil, errors.New("ANASTROPHE_DEV_REGISTRY_KEY wajib diisi (32 byte hex; KMS registri belum tersedia)")
	}
	return registry.NewDevMAC(key)
}
