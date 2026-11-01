// Command anastrophe-api menjalankan REST /v1 Anastrophe.
package main

import (
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/httpapi"
)

func main() {
	addr := os.Getenv("ANASTROPHE_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	handler := httpapi.New(httpapi.Config{EnabledChannels: []string{"ble"}}, httpapi.Deps{})
	server := &http.Server{Addr: addr, Handler: handler, ReadHeaderTimeout: 5 * time.Second}
	slog.Info("listening", "addr", addr)
	if err := server.ListenAndServe(); err != nil {
		slog.Error("server stopped", "err", err)
		os.Exit(1)
	}
}
