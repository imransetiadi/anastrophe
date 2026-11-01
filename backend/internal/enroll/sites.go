package enroll

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"github.com/imransetiadi/anastrophe/backend/internal/httpapi"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
)

// lookupSite: GET /v1/sites/lookup?code=<kode gedung> (ADR-0044). Penghuni mengonfirmasi nama gedung
// sebelum menempelkan kartu fisik. Kode tak dikenal, tidak berbentuk sah, kosong, atau tidak ada
// semuanya dijawab 404 SITE-NOT-FOUND yang sama; hanya membaca, jadi tanpa audit.
func (h *Handler) lookupSite(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	site, err := h.Store.SiteByJoinCode(r.Context(), r.URL.Query().Get("code"))
	switch {
	case errors.Is(err, store.ErrNotFound):
		httpapi.WriteProblem(w, problem("SITE-NOT-FOUND", http.StatusNotFound))
	case err != nil:
		slog.Error("site lookup failed", "err_type", errorType(err))
		httpapi.WriteProblem(w, problem("INTERNAL", http.StatusInternalServerError))
	default:
		out, _ := json.Marshal(struct {
			SiteID string `json:"site_id"`
			Name   string `json:"name"`
		}{site.ID, site.Name})
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(out)
	}
}
