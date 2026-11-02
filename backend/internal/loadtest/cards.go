package loadtest

import (
	"crypto/ecdsa"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"strings"
	"sync"
)

// syntheticPrefix adalah awalan UID 7 byte kartu sintetis uji beban ("LT"). Alat ini hanya memakai identitas
// buatannya sendiri, tidak pernah identitas kartu fisik nyata (aturan 1 dan 6).
const syntheticPrefix = "084c54"

// GenerateCards menulis CSV impor registri (tech,card_id,holder_contact,zones) berisi n kartu sintetis
// iso14443a: awalan 084c54 lalu nomor urut 4 byte mulai dari offset, tanpa kontak dan zona. Run yang berurutan
// memakai offset berbeda, karena kartu yang sudah dipakai membuat enrolment berikutnya PENDING_APPROVAL.
func GenerateCards(w io.Writer, n, offset int) error {
	cw := csv.NewWriter(w)
	if err := cw.Write([]string{"tech", "card_id", "holder_contact", "zones"}); err != nil {
		return err
	}
	for i := 0; i < n; i++ {
		if err := cw.Write([]string{"iso14443a", fmt.Sprintf("%s%08x", syntheticPrefix, offset+i), "", ""}); err != nil {
			return err
		}
	}
	cw.Flush()
	return cw.Error()
}

// CardPool membagikan kartu sintetis sekali pakai ke pekerja; aman dipakai bersamaan.
type CardPool struct {
	mu   sync.Mutex
	ids  []string
	next int
}

// LoadCards membaca CSV GenerateCards. Kartu yang bukan sintetis ditolak.
func LoadCards(r io.Reader) (*CardPool, error) {
	rows, err := csv.NewReader(r).ReadAll()
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 || strings.Join(rows[0], ",") != "tech,card_id,holder_contact,zones" {
		return nil, errors.New("header CSV harus: tech,card_id,holder_contact,zones")
	}
	pool := &CardPool{}
	for _, row := range rows[1:] {
		if len(row) != 4 || row[0] != "iso14443a" || !strings.HasPrefix(strings.ToLower(row[1]), syntheticPrefix) {
			return nil, errors.New("hanya kartu sintetis gen-cards yang boleh dipakai uji beban")
		}
		pool.ids = append(pool.ids, strings.ToLower(row[1]))
	}
	return pool, nil
}

// Next mengembalikan kartu berikutnya yang belum dipakai; false bila pool habis.
func (p *CardPool) Next() (string, bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.next >= len(p.ids) {
		return "", false
	}
	id := p.ids[p.next]
	p.next++
	return id, true
}

// Credential adalah kredensial hasil provisioning uji beban; kuncinya hanya di memori.
type Credential struct {
	ID  []byte
	Key *ecdsa.PrivateKey
}

// CredPool menyimpan kredensial untuk skenario perpanjangan, dipilih bergiliran; aman dipakai bersamaan.
type CredPool struct {
	mu    sync.Mutex
	creds []Credential
	next  int
}

// Add menambah kredensial ke pool.
func (p *CredPool) Add(c Credential) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.creds = append(p.creds, c)
}

// Pick memilih kredensial berikutnya secara bergiliran; false bila pool kosong.
func (p *CredPool) Pick() (Credential, bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.creds) == 0 {
		return Credential{}, false
	}
	c := p.creds[p.next%len(p.creds)]
	p.next++
	return c, true
}

// Len mengembalikan jumlah kredensial di pool.
func (p *CredPool) Len() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.creds)
}
