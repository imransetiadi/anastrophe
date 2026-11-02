package enroll

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/imransetiadi/anastrophe/backend/internal/httpapi"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
)

// parseHashField membaca field hash opsional (base64 dari SHA-256): status_token_hash (ADR-0037) dan
// provisioning_key_hash (ADR-0040). Field yang tidak ada → nil, true; ada tetapi bukan 32 byte → nil, false.
func parseHashField(field *string) ([]byte, bool) {
	if field == nil {
		return nil, true
	}
	hash, err := base64.StdEncoding.DecodeString(*field)
	if err != nil || len(hash) != 32 {
		return nil, false
	}
	return hash, true
}

// cardStatus: GET /v1/cards/{id}/status dengan token baca status sebagai bearer (ADR-0037). Semua
// kegagalan dijawab 404 CARD-NOT-FOUND yang sama, dan token tidak pernah dicatat.
func (h *Handler) cardStatus(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	notFound := func() { httpapi.WriteProblem(w, problem("CARD-NOT-FOUND", http.StatusNotFound)) }
	encoded, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok {
		notFound()
		return
	}
	token, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil || len(token) != 32 {
		notFound()
		return
	}
	hash := sha256.Sum256(token)
	status, err := h.Store.CardStatusByToken(r.Context(), r.PathValue("id"), hash[:])
	switch {
	case errors.Is(err, store.ErrNotFound):
		notFound()
	case err != nil:
		slog.ErrorContext(r.Context(), "card status failed", "err_type", errorType(err))
		httpapi.WriteProblem(w, problem("INTERNAL", http.StatusInternalServerError))
	default:
		out, _ := json.Marshal(struct {
			Status string `json:"status"`
		}{status})
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(out)
	}
}
