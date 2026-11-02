package loadtest

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
)

// Client menjalankan skenario uji beban terhadap satu API. Rahasia enrolment dan kunci kredensial hanya hidup
// di memori dan tidak pernah ditulis ke laporan.
type Client struct {
	Base     string
	HTTP     *http.Client
	SiteID   string
	JoinCode string
	Cards    *CardPool
	Creds    *CredPool
}

var (
	errCardsExhausted = fmt.Errorf("pool kartu sintetis habis: %w", ErrStop)
	errNoCredentials  = errors.New("pool kredensial kosong; jalankan enrol lebih dulu")
)

// Config: GET /v1/config.
func (c *Client) Config(ctx context.Context, rec *Recorder) error {
	_, err := rec.Measure(ctx, "config", func(ctx context.Context) (int, error) {
		return c.do(ctx, http.MethodGet, "/v1/config", nil, nil, nil, http.StatusOK)
	})
	return err
}

// Lookup: GET /v1/sites/lookup?code=<kode gedung>.
func (c *Client) Lookup(ctx context.Context, rec *Recorder) error {
	_, err := rec.Measure(ctx, "lookup", func(ctx context.Context) (int, error) {
		return c.do(ctx, http.MethodGet, "/v1/sites/lookup?code="+url.QueryEscape(c.JoinCode), nil, nil, nil, http.StatusOK)
	})
	return err
}

// Enrol: enrolment kartu sintetis berikutnya dengan device id baru dan rahasia enrolment (ADR-0040), lalu
// provisioning kanal BLE dengan kunci P-256 baru. Kredensial yang terbit masuk pool untuk Renew.
func (c *Client) Enrol(ctx context.Context, rec *Recorder) error {
	card, ok := c.Cards.Next()
	if !ok {
		rec.Observe("enrol.kartu_habis", 0, 0, errCardsExhausted)
		return errCardsExhausted
	}
	secret := randomBytes(32)
	hash := sha256.Sum256(secret)
	body := map[string]any{
		"device_id":             newUUID(),
		"site_id":               c.SiteID,
		"card":                  map[string]string{"tech": "iso14443a", "id": card},
		"provisioning_key_hash": base64.StdEncoding.EncodeToString(hash[:]),
	}
	var enrolled struct {
		EnrollmentID string `json:"enrollment_id"`
		Status       string `json:"status"`
	}
	if _, err := rec.Measure(ctx, "enrol.enrolment", func(ctx context.Context) (int, error) {
		status, err := c.do(ctx, http.MethodPost, "/v1/enrollments", body, nil, &enrolled, http.StatusCreated, http.StatusOK)
		if err == nil && enrolled.Status != "PROVISIONING" {
			// Kartu yang sudah dipakai perangkat lain menjadi PENDING_APPROVAL (ADR-0032): bukan enrolment yang
			// bisa diprovisikan, jadi dihitung galat agar kartu terpakai tidak tertutupi.
			err = fmt.Errorf("status enrolment %s; kartu sudah dipakai?", enrolled.Status)
		}
		return status, err
	}); err != nil {
		return err
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return err
	}
	pub, err := key.PublicKey.ECDH()
	if err != nil {
		return err
	}
	headers := map[string]string{
		"Authorization":   "Bearer " + base64.RawURLEncoding.EncodeToString(secret),
		"Idempotency-Key": idempotencyKey(),
	}
	var provisioned struct {
		CredentialID []byte `json:"credential_id"`
	}
	if _, err := rec.Measure(ctx, "enrol.provisioning", func(ctx context.Context) (int, error) {
		return c.do(ctx, http.MethodPost, "/v1/enrollments/"+url.PathEscape(enrolled.EnrollmentID)+"/credentials",
			map[string]string{"channel": "ble", "public_key": base64.StdEncoding.EncodeToString(pub.Bytes())}, headers, &provisioned, http.StatusOK)
	}); err != nil {
		return err
	}
	c.Creds.Add(Credential{ID: provisioned.CredentialID, Key: key})
	return nil
}

// Renew: tantangan perpanjangan lalu perpanjangan bertanda tangan kunci kredensial (ADR-0023).
func (c *Client) Renew(ctx context.Context, rec *Recorder) error {
	cred, ok := c.Creds.Pick()
	if !ok {
		rec.Observe("renew.tanpa_kredensial", 0, 0, errNoCredentials)
		return errNoCredentials
	}
	path := "/v1/credentials/" + hex.EncodeToString(cred.ID)
	var challenge struct {
		Nonce []byte `json:"nonce"`
	}
	if _, err := rec.Measure(ctx, "renew.challenge", func(ctx context.Context) (int, error) {
		return c.do(ctx, http.MethodPost, path+":challenge", map[string]string{}, nil, &challenge, http.StatusCreated)
	}); err != nil {
		return err
	}
	signature, err := renewalSignature(cred.Key, cred.ID, challenge.Nonce)
	if err != nil {
		return err
	}
	_, err = rec.Measure(ctx, "renew.perpanjangan", func(ctx context.Context) (int, error) {
		return c.do(ctx, http.MethodPost, path+":renew", map[string]string{
			"nonce": base64.StdEncoding.EncodeToString(challenge.Nonce), "signature": base64.StdEncoding.EncodeToString(signature),
		}, map[string]string{"Idempotency-Key": idempotencyKey()}, nil, http.StatusOK)
	})
	return err
}

// do mengirim satu permintaan JSON dan memeriksa status. Body respons dibuang kecuali out diisi; isi respons
// tidak pernah masuk pesan galat (bisa memuat sertifikat atau id).
func (c *Client) do(ctx context.Context, method, path string, body any, headers map[string]string, out any, want ...int) (int, error) {
	var reader io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return 0, err
		}
		reader = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.Base+path, reader)
	if err != nil {
		return 0, err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return resp.StatusCode, err
	}
	if !slices.Contains(want, resp.StatusCode) {
		return resp.StatusCode, fmt.Errorf("status %d", resp.StatusCode)
	}
	if out != nil {
		if err := json.Unmarshal(raw, out); err != nil {
			return resp.StatusCode, errors.New("respons bukan JSON yang diharapkan")
		}
	}
	return resp.StatusCode, nil
}

// renewalSignature menandatangani "ANP1-RENEW" ‖ cred_id ‖ nonce dengan ECDSA P-256 (raw r‖s), sesuai
// enroll.RenewalMessage.
func renewalSignature(key *ecdsa.PrivateKey, credID, nonce []byte) ([]byte, error) {
	digest := sha256.Sum256(append(append([]byte("ANP1-RENEW"), credID...), nonce...))
	r, s, err := ecdsa.Sign(rand.Reader, key, digest[:])
	if err != nil {
		return nil, err
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return sig, nil
}

func randomBytes(n int) []byte {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return b
}

func idempotencyKey() string { return "lt-" + hex.EncodeToString(randomBytes(12)) }

// newUUID membuat UUID v4 acak untuk device id baru per enrolment.
func newUUID() string {
	b := randomBytes(16)
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
