// Package appattest memverifikasi attestation dan assertion App Attest di server (NFR-S03, ADR-0052),
// mengikuti langkah Apple "Validating apps that connect to your server" (E35, O-AA01, O-AA02).
// Paket ini belum dipakai endpoint; kebijakan dan penyimpanan kunci menyusul.
package appattest

import "errors"

// ErrInvalid dibungkus semua kegagalan verifikasi. Alasan rinci hanya untuk log (Error.Reason); klien
// kelak menerima jawaban seragam.
var ErrInvalid = errors.New("appattest: verifikasi gagal")

// Error membawa alasan singkat kegagalan ("format", "chain", "key", "nonce", "key_id", "rp_id",
// "counter", "aaguid", "credential_id", "category", "signature") dan penyebab teknisnya bila ada.
type Error struct {
	Reason string
	Err    error
}

func (e *Error) Error() string {
	if e.Err != nil {
		return "appattest: " + e.Reason + ": " + e.Err.Error()
	}
	return "appattest: " + e.Reason
}

// Unwrap selalu ErrInvalid, sehingga pemanggil cukup memeriksa errors.Is(err, ErrInvalid).
func (e *Error) Unwrap() error { return ErrInvalid }

func invalid(reason string, err error) error { return &Error{Reason: reason, Err: err} }
