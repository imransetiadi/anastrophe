package enroll

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/anp1"
	"github.com/imransetiadi/anastrophe/backend/internal/httpapi"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
)

// revokeDomain memisahkan pesan hapus kartu dari perpanjangan dan transcript ANP/1.
var revokeDomain = []byte("ANP1-REVOKE")

// RevokeMessage = "ANP1-REVOKE" ‖ cred_id ‖ nonce ‖ UTF-8 card_instance_id huruf kecil (ADR-0026).
func RevokeMessage(credID, nonce []byte, cardID string) []byte {
	msg := make([]byte, 0, len(revokeDomain)+len(credID)+len(nonce)+len(cardID))
	msg = append(append(append(msg, revokeDomain...), credID...), nonce...)
	return append(msg, strings.ToLower(cardID)...)
}

// deleteCard: DELETE /v1/cards/{id} dengan bukti kepemilikan kunci kredensial (FR-31, ADR-0026).
func (h *Handler) deleteCard(w http.ResponseWriter, r *http.Request) {
	key := r.Header.Get("Idempotency-Key")
	if !validIdempotencyKey(key) {
		httpapi.WriteProblem(w, problem("REQ-IDEMPOTENCY-KEY", http.StatusBadRequest))
		return
	}
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	var raw struct {
		CredentialID string `json:"credential_id"`
		Nonce        string `json:"nonce"`
		Signature    string `json:"signature"`
	}
	if err := json.Unmarshal(body, &raw); err != nil {
		httpapi.WriteProblem(w, problem("REQ-INVALID", http.StatusBadRequest))
		return
	}
	credID, err1 := base64.StdEncoding.DecodeString(raw.CredentialID)
	nonce, err2 := base64.StdEncoding.DecodeString(raw.Nonce)
	sig, err3 := base64.StdEncoding.DecodeString(raw.Signature)
	if err1 != nil || err2 != nil || err3 != nil || len(credID) != 16 || len(nonce) != 32 || len(sig) != 64 {
		httpapi.WriteProblem(w, problem("REQ-INVALID", http.StatusBadRequest))
		return
	}
	cardID := strings.ToLower(r.PathValue("id"))
	hash := sha256.Sum256([]byte(r.URL.Path + "\n" + raw.CredentialID + "\n" + raw.Nonce + "\n" + raw.Signature))
	status, resp, err := h.Store.Idempotent(r.Context(), key, hash[:], func(ctx context.Context, tx *store.Tx) (int, []byte, error) {
		return h.revokeCard(ctx, tx, cardID, credID, nonce, sig)
	})
	h.writeResult(w, status, resp, err, "delete card failed")
}

// revokeCard memeriksa berurutan dalam satu transaksi; jalur gagal tidak menulis apa pun.
func (h *Handler) revokeCard(ctx context.Context, tx *store.Tx, cardID string, credID, nonce, sig []byte) (int, []byte, error) {
	card, err := tx.EnrollmentForUpdate(ctx, cardID)
	if errors.Is(err, store.ErrNotFound) {
		return problemBody("CARD-NOT-FOUND", http.StatusNotFound)
	}
	if err != nil {
		return 0, nil, err
	}
	if card.Status != "ACTIVE" {
		return problemBody("CARD-NOT-REMOVABLE", http.StatusConflict)
	}
	cred, err := tx.CredentialForRenewal(ctx, credID)
	if errors.Is(err, store.ErrNotFound) {
		return problemBody("CRED-PROOF-INVALID", http.StatusBadRequest)
	}
	if err != nil {
		return 0, nil, err
	}
	if cred.Site.ID != card.ID || cred.Status != "ACTIVE" {
		return problemBody("CRED-PROOF-INVALID", http.StatusBadRequest)
	}
	now := h.Now().UTC().Truncate(time.Second)
	valid, err := tx.RenewalChallengeValid(ctx, cred.ID, nonce, now)
	if err != nil {
		return 0, nil, err
	}
	if !valid {
		return problemBody("CRED-CHALLENGE-INVALID", http.StatusBadRequest)
	}
	pub, err := anp1.ParsePublicKey(cred.PubKey)
	if err != nil {
		return 0, nil, err
	}
	if !anp1.VerifyRaw(pub, RevokeMessage(cred.CredID, nonce, card.ID), sig) {
		return problemBody("CRED-PROOF-INVALID", http.StatusBadRequest)
	}
	revoked, err := tx.RevokeCard(ctx, card.ID, nonce, "user_deleted", now)
	if err != nil {
		return 0, nil, err
	}
	for _, c := range revoked {
		if err := tx.AppendAudit(ctx, store.AuditEvent{
			SiteID: card.SiteID, Actor: "device:" + card.DeviceID, Action: "credential.revoked",
			Subject: "credential:" + hex.EncodeToString(c.CredID),
			Data:    map[string]any{"channel": c.Channel, "reason": "user_deleted"},
			At:      now,
		}); err != nil {
			return 0, nil, err
		}
	}
	return http.StatusNoContent, nil, nil
}
