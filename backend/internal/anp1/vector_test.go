package anp1

import (
	"bytes"
	"crypto/ecdh"
	"encoding/hex"
	"encoding/json"
	"os"
	"testing"
)

// Vector bersama TC-PROTO-01, dibuat oleh scripts/anp1/gen_vectors.py (implementasi independen).
type vector struct {
	GroupPriv     string `json:"group_priv"`
	GroupID       string `json:"group_id"`
	ReaderEphPriv string `json:"reader_eph_priv"`
	PhoneEphPriv  string `json:"phone_eph_priv"`
	CredPriv      string `json:"cred_priv"`
	TxnID         string `json:"txn_id"`
	CredID        string `json:"cred_id"`
	Counter       uint32 `json:"counter"`
	Certificate   string `json:"certificate"`
	SigR          string `json:"sig_r"`
	SigP          string `json:"sig_p"`
	Expected      struct {
		Transcript              string `json:"transcript"`
		KPR                     string `json:"k_pr"`
		KRP                     string `json:"k_rp"`
		IVBase                  string `json:"iv_base"`
		Auth1Plaintext          string `json:"auth1_plaintext"`
		Auth1Ciphertext         string `json:"auth1_ciphertext"`
		CertCiphertext          string `json:"cert_ciphertext"`
		ResultPlaintextGranted  string `json:"result_plaintext_granted"`
		ResultCiphertextGranted string `json:"result_ciphertext_granted"`
	} `json:"expected"`
}

func h(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func load(t *testing.T) vector {
	t.Helper()
	raw, err := os.ReadFile("../../../Packages/Tests/ANCryptoTests/Resources/anp1-v1.json")
	if err != nil {
		t.Fatal(err)
	}
	var v vector
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

func key(t *testing.T, scalar []byte) *ecdh.PrivateKey {
	t.Helper()
	k, err := ecdh.P256().NewPrivateKey(scalar)
	if err != nil {
		t.Fatal(err)
	}
	return k
}

func TestVectorTranscriptDanKunciSesi(t *testing.T) {
	v := load(t)
	reader, phone := key(t, h(t, v.ReaderEphPriv)), key(t, h(t, v.PhoneEphPriv))
	transcript := Transcript(h(t, v.GroupID), reader.PublicKey().Bytes(), phone.PublicKey().Bytes(), h(t, v.TxnID))
	if !bytes.Equal(transcript, h(t, v.Expected.Transcript)) {
		t.Fatal("transcript berbeda")
	}
	shared, err := phone.ECDH(reader.PublicKey())
	if err != nil {
		t.Fatal(err)
	}
	kPR, kRP, ivBase, err := DeriveKeys(shared, h(t, v.TxnID), h(t, v.GroupID))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(kPR, h(t, v.Expected.KPR)) || !bytes.Equal(kRP, h(t, v.Expected.KRP)) || !bytes.Equal(ivBase, h(t, v.Expected.IVBase)) {
		t.Fatal("kunci sesi berbeda")
	}
}

func TestVectorCiphertext(t *testing.T) {
	v := load(t)
	kPR, kRP, iv := h(t, v.Expected.KPR), h(t, v.Expected.KRP), h(t, v.Expected.IVBase)
	cases := []struct {
		name, plaintext, ciphertext string
		key                         []byte
		seq                         uint64
		aad                         []byte
	}{
		{"auth1", v.Expected.Auth1Plaintext, v.Expected.Auth1Ciphertext, kPR, 0, []byte{0x80, 0x12, 0, 0}},
		{"get_cert", v.Certificate, v.Expected.CertCiphertext, kPR, 1, []byte{0x80, 0x14, 0, 0}},
		{"result", v.Expected.ResultPlaintextGranted, v.Expected.ResultCiphertextGranted, kRP, 0, []byte{0x80, 0x16, 0, 0}},
	}
	for _, c := range cases {
		sealed, err := Seal(c.key, Nonce(iv, c.seq), h(t, c.plaintext), c.aad)
		if err != nil || !bytes.Equal(sealed, h(t, c.ciphertext)) {
			t.Fatalf("%s: ciphertext berbeda (err %v)", c.name, err)
		}
	}
}

func TestVectorTandaTangan(t *testing.T) {
	v := load(t)
	reader, phone := key(t, h(t, v.ReaderEphPriv)), key(t, h(t, v.PhoneEphPriv))
	transcript := Transcript(h(t, v.GroupID), reader.PublicKey().Bytes(), phone.PublicKey().Bytes(), h(t, v.TxnID))
	group, err := ParsePublicKey(key(t, h(t, v.GroupPriv)).PublicKey().Bytes())
	if err != nil {
		t.Fatal(err)
	}
	if !VerifyRaw(group, append([]byte("ANP1-R"), transcript...), h(t, v.SigR)) {
		t.Fatal("sig_r tidak valid")
	}
	cred, err := ParsePublicKey(key(t, h(t, v.CredPriv)).PublicKey().Bytes())
	if err != nil {
		t.Fatal(err)
	}
	if !VerifyRaw(cred, PhoneMessage(transcript, h(t, v.CredID), v.Counter), h(t, v.SigP)) {
		t.Fatal("sig_p tidak valid")
	}
	if VerifyRaw(cred, PhoneMessage(transcript, h(t, v.CredID), v.Counter+1), h(t, v.SigP)) {
		t.Fatal("sig_p diterima untuk counter yang salah")
	}
}
