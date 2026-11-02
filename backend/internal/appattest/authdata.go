package appattest

import (
	"encoding/binary"
	"errors"
)

// authData adalah bagian authenticator data App Attest yang dipakai verifier. AAGUID dan CredentialID
// hanya ada di attestation; Category dan BundleVersion nil bila ekstensi tidak ada (I-17).
type authData struct {
	RPIDHash      []byte
	Flags         byte
	Counter       uint32
	AAGUID        []byte
	CredentialID  []byte
	Category      *uint32
	BundleVersion *string
}

// authDataHeaderLen: rpIdHash (32) + flags (1) + counter (4).
const authDataHeaderLen = 37

func parseAuthDataHeader(b []byte) (authData, []byte, error) {
	if len(b) < authDataHeaderLen {
		return authData{}, nil, invalid("format", errors.New("authData terlalu pendek"))
	}
	return authData{RPIDHash: b[:32], Flags: b[32], Counter: binary.BigEndian.Uint32(b[33:37])}, b[37:], nil
}

// parseAttestationAuthData mengurai header + aaguid (16) + panjang credentialId (2) + credentialId + kunci
// COSE (satu map CBOR) + peta ekstensi opsional. Byte flags tidak dipakai untuk menemukan bagian-bagian ini,
// karena Apple menulisnya tidak konsisten (0x40 dengan ekstensi, 0xC0; O-AA04, O-AA06, I-16).
func parseAttestationAuthData(b []byte) (authData, error) {
	a, rest, err := parseAuthDataHeader(b)
	if err != nil {
		return authData{}, err
	}
	if len(rest) < 18 {
		return authData{}, invalid("format", errors.New("authData tanpa data kredensial"))
	}
	a.AAGUID, rest = rest[:16], rest[16:]
	n := int(binary.BigEndian.Uint16(rest[:2]))
	rest = rest[2:]
	if n > len(rest) {
		return authData{}, invalid("format", errors.New("panjang credentialId melebihi authData"))
	}
	a.CredentialID, rest = rest[:n], rest[n:]
	cose, rest, err := cborPrefix(rest)
	if err != nil {
		return authData{}, invalid("format", err)
	}
	if _, ok := cose.(map[any]any); !ok {
		return authData{}, invalid("format", errors.New("kunci COSE bukan map"))
	}
	if err := a.parseExtensions(rest); err != nil {
		return authData{}, err
	}
	return a, nil
}

// parseAssertionAuthData mengurai header 37 byte + peta ekstensi opsional (O-AA06, I-16).
func parseAssertionAuthData(b []byte) (authData, error) {
	a, rest, err := parseAuthDataHeader(b)
	if err != nil {
		return authData{}, err
	}
	if err := a.parseExtensions(rest); err != nil {
		return authData{}, err
	}
	return a, nil
}

// parseExtensions: sisa kosong berarti tanpa ekstensi (I-17); selain itu harus tepat satu map CBOR. Kunci tak
// dikenal diabaikan; kategori validasi wajib 4 byte (uint32 little-endian, O-AA04) dan bundle version wajib teks.
func (a *authData) parseExtensions(rest []byte) error {
	if len(rest) == 0 {
		return nil
	}
	v, err := decodeCBOR(rest)
	if err != nil {
		return invalid("format", err)
	}
	m, ok := v.(map[any]any)
	if !ok {
		return invalid("format", errors.New("ekstensi authData bukan map"))
	}
	if raw, ok := m["apple_validation_category_01"]; ok {
		b, ok := raw.([]byte)
		if !ok || len(b) != 4 {
			return invalid("format", errors.New("kategori validasi bukan 4 byte"))
		}
		category := binary.LittleEndian.Uint32(b)
		a.Category = &category
	}
	if raw, ok := m["apple_bundle_version_01"]; ok {
		s, ok := raw.(string)
		if !ok {
			return invalid("format", errors.New("bundle version bukan teks"))
		}
		a.BundleVersion = &s
	}
	return nil
}
