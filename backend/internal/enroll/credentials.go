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
	Validity time.Duration // default ADR-0010: 7 hari; gedung bisa mengatur 1–30 hari
	// EnabledChannels = kanal yang diizinkan /v1/config (kill switch per kanal, FR-04).
	EnabledChannels []string
}

func (h *Handler) channelEnabled(channel string) bool {
	for _, c := range h.EnabledChannels {
		if c == channel {
			return true
		}
	}
	return false
}

func (h *Handler) Register(mux *http.ServeMux) {
	httpapi.Route(mux, http.MethodPost, "/v1/enrollments", h.createEnrollment)
	httpapi.Route(mux, http.MethodPost, "/v1/enrollments/{id}/credentials", h.issueCredential)
	httpapi.Route(mux, http.MethodPost, "/v1/credentials/{action}", h.credentialAction)
}

// validIdempotencyKey: klien mengirim UUID; batasi ke [A-Za-z0-9_-]{1,128} agar byte aneh
// (mis. non-UTF-8) tidak sampai ke PostgreSQL sebagai 500.
func validIdempotencyKey(key string) bool {
	if len(key) == 0 || len(key) > 128 {
		return false
	}
	for _, c := range key {
		if !(c == '-' || c == '_' || c >= '0' && c <= '9' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z') {
			return false
		}
	}
	return true
}

// readBody membaca body maksimal maxBody; lebih besar → 413, bukan dipotong diam-diam.
func readBody(w http.ResponseWriter, r *http.Request) ([]byte, bool) {
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxBody))
	var tooLarge *http.MaxBytesError
	switch {
	case errors.As(err, &tooLarge):
		httpapi.WriteProblem(w, problem("REQ-TOO-LARGE", http.StatusRequestEntityTooLarge))
		return nil, false
	case err != nil:
		httpapi.WriteProblem(w, problem("REQ-INVALID", http.StatusBadRequest))
		return nil, false
	}
	return body, true
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
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	if err := json.Unmarshal(body, &req); err != nil {
		httpapi.WriteProblem(w, problem("REQ-INVALID", http.StatusBadRequest))
		return
	}
	enroll := func(add func() (string, error)) (int, []byte, error) {
		id, err := add()
		var pgErr *pgconn.PgError
		switch {
		case errors.Is(err, store.ErrCardLimit):
			return problemBody("ENR-LIMIT", http.StatusConflict)
		case errors.Is(err, store.ErrNotFound), errors.As(err, &pgErr) && pgErr.Code == "23503":
			return problemBody("ENR-NOT-FOUND", http.StatusNotFound)
		case err != nil:
			return 0, nil, err
		}
		out, err := json.Marshal(map[string]string{"enrollment_id": id})
		return http.StatusCreated, out, err
	}
	// SDD §8.5: POST mutasi menerima Idempotency-Key; dengan key, ketuk ganda tidak memakan
	// dua jatah dari batas 8 kartu.
	var status int
	var resp []byte
	var err error
	if key := r.Header.Get("Idempotency-Key"); key != "" {
		if !validIdempotencyKey(key) {
			httpapi.WriteProblem(w, problem("REQ-IDEMPOTENCY-KEY", http.StatusBadRequest))
			return
		}
		hash := sha256.Sum256([]byte(r.URL.Path + "\n" + req.DeviceID + "\n" + req.SiteID))
		status, resp, err = h.Store.Idempotent(r.Context(), key, hash[:], func(ctx context.Context, tx *store.Tx) (int, []byte, error) {
			return enroll(func() (string, error) { return tx.AddCardInstance(ctx, req.DeviceID, req.SiteID) })
		})
	} else {
		status, resp, err = enroll(func() (string, error) { return h.Store.AddCardInstance(r.Context(), req.DeviceID, req.SiteID) })
	}
	h.writeResult(w, status, resp, err, "create enrollment failed")
}

// writeResult menulis hasil handler; error infrastruktur menjadi 500 tanpa detail.
func (h *Handler) writeResult(w http.ResponseWriter, status int, resp []byte, err error, logMessage string) {
	switch {
	case errors.Is(err, store.ErrIdempotencyConflict):
		httpapi.WriteProblem(w, problem("REQ-IDEMPOTENCY-CONFLICT", http.StatusUnprocessableEntity))
		return
	case err != nil:
		slog.Error(logMessage, "err_type", errorType(err))
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

func (h *Handler) issueCredential(w http.ResponseWriter, r *http.Request) {
	key := r.Header.Get("Idempotency-Key")
	if !validIdempotencyKey(key) {
		httpapi.WriteProblem(w, problem("REQ-IDEMPOTENCY-KEY", http.StatusBadRequest))
		return
	}
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	req, failure := parseCredentialRequest(body)
	if failure == nil && !h.channelEnabled(req.Channel) {
		p := problem("ENR-INVALID-CHANNEL", http.StatusBadRequest)
		failure = &p
	}
	if failure != nil {
		httpapi.WriteProblem(w, *failure)
		return
	}
	id := r.PathValue("id")
	// Hash atas isi yang sudah dinormalkan, bukan byte mentah: urutan kunci JSON dari klien
	// (mis. dictionary Swift) bisa berbeda antar-retry.
	hash := sha256.Sum256([]byte(r.URL.Path + "\n" + req.Channel + "\n" + base64.StdEncoding.EncodeToString(req.PublicKey)))
	status, resp, err := h.Store.Idempotent(r.Context(), key, hash[:], func(ctx context.Context, tx *store.Tx) (int, []byte, error) {
		return h.issue(ctx, tx, id, req)
	})
	h.writeResult(w, status, resp, err, "issue credential failed")
}

type provisioned struct {
	CredentialID []byte              `json:"credential_id"`
	Channel      string              `json:"channel"`
	Certificate  []byte              `json:"certificate"`
	NotBefore    string              `json:"not_before"`
	NotAfter     string              `json:"not_after"`
	SiteName     string              `json:"site_name"`
	Zones        []string            `json:"zones"`
	GroupKeys    map[string][][]byte `json:"group_keys"`
}

type credentialRequest struct {
	Channel   string
	PublicKey []byte
}

// parseCredentialRequest memvalidasi isi permintaan sebelum menyentuh database.
func parseCredentialRequest(body []byte) (credentialRequest, *httpapi.Problem) {
	var raw struct {
		Channel   string `json:"channel"`
		PublicKey string `json:"public_key"`
	}
	if err := json.Unmarshal(body, &raw); err != nil {
		p := problem("REQ-INVALID", http.StatusBadRequest)
		return credentialRequest{}, &p
	}
	if !supportedChannels[raw.Channel] {
		p := problem("ENR-INVALID-CHANNEL", http.StatusBadRequest)
		return credentialRequest{}, &p
	}
	pub, err := base64.StdEncoding.DecodeString(raw.PublicKey)
	if err != nil || len(pub) != 65 {
		p := problem("ENR-INVALID-KEY", http.StatusBadRequest)
		return credentialRequest{}, &p
	}
	if _, err := anp1.ParsePublicKey(pub); err != nil {
		p := problem("ENR-INVALID-KEY", http.StatusBadRequest)
		return credentialRequest{}, &p
	}
	return credentialRequest{Channel: raw.Channel, PublicKey: pub}, nil
}

// issue mengembalikan (status, body JSON); error hanya untuk kegagalan infrastruktur.
// Semua kerja berjalan di transaksi idempotency, sehingga gagal di tengah tidak menyisakan
// kredensial yatim.
func (h *Handler) issue(ctx context.Context, tx *store.Tx, enrollmentID string, req credentialRequest) (int, []byte, error) {
	pub := req.PublicKey
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
	notAfter := notBefore.Add(h.validity(enrollment.CertValidityDays))
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
		NotBefore: notBefore.Format(time.RFC3339), NotAfter: notAfter.Format(time.RFC3339), SiteName: enrollment.SiteName,
		Zones: enrollment.Zones, GroupKeys: groupKeys,
	})
	return http.StatusOK, out, err
}

// validity: masa berlaku dari kebijakan gedung (1–30 hari), atau default handler (ADR-0010).
func (h *Handler) validity(siteDays int) time.Duration {
	if siteDays > 0 {
		return time.Duration(siteDays) * 24 * time.Hour
	}
	return h.Validity
}

func problem(code string, status int) httpapi.Problem {
	return httpapi.NewProblem(code, status)
}

func problemBody(code string, status int) (int, []byte, error) {
	out, err := json.Marshal(problem(code, status))
	return status, out, err
}

// errorType mencatat jenis error tanpa isinya (bisa memuat data sensitif).
func errorType(err error) string {
	var pgErr *pgconn.PgError
	switch {
	case errors.Is(err, context.Canceled):
		return "canceled"
	case errors.Is(err, context.DeadlineExceeded):
		return "deadline"
	case errors.As(err, &pgErr):
		return "pg:" + pgErr.Code
	}
	return "other"
}
