// Package registry menyiapkan identitas kartu fisik dan kontak pemegang untuk registri gedung
// (FR-11, FR-52). Nilai mentah hanya lewat di memori; yang disimpan hanyalah HMAC per gedung
// (CLAUDE.md aturan 6). Kartu fisik hanya bukti kepemilikan saat enrolment (ADR-0001).
package registry

import (
	"context"
	"crypto/hkdf"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
)

// Tech adalah teknologi kartu. Kodenya ikut di-MAC sehingga byte yang sama pada teknologi
// berbeda tidak bertabrakan.
type Tech uint8

const (
	TechISO14443A Tech = 1 // UID 4, 7, atau 10 B
	TechISO15693  Tech = 2 // UID 8 B
	TechFeliCa    Tech = 3 // IDm 8 B
	TechISO7816   Tech = 4 // ID aplikasi dari profil baca gedung (SELECT AID), 1–32 B
)

var (
	ErrInvalidIdentity = errors.New("registry: identitas kartu tidak valid")
	ErrInvalidContact  = errors.New("registry: kontak tidak valid")
)

var techNames = map[string]Tech{"iso14443a": TechISO14443A, "iso15693": TechISO15693, "felica": TechFeliCa, "iso7816": TechISO7816}

// CardIdentity adalah identitas kartu yang dibaca saat enrolment. Jangan dicatat atau disimpan.
type CardIdentity struct {
	Tech Tech
	ID   []byte
}

// ParseCardIdentity memvalidasi nama teknologi dan panjang identitas per teknologi.
func ParseCardIdentity(tech, idHex string) (CardIdentity, error) {
	t, ok := techNames[tech]
	if !ok {
		return CardIdentity{}, ErrInvalidIdentity
	}
	id, err := hex.DecodeString(idHex)
	if err != nil || !validLength(t, len(id)) {
		return CardIdentity{}, ErrInvalidIdentity
	}
	return CardIdentity{Tech: t, ID: id}, nil
}

func validLength(t Tech, n int) bool {
	switch t {
	case TechISO14443A:
		return n == 4 || n == 7 || n == 10
	case TechISO15693, TechFeliCa:
		return n == 8
	case TechISO7816:
		return n >= 1 && n <= 32
	}
	return false
}

// MACInput = "ANP1-CARD-v1" ‖ u8(kode teknologi) ‖ u8(panjang) ‖ id.
func (c CardIdentity) MACInput() []byte {
	out := append([]byte("ANP1-CARD-v1"), byte(c.Tech), byte(len(c.ID)))
	return append(out, c.ID...)
}

// NormalizeContact: email di-trim dan dijadikan huruf kecil; telepon menjadi "+" diikuti 8–15
// digit (E.164), dengan spasi, tanda hubung, titik, dan kurung dibuang.
func NormalizeContact(raw string) (string, error) {
	s := strings.TrimSpace(raw)
	if strings.Contains(s, "@") {
		s = strings.ToLower(s)
		local, domain, _ := strings.Cut(s, "@")
		if local == "" || domain == "" || strings.Contains(domain, "@") {
			return "", ErrInvalidContact
		}
		return s, nil
	}
	var b strings.Builder
	for i, r := range s {
		switch {
		case r == '+' && i == 0, r >= '0' && r <= '9':
			b.WriteRune(r)
		case r == ' ', r == '-', r == '.', r == '(', r == ')':
		default:
			return "", ErrInvalidContact
		}
	}
	phone := b.String()
	if digits := len(phone) - 1; !strings.HasPrefix(phone, "+") || digits < 8 || digits > 15 {
		return "", ErrInvalidContact
	}
	return phone, nil
}

// ContactMACInput = "ANP1-CONTACT-v1" ‖ kontak ternormalisasi.
func ContactMACInput(normalized string) []byte {
	return append([]byte("ANP1-CONTACT-v1"), normalized...)
}

// MAC menghitung HMAC-SHA256 dengan kunci registri milik gedung. Produksi memakai KMS sehingga
// kunci tidak pernah keluar (SDD §11).
type MAC interface {
	MAC(ctx context.Context, siteID string, msg []byte) ([]byte, error)
}

// DevMAC menurunkan kunci per gedung dari satu kunci master lokal dengan HKDF-SHA256. Hanya untuk
// pengembangan dan uji.
type DevMAC struct{ master []byte }

// NewDevMAC menerima kunci master 32 byte dalam hex.
func NewDevMAC(masterHex string) (*DevMAC, error) {
	master, err := hex.DecodeString(masterHex)
	if err != nil || len(master) != 32 {
		return nil, errors.New("registry: kunci master dev harus 32 byte hex")
	}
	return &DevMAC{master: master}, nil
}

// MAC memakai kunci HKDF-SHA256(master, salt kosong, "ANP1-REGISTRY-v1" ‖ UUID gedung huruf kecil).
func (d *DevMAC) MAC(_ context.Context, siteID string, msg []byte) ([]byte, error) {
	key, err := hkdf.Key(sha256.New, d.master, nil, "ANP1-REGISTRY-v1"+strings.ToLower(siteID), 32)
	if err != nil {
		return nil, err
	}
	m := hmac.New(sha256.New, key)
	m.Write(msg)
	return m.Sum(nil), nil
}
