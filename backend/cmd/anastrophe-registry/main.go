// Command anastrophe-registry adalah alat operator untuk registri kartu fisik (FR-52, ADR-0031),
// persetujuan perangkat tambahan sebelum ada akun (ADR-0032), undangan sekali pakai (ADR-0033),
// siklus hidup kartu (FR-51, ADR-0036), kode gedung untuk enrolment dari app (ADR-0044), dan kebijakan
// gedung (FR-55, ADR-0049).
//
//	ANASTROPHE_DATABASE_URL=postgres://… ANASTROPHE_DEV_REGISTRY_KEY=<32 byte hex> \
//	  go -C backend run ./cmd/anastrophe-registry import --site <uuid> --file kartu.csv --operator <pegangan>
//	go -C backend run ./cmd/anastrophe-registry approve|reject --card-instance <uuid> --operator <pegangan>
//	go -C backend run ./cmd/anastrophe-registry invite --site <uuid> [--zones A;B | --card-file <berkas>|-] --operator <pegangan>
//	go -C backend run ./cmd/anastrophe-registry list --site <uuid> [--status ACTIVE] [--channel ble|nfcHCE] [--id <awalan>]
//	go -C backend run ./cmd/anastrophe-registry suspend|resume --card-instance <uuid> --operator <pegangan>
//	go -C backend run ./cmd/anastrophe-registry revoke --card-instance <uuid> [--reason <kode>] --operator <pegangan>
//	go -C backend run ./cmd/anastrophe-registry site-code --site <uuid> --operator <pegangan>
//	go -C backend run ./cmd/anastrophe-registry policy --site <uuid> [--cert-validity-days <1-30>] [--channels ble,nfcHCE|semua] [--operator <pegangan>]
//
// CSV: tech,card_id,holder_contact,zones (zones = nama zona dipisah ";", dipetakan lewat kebijakan
// gedung). Berkas kartu undangan berisi satu baris <tech>:<hex>; "-" membacanya dari stdin. Identitas
// kartu dan kontak tidak pernah lewat argumen (riwayat shell, daftar proses), langsung di-HMAC per
// gedung, dan tidak pernah dicetak, dicatat, atau disimpan (CLAUDE.md aturan 6). --operator adalah
// pegangan buram (mis. kode staf), bukan nama atau email, karena tercatat apa adanya di audit
// append-only. Kode keluar: 0 berhasil, 1 ada baris ditolak (baris lain tetap diimpor), 2 galat.
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
	"net/url"
	"os"
	"slices"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/registry"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
)

const usage = "pemakaian: anastrophe-registry import --site <uuid> --file <csv> --operator <pegangan> | invite --site <uuid> [--zones A;B | --card-file <berkas>|-] [--ttl <hari>] [--link-base <url>] --operator <pegangan> | approve|reject|suspend|resume --card-instance <uuid> --operator <pegangan> | revoke --card-instance <uuid> [--reason <kode>] --operator <pegangan> | list --site <uuid> [--status <STATUS>] [--channel ble|nfcHCE] [--id <awalan>] | site-code --site <uuid> --operator <pegangan> | policy --site <uuid> [--cert-validity-days <1-30>] [--channels ble,nfcHCE|semua] [--operator <pegangan>]"

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
	case "invite":
		return invite(ctx, args[1:], stdout, stderr, getenv)
	case "list":
		return list(ctx, args[1:], stdout, stderr, getenv)
	case "suspend", "resume", "revoke":
		return lifecycle(ctx, args[0], args[1:], stdout, stderr, getenv)
	case "site-code":
		return siteCode(ctx, args[1:], stdout, stderr, getenv)
	case "policy":
		return policy(ctx, args[1:], stdout, stderr, getenv)
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

// invite membuat undangan sekali pakai (FR-12, FR-53; ADR-0033) dan mencetak tokennya satu kali; server
// hanya menyimpan hash-nya. Kartu opsional dibaca dari berkas atau stdin lalu langsung di-HMAC per gedung.
// Kontak penerima menyusul bersama verifikasi kontak (FR-03).
func invite(ctx context.Context, args []string, stdout, stderr io.Writer, getenv func(string) string) int {
	fail := func(err error) int {
		fmt.Fprintln(stderr, "anastrophe-registry:", err)
		return 2
	}
	fs := flag.NewFlagSet("invite", flag.ContinueOnError)
	fs.SetOutput(stderr)
	site := fs.String("site", "", "UUID gedung")
	cardFile := fs.String("card-file", "", "berkas berisi <tech>:<hex> kartu terdaftar, atau - untuk stdin (opsional)")
	zones := fs.String("zones", "", "nama zona dipisah ; untuk undangan tanpa kartu")
	ttlDays := fs.Int("ttl", 7, "masa berlaku dalam hari (1–30)")
	linkBase := fs.String("link-base", "", "awalan tautan, mis. https://<domain>/i/ (domain belum ditentukan)")
	operator := fs.String("operator", "", "pegangan operator untuk audit (kode staf, bukan nama atau email)")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *ttlDays < 1 || *ttlDays > 30 {
		return fail(errors.New("--ttl harus 1–30 hari"))
	}
	// Review akhir undangan M6: tautan harus bisa dipakai app (InvitationLink: https, host, /i/<token>).
	if *linkBase != "" {
		base, err := url.Parse(*linkBase)
		if err != nil || base.Scheme != "https" || base.Host == "" || base.User != nil || base.Path != "/i/" || base.RawQuery != "" || base.Fragment != "" {
			return fail(errors.New("--link-base harus tepat https://<domain>/i/ (app hanya membuka /i/<token>)"))
		}
	}
	// Review akhir M5: zona undangan berkartu selalu dari registri kartu; --zones yang diabaikan diam-diam
	// bisa memberi zona lebih luas daripada maksud operator.
	if *cardFile != "" && strings.TrimSpace(*zones) != "" {
		return fail(errors.New("--zones tidak berlaku untuk undangan berkartu: zona diambil dari registri kartu"))
	}
	dsn := getenv("ANASTROPHE_DATABASE_URL")
	if dsn == "" {
		return fail(errors.New("ANASTROPHE_DATABASE_URL wajib diisi"))
	}
	siteID := strings.ToLower(strings.TrimSpace(*site))
	db, err := store.Open(ctx, dsn)
	if err != nil {
		return fail(err)
	}
	defer db.Close()
	names, err := db.SiteZoneNames(ctx, siteID)
	if errors.Is(err, store.ErrNotFound) {
		return fail(errors.New("gedung tidak ditemukan"))
	}
	if err != nil {
		return fail(err)
	}
	bitmap, ok := zoneBitmap(names, *zones)
	if !ok {
		return fail(errors.New("zona tidak dikenal di kebijakan gedung"))
	}
	inv := store.Invitation{SiteID: siteID, ZonesBitmap: bitmap, TTL: time.Duration(*ttlDays) * 24 * time.Hour}
	if *cardFile != "" {
		mac, err := registry.NewDevMAC(getenv("ANASTROPHE_DEV_REGISTRY_KEY"))
		if err != nil {
			return fail(errors.New("ANASTROPHE_DEV_REGISTRY_KEY wajib diisi untuk undangan berkartu (32 byte hex, sama dengan API)"))
		}
		identity, err := readCardIdentity(*cardFile, os.Stdin, stderr)
		if err != nil {
			return fail(err)
		}
		if inv.CardHMAC, err = mac.MAC(ctx, siteID, identity.MACInput()); err != nil {
			return fail(err)
		}
	}
	created, err := db.CreateInvitation(ctx, inv, *operator, time.Now())
	switch {
	case errors.Is(err, store.ErrNotRegistered):
		return fail(errors.New("kartu belum terdaftar di registri gedung"))
	case errors.Is(err, store.ErrInvalidOperator):
		return fail(errors.New("--operator wajib diisi: [A-Za-z0-9._-], maksimal 64 karakter"))
	case err != nil:
		return fail(err)
	}
	fmt.Fprintf(stdout, "id: %s\n", created.ID)
	fmt.Fprintf(stdout, "token: %s\n", created.Token)
	if *linkBase != "" {
		fmt.Fprintf(stdout, "tautan: %s%s\n", *linkBase, created.Token)
	}
	fmt.Fprintf(stdout, "berlaku sampai: %s\n", created.ExpiresAt.UTC().Format(time.RFC3339))
	fmt.Fprintln(stdout, "Token hanya dicetak sekali; server menyimpan hash-nya saja.")
	return 0
}

// list mencetak card instance satu gedung untuk operator (FR-50 sebagian): id, status, asal, kanal, dan
// waktu dibuat. Tidak ada identitas kartu, kontak, id perangkat, maupun token.
func list(ctx context.Context, args []string, stdout, stderr io.Writer, getenv func(string) string) int {
	fail := func(err error) int {
		fmt.Fprintln(stderr, "anastrophe-registry:", err)
		return 2
	}
	fs := flag.NewFlagSet("list", flag.ContinueOnError)
	fs.SetOutput(stderr)
	site := fs.String("site", "", "UUID gedung")
	status := fs.String("status", "", "filter status, mis. ACTIVE atau PENDING_APPROVAL")
	channel := fs.String("channel", "", "filter kanal kredensial aktif: ble atau nfcHCE")
	id := fs.String("id", "", "awalan id card instance")
	if err := fs.Parse(args); err != nil {
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
	cards, err := db.ListCardInstancesFiltered(ctx, strings.ToLower(strings.TrimSpace(*site)), store.CardInstanceFilter{
		Status: strings.ToUpper(strings.TrimSpace(*status)), Channel: strings.TrimSpace(*channel), IDPrefix: strings.TrimSpace(*id),
	})
	switch {
	case errors.Is(err, store.ErrInvalidFilter) && strings.TrimSpace(*id) != "" && !validIDPrefix(*id):
		return fail(errors.New("--id harus awalan id card instance (0-9, a-f, -), maksimal 36 karakter"))
	case errors.Is(err, store.ErrInvalidFilter):
		return fail(errors.New("kanal harus ble atau nfcHCE"))
	case errors.Is(err, store.ErrNotFound):
		return fail(errors.New("gedung tidak ditemukan"))
	case errors.Is(err, store.ErrInvalidStatus):
		return fail(errors.New("status tidak dikenal"))
	case err != nil:
		return fail(err)
	}
	tw := tabwriter.NewWriter(stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "ID\tSTATUS\tASAL\tKANAL\tDIBUAT")
	for _, c := range cards {
		channels := strings.Join(c.Channels, ",")
		if channels == "" {
			channels = "-"
		}
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\n", c.ID, c.Status, c.Origin, channels, c.CreatedAt.UTC().Format(time.RFC3339))
	}
	if err := tw.Flush(); err != nil {
		return fail(err)
	}
	return 0
}

// lifecycle menjalankan suspend, resume, atau revoke untuk satu card instance (FR-51, ADR-0036).
func lifecycle(ctx context.Context, action string, args []string, stdout, stderr io.Writer, getenv func(string) string) int {
	fail := func(err error) int {
		fmt.Fprintln(stderr, "anastrophe-registry:", err)
		return 2
	}
	fs := flag.NewFlagSet(action, flag.ContinueOnError)
	fs.SetOutput(stderr)
	id := fs.String("card-instance", "", "UUID card instance")
	operator := fs.String("operator", "", "pegangan operator untuk audit (kode staf, bukan nama atau email)")
	reason := "operator"
	if action == "revoke" {
		fs.StringVar(&reason, "reason", "operator", "kode alasan pencabutan [a-z_], mis. hilang atau pindah")
	}
	if err := fs.Parse(args); err != nil {
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
	instance := strings.ToLower(strings.TrimSpace(*id))
	now := time.Now()
	var verdict string
	switch action {
	case "suspend":
		err, verdict = db.SuspendCard(ctx, instance, *operator, now), "ditangguhkan"
	case "resume":
		err, verdict = db.ResumeCard(ctx, instance, *operator, now), "dipulihkan"
	default:
		var n int
		n, err = db.RevokeCardInstance(ctx, instance, reason, *operator, now)
		verdict = fmt.Sprintf("dicabut (%d kredensial masuk denylist)", n)
	}
	switch {
	case errors.Is(err, store.ErrInvalidOperator):
		return fail(errors.New("--operator wajib diisi: [A-Za-z0-9._-], maksimal 64 karakter"))
	case errors.Is(err, store.ErrInvalidReason):
		return fail(errors.New("--reason harus kode [a-z_], maksimal 32 karakter"))
	case errors.Is(err, store.ErrNotFound):
		return fail(errors.New("card instance tidak ditemukan"))
	case errors.Is(err, store.ErrInvalidTransition):
		return fail(errors.New("status card instance tidak mengizinkan tindakan ini"))
	case err != nil:
		return fail(err)
	}
	fmt.Fprintf(stdout, "card instance %s %s\n", instance, verdict)
	if action != "resume" {
		// Keterbatasan terbuka sampai ADR-0038 diputuskan.
		fmt.Fprintln(stderr, "anastrophe-registry: peringatan: pendaftaran ulang kartu fisik yang sama belum diblokir (ADR-0038, menunggu keputusan)")
	}
	return 0
}

// siteCode membuat kode gedung baru untuk enrolment dari app (ADR-0044) dan mencetaknya sekali. Kode
// lama langsung tidak berlaku. Kode bukan rahasia (boleh dicetak di poster), tetapi tidak ditulis ke
// audit karena audit tidak membutuhkannya.
func siteCode(ctx context.Context, args []string, stdout, stderr io.Writer, getenv func(string) string) int {
	fail := func(err error) int {
		fmt.Fprintln(stderr, "anastrophe-registry:", err)
		return 2
	}
	fs := flag.NewFlagSet("site-code", flag.ContinueOnError)
	fs.SetOutput(stderr)
	site := fs.String("site", "", "UUID gedung")
	operator := fs.String("operator", "", "pegangan operator untuk audit (kode staf, bukan nama atau email)")
	if err := fs.Parse(args); err != nil {
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
	code, replaced, err := db.RotateSiteJoinCode(ctx, strings.ToLower(strings.TrimSpace(*site)), *operator, time.Now())
	switch {
	case errors.Is(err, store.ErrInvalidOperator):
		return fail(errors.New("--operator wajib diisi: [A-Za-z0-9._-], maksimal 64 karakter"))
	case errors.Is(err, store.ErrNotFound):
		return fail(errors.New("gedung tidak ditemukan"))
	case err != nil:
		return fail(err)
	}
	fmt.Fprintf(stdout, "kode: %s\n", store.FormatJoinCode(code))
	if replaced {
		fmt.Fprintln(stderr, "anastrophe-registry: kode lama tidak berlaku lagi; bagikan kode baru ke penghuni")
	}
	return 0
}

// policy membaca kebijakan gedung, atau mengubah masa berlaku sertifikat dan/atau kanal yang diizinkan
// (FR-55, ADR-0049). Hanya kunci yang diberikan yang berubah; zona dan kunci lain dipertahankan.
func policy(ctx context.Context, args []string, stdout, stderr io.Writer, getenv func(string) string) int {
	fail := func(err error) int {
		fmt.Fprintln(stderr, "anastrophe-registry:", err)
		return 2
	}
	fs := flag.NewFlagSet("policy", flag.ContinueOnError)
	fs.SetOutput(stderr)
	site := fs.String("site", "", "UUID gedung")
	days := fs.Int("cert-validity-days", 0, "masa berlaku sertifikat dalam hari (1–30)")
	channels := fs.String("channels", "", "kanal yang diizinkan, dipisah koma: ble, nfcHCE; atau semua")
	operator := fs.String("operator", "", "pegangan operator untuk audit (kode staf, bukan nama atau email)")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	visited := map[string]bool{}
	fs.Visit(func(f *flag.Flag) { visited[f.Name] = true })
	invalid := errors.New("--cert-validity-days harus 1–30 dan --channels hanya ble, nfcHCE, atau semua")
	var update store.PolicyUpdate
	if visited["cert-validity-days"] {
		update.CertValidityDays = days
	}
	if visited["channels"] {
		list := []string{}
		if strings.TrimSpace(*channels) != "semua" {
			for _, item := range strings.Split(*channels, ",") {
				item = strings.TrimSpace(item)
				if item == "" {
					return fail(invalid)
				}
				list = append(list, item)
			}
		}
		update.Channels = &list
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
	siteID := strings.ToLower(strings.TrimSpace(*site))
	var current store.SitePolicy
	if update.CertValidityDays == nil && update.Channels == nil {
		current, err = db.SitePolicyOf(ctx, siteID)
	} else {
		current, err = db.UpdateSitePolicy(ctx, siteID, *operator, update, time.Now())
	}
	switch {
	case errors.Is(err, store.ErrInvalidOperator):
		return fail(errors.New("--operator wajib diisi untuk mengubah kebijakan: [A-Za-z0-9._-], maksimal 64 karakter"))
	case errors.Is(err, store.ErrInvalidPolicy):
		return fail(invalid)
	case errors.Is(err, store.ErrNotFound):
		return fail(errors.New("gedung tidak ditemukan"))
	case err != nil:
		return fail(err)
	}
	fmt.Fprintf(stdout, "gedung: %s\n", siteID)
	if current.CertValidityDays == 0 {
		fmt.Fprintln(stdout, "masa berlaku sertifikat: bawaan (7 hari)")
	} else {
		fmt.Fprintf(stdout, "masa berlaku sertifikat: %d hari\n", current.CertValidityDays)
	}
	switch {
	case current.Channels == nil:
		fmt.Fprintln(stdout, "kanal: semua kanal aktif")
	case len(current.Channels) == 0:
		fmt.Fprintln(stdout, "kanal: tidak ada (enrolment baru tidak bisa diprovisikan)")
	default:
		fmt.Fprintf(stdout, "kanal: %s\n", strings.Join(current.Channels, ", "))
		// Kanal yang diaktifkan layanan (/v1/config) tidak terlihat dari CLI; tanpa irisan, enrolment baru
		// di gedung ini tidak bisa diprovisikan (review akhir, ADR-0049).
		fmt.Fprintln(stdout, "catatan: kanal efektif = kanal ini ∩ kanal yang diaktifkan layanan (/v1/config)")
	}
	fmt.Fprintf(stdout, "zona: %d\n", current.ZoneCount)
	return 0
}

// validIDPrefix: awalan id yang diterima list (sama dengan store), untuk memilih pesan galat yang tepat.
func validIDPrefix(s string) bool {
	s = strings.ToLower(strings.TrimSpace(s))
	if s == "" || len(s) > 36 {
		return false
	}
	for _, r := range s {
		if !(r >= '0' && r <= '9' || r >= 'a' && r <= 'f' || r == '-') {
			return false
		}
	}
	return true
}

// readCardIdentity membaca satu baris <tech>:<hex> dari berkas, atau dari stdin bila path "-". Nilai
// yang ditolak tidak pernah dicetak (CLAUDE.md aturan 6).
func readCardIdentity(path string, stdin *os.File, stderr io.Writer) (registry.CardIdentity, error) {
	in := stdin
	if path != "-" {
		f, err := os.Open(path)
		if err != nil {
			return registry.CardIdentity{}, fmt.Errorf("berkas kartu: %w", err)
		}
		defer f.Close()
		in = f
	} else if info, err := stdin.Stat(); err == nil && info.Mode()&os.ModeCharDevice != 0 {
		fmt.Fprint(stderr, "Tempel identitas kartu <tech>:<hex>, lalu Enter: ")
	}
	line, err := bufio.NewReader(io.LimitReader(in, 256)).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return registry.CardIdentity{}, errors.New("identitas kartu tidak bisa dibaca")
	}
	tech, id, ok := strings.Cut(strings.TrimSpace(line), ":")
	identity, err := registry.ParseCardIdentity(tech, id)
	if !ok || err != nil {
		return registry.CardIdentity{}, errors.New("identitas kartu harus <tech>:<hex> dengan teknologi dan panjang identitas yang valid")
	}
	return identity, nil
}

// zoneBitmap memetakan nama zona (dipisah ";") ke bit lewat urutan zona di kebijakan gedung.
func zoneBitmap(names []string, text string) (uint64, bool) {
	var bitmap uint64
	if strings.TrimSpace(text) == "" {
		return 0, true
	}
	for _, name := range strings.Split(text, ";") {
		bit := slices.Index(names, strings.TrimSpace(name))
		if bit < 0 || bit >= 64 {
			return 0, false
		}
		bitmap |= 1 << uint(bit)
	}
	return bitmap, true
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
