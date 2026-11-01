// Command anastrophe-devseed menyiapkan data lab (dev saja): organisasi, gedung dengan
// kebijakan zona, reader group, dan satu perangkat. Mencetak {"site_id","device_id"}.
//
//	go -C backend run ./cmd/anastrophe-devseed -lab-dir ../scripts/anp1/.lab
//
// Kunci publik reader group diambil dari site.json milik scripts/anp1/lab_ca.py (di-ignore
// git) agar reader lab memakai kunci yang sama; tanpa -lab-dir dibuat kunci baru.
//
// Slot kartu perangkat lab habis (8, termasuk percobaan yang gagal)? Buat perangkat baru
// untuk gedung yang sama: `-site-code <hex> -new-device`.
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
	"strings"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/registry"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
	"github.com/jackc/pgx/v5/pgconn"
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
	newDevice := flag.Bool("new-device", false, "hanya buat perangkat baru untuk -site-code yang sudah ada (mis. slot kartu perangkat lama habis)")
	allowRemote := flag.Bool("allow-remote", false, "izinkan database bukan lokal (hati-hati: devseed menulis data lab)")
	labCard := flag.String("lab-card", "iso14443a:04a1b2c3d4e5f6", "kartu lab <tech>:<hex> yang didaftarkan ke registri (app memakai -ANLabCard yang sama)")
	flag.Parse()

	dsn := os.Getenv("ANASTROPHE_DATABASE_URL")
	if dsn == "" {
		return errors.New("ANASTROPHE_DATABASE_URL wajib diisi")
	}
	if local, err := localDatabase(dsn); err != nil || (!local && !*allowRemote) {
		return errors.New("hanya untuk database lokal (localhost, 127.0.0.1, ::1, atau socket Unix); pakai -allow-remote bila memang disengaja")
	}
	code, err := hex.DecodeString(*siteCode)
	if err != nil || len(code) != 8 {
		return errors.New("-site-code harus 8 byte hex")
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
	if *newDevice {
		out, err := db.AddLabDevice(ctx, code)
		if errors.Is(err, store.ErrNotFound) {
			return errors.New("-site-code belum di-seed; jalankan tanpa -new-device dulu")
		}
		if err != nil {
			return err
		}
		return json.NewEncoder(os.Stdout).Encode(out)
	}
	// Kartu lab dan kunci registri hanya dibutuhkan seed lengkap, bukan -new-device (review registri minor 4).
	labIdentity, err := parseLabCard(*labCard)
	if err != nil {
		return err
	}
	mac, err := registry.NewDevMAC(os.Getenv("ANASTROPHE_DEV_REGISTRY_KEY"))
	if err != nil {
		return errors.New("ANASTROPHE_DEV_REGISTRY_KEY wajib diisi (32 byte hex, sama dengan API)")
	}
	groupID, groupKey, err := readerGroup(*labDir)
	if err != nil {
		return err
	}
	out, err := db.SeedLab(ctx, store.SeedInput{
		OrgName: "Lab", SiteName: *siteName, SiteCode: code,
		Zones: []string{*zone}, ZonesBitmap: 1, GroupID: groupID, GroupKey: groupKey,
	})
	if err != nil {
		return err
	}
	// Enrolment lab lewat jalur kartu (ADR-0031): kartu lab terdaftar dengan zona lab (bit 0).
	sum, err := mac.MAC(ctx, out.SiteID, labIdentity.MACInput())
	if err != nil {
		return err
	}
	if _, _, err := db.UpsertPhysicalCards(ctx, out.SiteID, "devseed", []store.PhysicalCard{{CardHMAC: sum, ZonesBitmap: 1}}, 0, time.Now()); err != nil {
		return err
	}
	fmt.Fprintln(os.Stderr, "devseed: kartu lab terdaftar di registri (pakai -ANLabCard yang sama di app)")
	return json.NewEncoder(os.Stdout).Encode(out)
}

// parseLabCard membaca "<tech>:<hex>" menjadi identitas kartu lab.
func parseLabCard(s string) (registry.CardIdentity, error) {
	tech, id, ok := strings.Cut(s, ":")
	if !ok {
		return registry.CardIdentity{}, errors.New("-lab-card harus <tech>:<hex>, mis. iso14443a:04a1b2c3d4e5f6")
	}
	identity, err := registry.ParseCardIdentity(tech, id)
	if err != nil {
		return registry.CardIdentity{}, errors.New("-lab-card: teknologi atau panjang identitas tidak valid")
	}
	return identity, nil
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

// localDatabase: host DSN adalah loopback atau socket Unix (devseed hanya untuk lab lokal).
func localDatabase(dsn string) (bool, error) {
	cfg, err := pgconn.ParseConfig(dsn)
	if err != nil {
		return false, err
	}
	switch host := cfg.Host; {
	case strings.HasPrefix(host, "/"), host == "localhost", host == "127.0.0.1", host == "::1":
		return true, nil
	default:
		return false, nil
	}
}
