package enroll

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/anp1"
	"github.com/imransetiadi/anastrophe/backend/internal/certs"
	"github.com/imransetiadi/anastrophe/backend/internal/httpapi"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
)

// RenewalChallengeTTL: masa berlaku nonce perpanjangan (FR-45, ADR-0023).
const RenewalChallengeTTL = 120 * time.Second

// renewalDomain memisahkan pesan bukti kepemilikan dari transcript ANP/1.
var renewalDomain = []byte("ANP1-RENEW")

// RenewalMessage = "ANP1-RENEW" ‖ cred_id (16 B) ‖ nonce (32 B), ditandatangani kunci kredensial.
func RenewalMessage(credID, nonce []byte) []byte {
	msg := make([]byte, 0, len(renewalDomain)+len(credID)+len(nonce))
	return append(append(append(msg, renewalDomain...), credID...), nonce...)
}

// credentialAction memisahkan "<cred_id hex>:<aksi>". ServeMux tidak mendukung wildcard
// dengan akhiran ":aksi", jadi segmen path diurai di sini.
func (h *Handler) credentialAction(w http.ResponseWriter, r *http.Request) {
	ref, action, _ := strings.Cut(r.PathValue("action"), ":")
	switch action {
	case "challenge", "renew":
	default:
		httpapi.WriteProblem(w, problem("NOT-FOUND", http.StatusNotFound))
		return
	}
	credID, err := hex.DecodeString(ref)
	if err != nil || len(credID) != 16 || ref != strings.ToLower(ref) {
		httpapi.WriteProblem(w, problem("CRED-NOT-FOUND", http.StatusNotFound))
		return
	}
	if action == "challenge" {
		h.renewalChallenge(w, r, credID)
	} else {
		h.renewCredential(w, r, credID)
	}
}

func (h *Handler) renewalChallenge(w http.ResponseWriter, r *http.Request, credID []byte) {
	nonce := make([]byte, 32)
	if _, err := rand.Read(nonce); err != nil {
		httpapi.WriteProblem(w, problem("INTERNAL", http.StatusInternalServerError))
		return
	}
	expiresAt := h.Now().UTC().Add(RenewalChallengeTTL).Truncate(time.Second)
	cardID, err := h.Store.CreateRenewalChallenge(r.Context(), credID, nonce, expiresAt)
	switch {
	case errors.Is(err, store.ErrNotFound):
		httpapi.WriteProblem(w, problem("CRED-NOT-FOUND", http.StatusNotFound))
	case errors.Is(err, store.ErrGone):
		httpapi.WriteProblem(w, problem("CARD-GONE", http.StatusGone))
	case errors.Is(err, store.ErrNotRenewable):
		httpapi.WriteProblem(w, problem("CRED-NOT-RENEWABLE", http.StatusConflict))
	case err != nil:
		slog.Error("renewal challenge failed", "err_type", errorType(err))
		httpapi.WriteProblem(w, problem("INTERNAL", http.StatusInternalServerError))
	default:
		out, _ := json.Marshal(struct {
			Nonce          []byte `json:"nonce"`
			ExpiresAt      string `json:"expires_at"`
			CardInstanceID string `json:"card_instance_id"`
		}{nonce, expiresAt.Format(time.RFC3339), cardID})
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write(out)
	}
}

func (h *Handler) renewCredential(w http.ResponseWriter, r *http.Request, credID []byte) {
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
		Nonce     string `json:"nonce"`
		Signature string `json:"signature"`
	}
	nonce, errNonce := []byte(nil), error(nil)
	sig, errSig := []byte(nil), error(nil)
	if err := json.Unmarshal(body, &raw); err == nil {
		nonce, errNonce = base64.StdEncoding.DecodeString(raw.Nonce)
		sig, errSig = base64.StdEncoding.DecodeString(raw.Signature)
	} else {
		errNonce = err
	}
	if errNonce != nil || errSig != nil || len(nonce) != 32 || len(sig) != 64 {
		httpapi.WriteProblem(w, problem("REQ-INVALID", http.StatusBadRequest))
		return
	}
	hash := sha256.Sum256([]byte(r.URL.Path + "\n" + raw.Nonce + "\n" + raw.Signature))
	status, resp, err := h.Store.Idempotent(r.Context(), key, hash[:], func(ctx context.Context, tx *store.Tx) (int, []byte, error) {
		return h.renew(ctx, tx, credID, nonce, sig)
	})
	h.writeResult(w, status, resp, err, "renew credential failed")
}

// renew: urutan cek SDD §8.4.2 dalam satu transaksi. Jalur gagal tidak menulis apa pun,
// karena Idempotent meng-commit respons < 500.
func (h *Handler) renew(ctx context.Context, tx *store.Tx, credID, nonce, sig []byte) (int, []byte, error) {
	cred, err := tx.CredentialForRenewal(ctx, credID)
	if errors.Is(err, store.ErrNotFound) {
		return problemBody("CRED-NOT-FOUND", http.StatusNotFound)
	}
	if err != nil {
		return 0, nil, err
	}
	// Kill switch kanal (FR-04) juga menghentikan perpanjangan, bukan hanya penerbitan baru.
	if !cred.Renewable() || !h.channelEnabled(cred.Channel) {
		return problemBody("CRED-NOT-RENEWABLE", http.StatusConflict)
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
	if !anp1.VerifyRaw(pub, RenewalMessage(cred.CredID, nonce), sig) {
		return problemBody("CRED-PROOF-INVALID", http.StatusBadRequest)
	}
	signer, err := h.Signers(cred.Site.SiteID)
	if err != nil {
		return 0, nil, err
	}
	notAfter := now.Add(h.validity(cred.Site.CertValidityDays))
	cert, err := certs.Issue(signer, certs.Request{
		CredentialID: cred.CredID, SiteID: cred.Site.SiteCode, PublicKey: cred.PubKey,
		Zones: cred.Site.ZonesBitmap, Channel: cred.Channel, NotBefore: now, NotAfter: notAfter,
	})
	if err != nil {
		return 0, nil, err
	}
	if err := tx.CompleteRenewal(ctx, cred.ID, nonce, cert, notAfter, now); err != nil {
		return 0, nil, err
	}
	if err := tx.AppendAudit(ctx, credentialAudit("credential.renewed", cred.Site, cred.CredID, cred.Channel, notAfter, now)); err != nil {
		return 0, nil, err
	}
	groupKeys, err := tx.ReaderGroupKeys(ctx, cred.Site.SiteID)
	if err != nil {
		return 0, nil, err
	}
	out, err := json.Marshal(provisioned{
		CredentialID: cred.CredID, Channel: cred.Channel, Certificate: cert,
		NotBefore: now.Format(time.RFC3339), NotAfter: notAfter.Format(time.RFC3339),
		SiteName: cred.Site.SiteName, Zones: cred.Site.Zones, GroupKeys: groupKeys,
	})
	return http.StatusOK, out, err
}
