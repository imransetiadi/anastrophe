// Command anastrophe-devseed menyiapkan data lab (dev saja): organisasi, gedung dengan
// kebijakan zona, reader group, dan satu perangkat. Mencetak {"site_id","device_id"}.
//
//	go -C backend run ./cmd/anastrophe-devseed -lab-dir ../scripts/anp1/.lab
//
// Kunci publik reader group diambil dari site.json milik scripts/anp1/lab_ca.py (di-ignore
// git) agar reader lab memakai kunci yang sama; tanpa -lab-dir dibuat kunci baru.
package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/imransetiadi/anastrophe/backend/internal/store"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "devseed:", err)
		os.Exit(1)
	}
}

func run() error {
	siteCode := flag.String("site-code", "0102030405060708", "site_id 8 byte hex")
	siteName := flag.String("site-name", "Gedung Lab", "nama gedung")
	zone := flag.String("zone", "Pintu Lab", "nama zona")
	labDir := flag.String("lab-dir", "", "direktori site.json lab_ca.py (opsional)")
	flag.Parse()

	dsn := os.Getenv("ANASTROPHE_DATABASE_URL")
	if dsn == "" {
		return errors.New("ANASTROPHE_DATABASE_URL wajib diisi")
	}
	code, err := hex.DecodeString(*siteCode)
	if err != nil || len(code) != 8 {
		return errors.New("-site-code harus 8 byte hex")
	}
	groupID, groupKey, err := readerGroup(*labDir)
	if err != nil {
		return err
	}
	ctx := context.Background()
	db, err := store.Open(ctx, dsn)
	if err != nil {
		return err
	}
	defer db.Close()
	if err := db.Migrate(ctx); err != nil {
		return err
	}
	out, err := db.SeedLab(ctx, store.SeedInput{
		OrgName: "Lab", SiteName: *siteName, SiteCode: code,
		Zones: []string{*zone}, ZonesBitmap: 1, GroupID: groupID, GroupKey: groupKey,
	})
	if err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(out)
}

// readerGroup membaca group_id + kunci publik dari site.json lab_ca.py, atau membuat baru.
func readerGroup(labDir string) ([]byte, []byte, error) {
	if labDir == "" {
		key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		if err != nil {
			return nil, nil, err
		}
		pub, _ := key.PublicKey.ECDH()
		id := make([]byte, 8)
		_, _ = rand.Read(id)
		fmt.Fprintln(os.Stderr, "devseed: reader group baru dibuat (kunci privat tidak disimpan; pakai -lab-dir untuk reader lab)")
		return id, pub.Bytes(), nil
	}
	raw, err := os.ReadFile(filepath.Join(labDir, "site.json"))
	if err != nil {
		return nil, nil, err
	}
	var site struct {
		GroupID         string `json:"group_id"`
		GroupPrivatePEM string `json:"group_private_pem"`
	}
	if err := json.Unmarshal(raw, &site); err != nil {
		return nil, nil, err
	}
	id, err := hex.DecodeString(site.GroupID)
	if err != nil || len(id) != 8 {
		return nil, nil, errors.New("group_id di site.json tidak valid")
	}
	block, _ := pem.Decode([]byte(site.GroupPrivatePEM))
	if block == nil {
		return nil, nil, errors.New("group_private_pem di site.json tidak valid")
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, nil, err
	}
	ecKey, ok := key.(*ecdsa.PrivateKey)
	if !ok {
		return nil, nil, errors.New("kunci reader group bukan P-256")
	}
	pub, err := ecKey.PublicKey.ECDH()
	if err != nil {
		return nil, nil, err
	}
	return id, pub.Bytes(), nil
}
