// Package enroll menangani enrolment dan provisioning kredensial (SDD §8.4.1, §8.5).
package enroll

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/anp1"
	"github.com/imransetiadi/anastrophe/backend/internal/certs"
	"github.com/imransetiadi/anastrophe/backend/internal/httpapi"
	"github.com/imransetiadi/anastrophe/backend/internal/registry"
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
	// Registry menghitung HMAC identitas kartu per gedung (ADR-0031); wajib untuk enrolment.
	Registry registry.MAC
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
	httpapi.Route(mux, http.MethodDelete, "/v1/cards/{id}", h.deleteCard)
	httpapi.Route(mux, http.MethodGet, "/v1/cards/{id}/status", h.cardStatus)
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

// createEnrollment memulai enrolment untuk kartu fisik yang terdaftar di registri gedung (FR-11, FR-13;
// ADR-0031) atau untuk undangan sekali pakai (FR-12; ADR-0033); tepat satu dari keduanya. Identitas kartu
// hanya dipakai untuk menghitung HMAC per gedung lalu dibuang, dan token undangan hanya dipakai dalam
// bentuk hash (CLAUDE.md aturan 6). Security code dan App Attest menyusul bersama akun (ADR-0032).
func (h *Handler) createEnrollment(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID string `json:"device_id"`
		SiteID   string `json:"site_id"`
		Card     *struct {
			Tech string `json:"tech"`
			ID   string `json:"id"`
		} `json:"card"`
		Invitation *string `json:"invitation"`
	}
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	if err := json.Unmarshal(body, &req); err != nil || (req.Card == nil) == (req.Invitation == nil) {
		httpapi.WriteProblem(w, problem("REQ-INVALID", http.StatusBadRequest))
		return
	}
	// requestKey masuk hash idempotency: HMAC kartu atau hash token, tidak pernah nilai mentah,
	// karena baris idempotency tersimpan di database (aturan 6).
	var requestKey string
	var inTx func(ctx context.Context, tx *store.Tx) (store.CardEnrollment, error)
	var direct func(ctx context.Context) (store.CardEnrollment, error)
	if req.Invitation != nil {
		tokenHash, err := store.InvitationTokenHash(*req.Invitation)
		if err != nil {
			httpapi.WriteProblem(w, problem("REQ-INVALID", http.StatusBadRequest))
			return
		}
		requestKey = "invitation:" + hex.EncodeToString(tokenHash)
		inTx = func(ctx context.Context, tx *store.Tx) (store.CardEnrollment, error) {
			return tx.EnrollInvitation(ctx, req.DeviceID, tokenHash, h.Now())
		}
		direct = func(ctx context.Context) (store.CardEnrollment, error) {
			return h.Store.EnrollInvitation(ctx, req.DeviceID, tokenHash, h.Now())
		}
	} else {
		identity, err := registry.ParseCardIdentity(req.Card.Tech, req.Card.ID)
		if err != nil {
			httpapi.WriteProblem(w, problem("REQ-INVALID", http.StatusBadRequest))
			return
		}
		// ID gedung dinormalisasi sekali sebelum MAC, agar impor dan enrolment selalu cocok apa pun
		// sumber MAC-nya (review registri minor 9).
		siteID := strings.ToLower(strings.TrimSpace(req.SiteID))
		// Dihitung di luar transaksi database: produksi memanggil KMS.
		cardHMAC, err := h.Registry.MAC(r.Context(), siteID, identity.MACInput())
		if err != nil {
			h.writeResult(w, 0, nil, err, "registry mac failed")
			return
		}
		requestKey = siteID + "\n" + hex.EncodeToString(cardHMAC)
		inTx = func(ctx context.Context, tx *store.Tx) (store.CardEnrollment, error) {
			return tx.EnrollCard(ctx, req.DeviceID, siteID, cardHMAC, h.Now())
		}
		direct = func(ctx context.Context) (store.CardEnrollment, error) {
			return h.Store.EnrollCard(ctx, req.DeviceID, siteID, cardHMAC, h.Now())
		}
	}
	enroll := func(result store.CardEnrollment, err error) (int, []byte, error) {
		var pgErr *pgconn.PgError
		switch {
		case errors.Is(err, store.ErrCardLimit):
			return problemBody("ENR-LIMIT", http.StatusConflict)
		case errors.Is(err, store.ErrDuplicateEnrollment):
			return problemBody("ENR-DUPLICATE", http.StatusConflict)
		case errors.Is(err, store.ErrSiteUnsupported):
			return problemBody("ENR-SITE-UNSUPPORTED", http.StatusNotFound)
		case errors.Is(err, store.ErrNotRegistered):
			return problemBody("ENR-NOT-REGISTERED", http.StatusNotFound)
		case errors.Is(err, store.ErrInvitationInvalid):
			// Tak dikenal, kedaluwarsa, dan terpakai dijawab identik (TC-ENR-08).
			return problemBody("ENR-INVITATION-INVALID", http.StatusNotFound)
		case errors.Is(err, store.ErrNotFound), errors.As(err, &pgErr) && pgErr.Code == "23503":
			return problemBody("ENR-NOT-FOUND", http.StatusNotFound)
		case err != nil:
			return 0, nil, err
		}
		out, err := json.Marshal(map[string]string{"enrollment_id": result.ID, "status": result.Status})
		if result.Resumed {
			return http.StatusOK, out, err // ADR-0034: instance yang belum selesai dilanjutkan
		}
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
		hash := sha256.Sum256([]byte(r.URL.Path + "\n" + req.DeviceID + "\n" + requestKey))
		status, resp, err = h.Store.Idempotent(r.Context(), key, hash[:], func(ctx context.Context, tx *store.Tx) (int, []byte, error) {
			return enroll(inTx(ctx, tx))
		})
	} else {
		status, resp, err = enroll(direct(r.Context()))
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
	material := r.URL.Path + "\n" + req.Channel + "\n" + base64.StdEncoding.EncodeToString(req.PublicKey)
	if req.StatusTokenHash != nil {
		// Hanya bila ada, agar hash permintaan klien lama tidak berubah (ADR-0037).
		material += "\n" + base64.StdEncoding.EncodeToString(req.StatusTokenHash)
	}
	hash := sha256.Sum256([]byte(material))
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
	// StatusTokenHash: SHA-256 token baca status dari app (ADR-0037), opsional untuk klien lama.
	StatusTokenHash []byte
}

// parseCredentialRequest memvalidasi isi permintaan sebelum menyentuh database.
func parseCredentialRequest(body []byte) (credentialRequest, *httpapi.Problem) {
	var raw struct {
		Channel         string  `json:"channel"`
		PublicKey       string  `json:"public_key"`
		StatusTokenHash *string `json:"status_token_hash"`
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
	tokenHash, ok := parseStatusTokenHash(raw.StatusTokenHash)
	if !ok {
		p := problem("REQ-INVALID", http.StatusBadRequest)
		return credentialRequest{}, &p
	}
	return credentialRequest{Channel: raw.Channel, PublicKey: pub, StatusTokenHash: tokenHash}, nil
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
	if enrollment.Status == "PENDING_APPROVAL" {
		return problemBody("ENR-PENDING-APPROVAL", http.StatusConflict) // ADR-0032: menunggu operator
	}
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
	if req.StatusTokenHash != nil {
		if err := tx.InitStatusTokenHash(ctx, enrollment.ID, req.StatusTokenHash); err != nil {
			return 0, nil, err
		}
	}
	if err := tx.AppendAudit(ctx, credentialAudit("credential.provisioned", enrollment, credID, req.Channel, notAfter, notBefore)); err != nil {
		return 0, nil, err
	}
	out, err := json.Marshal(provisioned{
		CredentialID: credID, Channel: req.Channel, Certificate: cert,
		NotBefore: notBefore.Format(time.RFC3339), NotAfter: notAfter.Format(time.RFC3339), SiteName: enrollment.SiteName,
		Zones: enrollment.Zones, GroupKeys: groupKeys,
	})
	return http.StatusOK, out, err
}

// credentialAudit: event kredensial tanpa data pribadi, hanya kanal dan masa berlaku (FR-54).
func credentialAudit(action string, site store.Enrollment, credID []byte, channel string, notAfter, at time.Time) store.AuditEvent {
	return store.AuditEvent{
		SiteID: site.SiteID, Actor: "device:" + site.DeviceID, Action: action,
		Subject: "credential:" + hex.EncodeToString(credID),
		Data:    map[string]any{"channel": channel, "not_after": notAfter.UTC().Format(time.RFC3339)},
		At:      at,
	}
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
