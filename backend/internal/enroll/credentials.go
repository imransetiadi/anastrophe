// Package enroll menangani enrolment dan provisioning kredensial (SDD §8.4.1, §8.5).
package enroll

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/anp1"
	"github.com/imransetiadi/anastrophe/backend/internal/certs"
	"github.com/imransetiadi/anastrophe/backend/internal/httpapi"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
	"github.com/jackc/pgx/v5/pgconn"
)

// SignerSource memberi penanda tangan Site CA per gedung (produksi: KMS/HSM).
type SignerSource func(siteID string) (certs.Signer, error)

type Handler struct {
	Store    *store.Store
	Signers  SignerSource
	Now      func() time.Time
	Validity time.Duration // default ADR-0010: 7 hari
}

func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/enrollments", h.createEnrollment)
	mux.HandleFunc("POST /v1/enrollments/{id}/credentials", h.issueCredential)
}

const maxBody = 4 << 10

var supportedChannels = map[string]bool{"ble": true, "nfcHCE": true}

// createEnrollment adalah pengganti sementara tracer bullet: enrolment produksi memakai
// identitas kartu fisik (HMAC registri), security code, dan App Attest (rencana berikutnya).
func (h *Handler) createEnrollment(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID string `json:"device_id"`
		SiteID   string `json:"site_id"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, maxBody)).Decode(&req); err != nil {
		httpapi.WriteProblem(w, problem("REQ-INVALID", http.StatusBadRequest))
		return
	}
	id, err := h.Store.AddCardInstance(r.Context(), req.DeviceID, req.SiteID)
	var pgErr *pgconn.PgError
	switch {
	case errors.Is(err, store.ErrCardLimit):
		httpapi.WriteProblem(w, problem("ENR-LIMIT", http.StatusConflict))
	case errors.Is(err, store.ErrNotFound), errors.As(err, &pgErr) && pgErr.Code == "23503":
		httpapi.WriteProblem(w, problem("ENR-NOT-FOUND", http.StatusNotFound))
	case err != nil:
		slog.Error("create enrollment failed", "err_type", errorType(err))
		httpapi.WriteProblem(w, problem("INTERNAL", http.StatusInternalServerError))
	default:
		httpapi.WriteJSON(w, http.StatusCreated, map[string]string{"enrollment_id": id})
	}
}

func (h *Handler) issueCredential(w http.ResponseWriter, r *http.Request) {
	key := r.Header.Get("Idempotency-Key")
	if key == "" || len(key) > 128 {
		httpapi.WriteProblem(w, problem("REQ-IDEMPOTENCY-KEY", http.StatusBadRequest))
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, maxBody))
	if err != nil {
		httpapi.WriteProblem(w, problem("REQ-INVALID", http.StatusBadRequest))
		return
	}
	id := r.PathValue("id")
	hash := sha256.Sum256(append([]byte(r.URL.Path+"\n"), body...))
	status, resp, err := h.Store.Idempotent(r.Context(), key, hash[:], func(ctx context.Context, tx *store.Tx) (int, []byte, error) {
		return h.issue(ctx, tx, id, body)
	})
	switch {
	case errors.Is(err, store.ErrIdempotencyConflict):
		httpapi.WriteProblem(w, problem("REQ-IDEMPOTENCY-CONFLICT", http.StatusUnprocessableEntity))
		return
	case err != nil:
		slog.Error("issue credential failed", "err_type", errorType(err))
		httpapi.WriteProblem(w, problem("INTERNAL", http.StatusInternalServerError))
		return
	}
	contentType := "application/json"
	if status >= 400 {
		contentType = "application/problem+json"
	}
	w.Header().Set("Content-Type", contentType)
	w.WriteHeader(status)
	_, _ = w.Write(resp)
}

type provisioned struct {
	CredentialID []byte              `json:"credential_id"`
	Channel      string              `json:"channel"`
	Certificate  []byte              `json:"certificate"`
	NotAfter     string              `json:"not_after"`
	SiteName     string              `json:"site_name"`
	Zones        []string            `json:"zones"`
	GroupKeys    map[string][][]byte `json:"group_keys"`
}

// issue mengembalikan (status, body JSON); error hanya untuk kegagalan infrastruktur.
// Semua kerja berjalan di transaksi idempotency, sehingga gagal di tengah tidak menyisakan
// kredensial yatim.
func (h *Handler) issue(ctx context.Context, tx *store.Tx, enrollmentID string, body []byte) (int, []byte, error) {
	var req struct {
		Channel   string `json:"channel"`
		PublicKey string `json:"public_key"`
	}
	if err := json.Unmarshal(body, &req); err != nil {
		return problemBody("REQ-INVALID", http.StatusBadRequest)
	}
	if !supportedChannels[req.Channel] {
		return problemBody("ENR-INVALID-CHANNEL", http.StatusBadRequest)
	}
	pub, err := base64.StdEncoding.DecodeString(req.PublicKey)
	if err != nil || len(pub) != 65 {
		return problemBody("ENR-INVALID-KEY", http.StatusBadRequest)
	}
	if _, err := anp1.ParsePublicKey(pub); err != nil {
		return problemBody("ENR-INVALID-KEY", http.StatusBadRequest)
	}
	enrollment, err := tx.EnrollmentForUpdate(ctx, enrollmentID)
	if errors.Is(err, store.ErrNotFound) {
		return problemBody("ENR-NOT-FOUND", http.StatusNotFound)
	}
	if err != nil {
		return 0, nil, err
	}
	// SDD §8.2: hanya kartu yang sedang diprovisikan (atau aktif untuk kanal baru) yang
	// boleh mendapat sertifikat.
	if enrollment.Status != "PROVISIONING" && enrollment.Status != "ACTIVE" {
		return problemBody("ENR-NOT-PROVISIONABLE", http.StatusConflict)
	}
	exists, err := tx.HasActiveCredential(ctx, enrollment.ID, req.Channel)
	if err != nil {
		return 0, nil, err
	}
	if exists {
		return problemBody("ENR-CHANNEL-EXISTS", http.StatusConflict)
	}
	signer, err := h.Signers(enrollment.SiteID)
	if err != nil {
		return 0, nil, err
	}
	groupKeys, err := tx.ReaderGroupKeys(ctx, enrollment.SiteID)
	if err != nil {
		return 0, nil, err
	}
	credID := make([]byte, 16)
	if _, err := rand.Read(credID); err != nil {
		return 0, nil, err
	}
	notBefore := h.Now().UTC().Truncate(time.Second)
	notAfter := notBefore.Add(h.Validity)
	cert, err := certs.Issue(signer, certs.Request{
		CredentialID: credID, SiteID: enrollment.SiteCode, PublicKey: pub,
		Zones: enrollment.ZonesBitmap, Channel: req.Channel, NotBefore: notBefore, NotAfter: notAfter,
	})
	if err != nil {
		return 0, nil, err
	}
	if err := tx.SaveCredential(ctx, store.Credential{
		CardInstanceID: enrollment.ID, Channel: req.Channel, CredID: credID, PubKey: pub, Cert: cert, NotAfter: notAfter,
	}); err != nil {
		return 0, nil, err
	}
	out, err := json.Marshal(provisioned{
		CredentialID: credID, Channel: req.Channel, Certificate: cert,
		NotAfter: notAfter.Format(time.RFC3339), SiteName: enrollment.SiteName,
		Zones: enrollment.Zones, GroupKeys: groupKeys,
	})
	return http.StatusOK, out, err
}

func problem(code string, status int) httpapi.Problem {
	return httpapi.Problem{Type: code, Title: http.StatusText(status), Status: status}
}

func problemBody(code string, status int) (int, []byte, error) {
	out, err := json.Marshal(problem(code, status))
	return status, out, err
}

// errorType mencatat jenis error tanpa isinya (bisa memuat data sensitif).
func errorType(err error) string {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return "pg:" + pgErr.Code
	}
	return "other"
}
