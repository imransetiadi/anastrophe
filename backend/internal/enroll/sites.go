package enroll

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"slices"

	"github.com/imransetiadi/anastrophe/backend/internal/httpapi"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
)

// effectiveChannels: kanal yang boleh dipakai di gedung = kebijakan gedung ∩ kanal global /v1/config,
// dalam urutan kanal global (ADR-0049). Tanpa kebijakan kanal, semua kanal global. Tidak pernah nil, agar
// JSON-nya [] dan bukan null.
func (h *Handler) effectiveChannels(policy []string) []string {
	result := []string{}
	for _, c := range h.EnabledChannels {
		if policy == nil || slices.Contains(policy, c) {
			result = append(result, c)
		}
	}
	return result
}

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
			SiteID   string   `json:"site_id"`
			Name     string   `json:"name"`
			Channels []string `json:"channels"`
		}{site.ID, site.Name, h.effectiveChannels(site.Channels)})
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(out)
	}
}
