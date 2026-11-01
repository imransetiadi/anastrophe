// Command anastrophe-registry adalah alat operator untuk registri kartu fisik (FR-52, ADR-0031)
// dan persetujuan perangkat tambahan sebelum ada akun (ADR-0032).
//
//	ANASTROPHE_DATABASE_URL=postgres://… ANASTROPHE_DEV_REGISTRY_KEY=<32 byte hex> \
//	  go -C backend run ./cmd/anastrophe-registry import --site <uuid> --file kartu.csv --operator <pegangan>
//	go -C backend run ./cmd/anastrophe-registry approve|reject --card-instance <uuid> --operator <pegangan>
//
// CSV: tech,card_id,holder_contact,zones (zones = nama zona dipisah ";", dipetakan lewat kebijakan
// gedung). Identitas kartu dan kontak langsung di-HMAC per gedung dan tidak pernah dicetak, dicatat,
// atau disimpan (CLAUDE.md aturan 6). --operator adalah pegangan buram (mis. kode staf), bukan nama
// atau email, karena tercatat apa adanya di audit append-only. Kode keluar: 0 berhasil, 1 ada baris
// ditolak (baris lain tetap diimpor), 2 galat.
package main

import (
	"bufio"
	"context"
	"encoding/csv"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/registry"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
)

const usage = "pemakaian: anastrophe-registry import --site <uuid> --file <csv> --operator <pegangan> | approve|reject --card-instance <uuid> --operator <pegangan>"

func main() {
	os.Exit(run(context.Background(), os.Args[1:], os.Stdout, os.Stderr, os.Getenv))
}

func run(ctx context.Context, args []string, stdout, stderr io.Writer, getenv func(string) string) int {
	fail := func(err error) int {
		fmt.Fprintln(stderr, "anastrophe-registry:", err)
		return 2
	}
	if len(args) == 0 {
		return fail(errors.New(usage))
	}
	switch args[0] {
	case "import":
		fs := flag.NewFlagSet("import", flag.ContinueOnError)
		fs.SetOutput(stderr)
		site := fs.String("site", "", "UUID gedung")
		file := fs.String("file", "", "berkas CSV registri")
		operator := fs.String("operator", "", "pegangan operator untuk audit (kode staf, bukan nama atau email)")
		if err := fs.Parse(args[1:]); err != nil {
			return 2
		}
		dsn := getenv("ANASTROPHE_DATABASE_URL")
		if dsn == "" {
			return fail(errors.New("ANASTROPHE_DATABASE_URL wajib diisi"))
		}
		mac, err := registry.NewDevMAC(getenv("ANASTROPHE_DEV_REGISTRY_KEY"))
		if err != nil {
			return fail(errors.New("ANASTROPHE_DEV_REGISTRY_KEY wajib diisi (32 byte hex, sama dengan API)"))
		}
		in, err := os.Open(*file)
		if err != nil {
			return fail(err)
		}
		defer in.Close()
		db, err := store.Open(ctx, dsn)
		if err != nil {
			return fail(err)
		}
		defer db.Close()
		// ID gedung dinormalisasi sekali sebelum MAC (review registri minor 9).
		siteID := strings.ToLower(strings.TrimSpace(*site))
		rejected, err := importCards(ctx, db, mac, siteID, *operator, in, stdout, time.Now())
		if err != nil {
			return fail(err)
		}
		if rejected > 0 {
			return 1
		}
		return 0
	case "approve", "reject":
		fs := flag.NewFlagSet(args[0], flag.ContinueOnError)
		fs.SetOutput(stderr)
		id := fs.String("card-instance", "", "UUID card instance PENDING_APPROVAL")
		operator := fs.String("operator", "", "pegangan operator untuk audit (kode staf, bukan nama atau email)")
		if err := fs.Parse(args[1:]); err != nil {
			return 2
		}
		dsn := getenv("ANASTROPHE_DATABASE_URL")
		if dsn == "" {
			return fail(errors.New("ANASTROPHE_DATABASE_URL wajib diisi"))
		}
		db, err := store.Open(ctx, dsn)
		if err != nil {
			return fail(err)
		}
		defer db.Close()
		approve := args[0] == "approve"
		switch err := db.DecideEnrollment(ctx, *id, approve, *operator, time.Now()); {
		case errors.Is(err, store.ErrInvalidOperator):
			return fail(errors.New("--operator wajib diisi: [A-Za-z0-9._-], maksimal 64 karakter"))
		case errors.Is(err, store.ErrNotFound):
			return fail(errors.New("card instance tidak ditemukan"))
		case errors.Is(err, store.ErrNotPending):
			return fail(errors.New("card instance tidak menunggu persetujuan"))
		case err != nil:
			return fail(err)
		}
		verdict := "ditolak"
		if approve {
			verdict = "disetujui"
		}
		fmt.Fprintf(stdout, "card instance %s %s\n", *id, verdict)
		return 0
	default:
		return fail(errors.New(usage))
	}
}

// importCards membaca CSV registri, menghitung HMAC per gedung, lalu menyimpan kartu yang valid dalam
// satu transaksi. Baris yang ditolak dilaporkan dengan nomor baris dan alasan, tanpa nilai sel.
func importCards(ctx context.Context, db *store.Store, mac registry.MAC, siteID, operator string, in io.Reader, out io.Writer, now time.Time) (int, error) {
	names, err := db.SiteZoneNames(ctx, siteID)
	if errors.Is(err, store.ErrNotFound) {
		return 0, errors.New("gedung tidak ditemukan")
	}
	if err != nil {
		return 0, err
	}
	bits := map[string]uint{}
	for i, name := range names {
		if i < 64 {
			bits[name] = uint(i)
		}
	}
	// Ekspor "CSV UTF-8" (mis. Excel) diawali BOM; header dibandingkan tanpa beda huruf dan spasi.
	buffered := bufio.NewReader(in)
	if bom, err := buffered.Peek(3); err == nil && string(bom) == "\ufeff" {
		_, _ = buffered.Discard(3)
	}
	reader := csv.NewReader(buffered)
	reader.FieldsPerRecord = 4
	header, err := reader.Read()
	for i := range header {
		header[i] = strings.ToLower(strings.TrimSpace(header[i]))
	}
	if err != nil || strings.Join(header, ",") != "tech,card_id,holder_contact,zones" {
		return 0, errors.New("header CSV harus: tech,card_id,holder_contact,zones")
	}
	var cards []store.PhysicalCard
	var problems []string
	seen := map[string]int{}
	for {
		record, err := reader.Read()
		if errors.Is(err, io.EOF) {
			break
		}
		line, _ := reader.FieldPos(0)
		if err != nil {
			var parseErr *csv.ParseError
			if errors.As(err, &parseErr) {
				// Tanda kutip yang tidak ditutup menelan baris sesudahnya: batalkan seluruh impor
				// alih-alih membuang baris valid tanpa laporan (review registri I3).
				if errors.Is(parseErr.Err, csv.ErrQuote) || errors.Is(parseErr.Err, csv.ErrBareQuote) {
					return 0, fmt.Errorf("CSV rusak mulai baris %d (tanda kutip tidak lengkap); tidak ada yang diimpor", parseErr.StartLine)
				}
				line = parseErr.StartLine
			}
			problems = append(problems, fmt.Sprintf("baris %d: format CSV tidak valid", line))
			continue
		}
		card, reason := parseRow(ctx, mac, siteID, bits, record)
		if reason != "" {
			problems = append(problems, fmt.Sprintf("baris %d: %s", line, reason))
			continue
		}
		key := hex.EncodeToString(card.CardHMAC)
		if first, duplicate := seen[key]; duplicate {
			problems = append(problems, fmt.Sprintf("baris %d: kartu sama dengan baris %d", line, first))
			continue
		}
		seen[key] = line
		cards = append(cards, card)
	}
	added, updated, err := db.UpsertPhysicalCards(ctx, siteID, operator, cards, len(problems), now)
	if errors.Is(err, store.ErrInvalidOperator) {
		return 0, errors.New("--operator wajib diisi: [A-Za-z0-9._-], maksimal 64 karakter")
	}
	if err != nil {
		return 0, err
	}
	fmt.Fprintf(out, "ditambah: %d, diperbarui: %d, ditolak: %d\n", added, updated, len(problems))
	for _, p := range problems {
		fmt.Fprintln(out, p)
	}
	return len(problems), nil
}

// parseRow mengubah satu baris CSV menjadi kartu registri. Alasan penolakan tidak memuat nilai sel.
func parseRow(ctx context.Context, mac registry.MAC, siteID string, bits map[string]uint, record []string) (store.PhysicalCard, string) {
	identity, err := registry.ParseCardIdentity(strings.TrimSpace(record[0]), strings.TrimSpace(record[1]))
	if err != nil {
		return store.PhysicalCard{}, "teknologi atau panjang identitas kartu tidak valid"
	}
	var bitmap uint64
	if zones := strings.TrimSpace(record[3]); zones != "" {
		for _, name := range strings.Split(zones, ";") {
			bit, ok := bits[strings.TrimSpace(name)]
			if !ok {
				return store.PhysicalCard{}, "zona tidak dikenal di kebijakan gedung"
			}
			bitmap |= 1 << bit
		}
	}
	sum, err := mac.MAC(ctx, siteID, identity.MACInput())
	if err != nil {
		return store.PhysicalCard{}, "HMAC kartu gagal dihitung"
	}
	card := store.PhysicalCard{CardHMAC: sum, ZonesBitmap: bitmap}
	if contact := strings.TrimSpace(record[2]); contact != "" {
		normalized, err := registry.NormalizeContact(contact)
		if err != nil {
			return store.PhysicalCard{}, "kontak pemegang tidak valid"
		}
		if card.ContactHMAC, err = mac.MAC(ctx, siteID, registry.ContactMACInput(normalized)); err != nil {
			return store.PhysicalCard{}, "HMAC kontak gagal dihitung"
		}
	}
	return card, ""
}
