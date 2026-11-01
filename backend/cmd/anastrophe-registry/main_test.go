package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/registry"
	"github.com/imransetiadi/anastrophe/backend/internal/store"
	"github.com/imransetiadi/anastrophe/backend/internal/testpg"
	"github.com/jackc/pgx/v5"
)

var adminDSN, skipReason string

func TestMain(m *testing.M) {
	dsn, stop, err := testpg.Start()
	if err != nil && !errors.Is(err, testpg.ErrUnavailable) {
		fmt.Println("test database gagal:", err)
		os.Exit(1)
	}
	if err != nil {
		skipReason = err.Error()
	}
	adminDSN = dsn
	code := m.Run()
	stop()
	os.Exit(code)
}

func freshStore(t *testing.T) (*store.Store, string) {
	t.Helper()
	if adminDSN == "" {
		testpg.Skip(t, skipReason)
	}
	ctx := context.Background()
	dsn, err := testpg.NewDatabase(ctx, adminDSN)
	if err != nil {
		t.Fatal(err)
	}
	s, err := store.Open(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(s.Close)
	if err := s.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	return s, dsn
}

const testKey = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

func env(dsn string) func(string) string {
	return func(k string) string {
		switch k {
		case "ANASTROPHE_DATABASE_URL":
			return dsn
		case "ANASTROPHE_DEV_REGISTRY_KEY":
			return testKey
		}
		return ""
	}
}

func siteWithZones(t *testing.T, db *store.Store) string {
	t.Helper()
	ctx := context.Background()
	org, err := db.CreateOrganization(ctx, "Org", "ID")
	if err != nil {
		t.Fatal(err)
	}
	site, err := db.CreateSite(ctx, org, "Menara", "ID", "Asia/Jakarta", []byte{1, 2, 3, 4, 5, 6, 7, 8})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.SetSitePolicy(ctx, site, []byte(`{"zones": ["Lobi", "Lift A", "Parkir"]}`)); err != nil {
		t.Fatal(err)
	}
	return site
}

func writeCSV(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "kartu.csv")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

const registryCSV = `tech,card_id,holder_contact,zones
iso14443a,04a1b2c3d4e5f6,+62 812-3456-7890,Lobi;Parkir
felica,0123456789abcdef,,Lift A
iso14443a,04a1b2c3d4,,Lobi
iso15693,e004010203040506,,Gudang
iso14443a,04a1b2c3d4e5f6,,Lobi
iso14443a,04b1b2c3d4e5f6,bukan-kontak,Lobi
`

func cardHMAC(t *testing.T, site, tech, id string) []byte {
	t.Helper()
	mac, _ := registry.NewDevMAC(testKey)
	identity, err := registry.ParseCardIdentity(tech, id)
	if err != nil {
		t.Fatal(err)
	}
	sum, err := mac.MAC(context.Background(), site, identity.MACInput())
	if err != nil {
		t.Fatal(err)
	}
	return sum
}

func TestImportCSV(t *testing.T) {
	db, dsn := freshStore(t)
	ctx := context.Background()
	site := siteWithZones(t, db)
	path := writeCSV(t, registryCSV)
	var out, errOut bytes.Buffer
	if code := run(ctx, []string{"import", "--site", site, "--file", path, "--operator", "budi"}, &out, &errOut, env(dsn)); code != 1 {
		t.Fatalf("kode keluar %d (ingin 1: ada baris ditolak): %s %s", code, out.String(), errOut.String())
	}
	for _, want := range []string{"ditambah: 2, diperbarui: 0, ditolak: 4", "baris 4:", "baris 5:", "baris 6: kartu sama dengan baris 2", "baris 7:"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("laporan tanpa %q: %s", want, out.String())
		}
	}
	// Zona dipetakan lewat kebijakan gedung: Lobi (bit 0) + Parkir (bit 2) = 5.
	device, _ := db.CreateDevice(ctx)
	id, status, err := db.StartCardEnrollment(ctx, device, site, cardHMAC(t, site, "iso14443a", "04a1b2c3d4e5f6"), time.Now())
	if err != nil || status != "PROVISIONING" {
		t.Fatalf("kartu impor tidak bisa didaftarkan: %q %v", status, err)
	}
	_, _, err = db.Idempotent(ctx, "zona", []byte("h"), func(ctx context.Context, tx *store.Tx) (int, []byte, error) {
		e, err := tx.EnrollmentForUpdate(ctx, id)
		if err == nil && e.ZonesBitmap != 5 {
			t.Errorf("bitmap zona = %d, ingin 5", e.ZonesBitmap)
		}
		return 200, []byte("{}"), err
	})
	if err != nil {
		t.Fatal(err)
	}
	out.Reset()
	if code := run(ctx, []string{"import", "--site", site, "--file", path, "--operator", "budi"}, &out, &errOut, env(dsn)); code != 1 || !strings.Contains(out.String(), "ditambah: 0, diperbarui: 2, ditolak: 4") {
		t.Fatalf("impor ulang: %d %s", code, out.String())
	}
}

func TestImportTanpaNilaiMentah(t *testing.T) {
	// CLAUDE.md aturan 6: identitas kartu dan kontak tidak tercetak, tercatat, atau masuk audit.
	db, dsn := freshStore(t)
	ctx := context.Background()
	site := siteWithZones(t, db)
	var out, errOut bytes.Buffer
	run(ctx, []string{"import", "--site", site, "--file", writeCSV(t, registryCSV), "--operator", "budi"}, &out, &errOut, env(dsn))
	events, err := db.AuditEvents(ctx, store.AuditChain(site))
	if err != nil || len(events) != 1 {
		t.Fatalf("audit: %d %v", len(events), err)
	}
	text := strings.ToLower(out.String() + errOut.String() + fmt.Sprint(events) + allTablesText(t, dsn))
	for _, raw := range []string{"04a1b2c3d4e5f6", "0123456789abcdef", "04a1b2c3d4", "e004010203040506", "04b1b2c3d4e5f6", "6281234567890", "812-3456", "bukan-kontak"} {
		if strings.Contains(text, raw) {
			t.Fatalf("nilai mentah %q bocor: %s", raw, text)
		}
	}
}

func TestPersetujuanLewatCLI(t *testing.T) {
	db, dsn := freshStore(t)
	ctx := context.Background()
	site := siteWithZones(t, db)
	var out, errOut bytes.Buffer
	run(ctx, []string{"import", "--site", site, "--file", writeCSV(t, "tech,card_id,holder_contact,zones\niso14443a,04a1b2c3d4e5f6,,Lobi\n"), "--operator", "budi"}, &out, &errOut, env(dsn))
	sum := cardHMAC(t, site, "iso14443a", "04a1b2c3d4e5f6")
	devices := make([]string, 3)
	for i := range devices {
		devices[i], _ = db.CreateDevice(ctx)
	}
	_, _, _ = db.StartCardEnrollment(ctx, devices[0], site, sum, time.Now())
	approveMe, _, _ := db.StartCardEnrollment(ctx, devices[1], site, sum, time.Now())
	rejectMe, _, _ := db.StartCardEnrollment(ctx, devices[2], site, sum, time.Now())
	if code := run(ctx, []string{"approve", "--card-instance", approveMe, "--operator", "budi"}, &out, &errOut, env(dsn)); code != 0 {
		t.Fatalf("approve: %d %s", code, errOut.String())
	}
	if code := run(ctx, []string{"reject", "--card-instance", rejectMe, "--operator", "budi"}, &out, &errOut, env(dsn)); code != 0 {
		t.Fatalf("reject: %d %s", code, errOut.String())
	}
	errOut.Reset()
	if code := run(ctx, []string{"approve", "--card-instance", approveMe, "--operator", "budi"}, &out, &errOut, env(dsn)); code != 2 || !strings.Contains(errOut.String(), "tidak menunggu persetujuan") {
		t.Fatalf("approve ulang: %d %s", code, errOut.String())
	}
	if code := run(ctx, []string{"approve", "--card-instance", rejectMe}, &out, &errOut, env(dsn)); code != 2 {
		t.Fatalf("tanpa operator: %d", code)
	}
	events, _ := db.AuditEvents(ctx, store.AuditChain(site))
	var decided []string
	for _, e := range events {
		if e.Action == "enrollment.approved" || e.Action == "enrollment.rejected" {
			decided = append(decided, e.Action+" "+e.Actor)
		}
	}
	if strings.Join(decided, ",") != "enrollment.approved operator:budi,enrollment.rejected operator:budi" {
		t.Fatalf("audit keputusan: %v", decided)
	}
}

func TestArgumenSalah(t *testing.T) {
	ctx := context.Background()
	var out, errOut bytes.Buffer
	noDB := func(string) string { return "" }
	for _, args := range [][]string{nil, {"hapus"}, {"import", "--site", "x"}} {
		if code := run(ctx, args, &out, &errOut, noDB); code != 2 {
			t.Errorf("%v: kode %d", args, code)
		}
	}
	withDB := func(k string) string {
		if k == "ANASTROPHE_DATABASE_URL" {
			return "postgres://127.0.0.1:1/x"
		}
		return ""
	}
	errOut.Reset()
	if code := run(ctx, []string{"import", "--site", "x", "--file", "y", "--operator", "budi"}, &out, &errOut, withDB); code != 2 || !strings.Contains(errOut.String(), "ANASTROPHE_DEV_REGISTRY_KEY") {
		t.Fatalf("tanpa kunci registri: %d %s", code, errOut.String())
	}
}

// allTablesText menggabungkan isi semua tabel (row_to_json) untuk memeriksa nilai mentah (aturan 6).
func allTablesText(t *testing.T, dsn string) string {
	t.Helper()
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close(ctx)
	rows, err := conn.Query(ctx, `SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'`)
	if err != nil {
		t.Fatal(err)
	}
	tables, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		t.Fatal(err)
	}
	var b strings.Builder
	for _, table := range tables {
		var text string
		query := fmt.Sprintf(`SELECT coalesce(string_agg(row_to_json(t)::text, ' '), '') FROM %s t`, pgx.Identifier{table}.Sanitize())
		if err := conn.QueryRow(ctx, query).Scan(&text); err != nil {
			t.Fatal(err)
		}
		b.WriteString(strings.ToLower(text))
	}
	return b.String()
}

func TestImportCSVDenganBOMDanCRLF(t *testing.T) {
	// Review I3: ekspor "CSV UTF-8" Excel diawali BOM dan memakai CRLF; header boleh beda huruf/spasi.
	db, dsn := freshStore(t)
	site := siteWithZones(t, db)
	content := "\ufeffTech, card_id ,Holder_Contact,zones\r\niso14443a,04a1b2c3d4e5f6,,Lobi\r\n"
	var out, errOut bytes.Buffer
	if code := run(context.Background(), []string{"import", "--site", site, "--file", writeCSV(t, content), "--operator", "budi"}, &out, &errOut, env(dsn)); code != 0 || !strings.Contains(out.String(), "ditambah: 1, diperbarui: 0, ditolak: 0") {
		t.Fatalf("kode %d: %s %s", code, out.String(), errOut.String())
	}
}

func TestImportKutipRusakDibatalkan(t *testing.T) {
	// Review I3: tanda kutip yang tidak ditutup menelan baris sesudahnya; seluruh impor dibatalkan.
	db, dsn := freshStore(t)
	ctx := context.Background()
	site := siteWithZones(t, db)
	content := "tech,card_id,holder_contact,zones\niso14443a,04a1b2c3d4e5f6,,Lobi\niso14443a,04b1b2c3d4e5f6,\"budi,Lobi\niso14443a,04c1b2c3d4e5f6,,Lobi\niso14443a,04d1b2c3d4e5f6,,Lobi\n"
	var out, errOut bytes.Buffer
	code := run(ctx, []string{"import", "--site", site, "--file", writeCSV(t, content), "--operator", "budi"}, &out, &errOut, env(dsn))
	if code != 2 || !strings.Contains(errOut.String(), "baris 3") {
		t.Fatalf("kode %d (ingin 2): %s %s", code, out.String(), errOut.String())
	}
	if events, _ := db.AuditEvents(ctx, store.AuditChain(site)); len(events) != 0 {
		t.Fatalf("impor seharusnya batal seluruhnya, audit: %d", len(events))
	}
}

func inviteToken(t *testing.T, out string) string {
	t.Helper()
	for _, line := range strings.Split(out, "\n") {
		if token, ok := strings.CutPrefix(line, "token: "); ok {
			return token
		}
	}
	t.Fatalf("token tidak tercetak: %s", out)
	return ""
}

func TestInviteMencetakTokenSekali(t *testing.T) {
	// Review Focus 3: token dicetak sekali; database dan audit hanya menyimpan hash-nya.
	db, dsn := freshStore(t)
	ctx := context.Background()
	site := siteWithZones(t, db)
	var out, errOut bytes.Buffer
	code := run(ctx, []string{"invite", "--site", site, "--zones", "Lobi;Parkir", "--link-base", "https://contoh.test/i/", "--operator", "staf-01"}, &out, &errOut, env(dsn))
	if code != 0 {
		t.Fatalf("kode %d: %s %s", code, out.String(), errOut.String())
	}
	token := inviteToken(t, out.String())
	if !strings.Contains(out.String(), "tautan: https://contoh.test/i/"+token) {
		t.Fatalf("tautan tidak tercetak: %s", out.String())
	}
	if strings.Contains(allTablesText(t, dsn), strings.ToLower(token)) {
		t.Fatal("token mentah tersimpan di database")
	}
	hash, err := store.InvitationTokenHash(token)
	if err != nil {
		t.Fatal(err)
	}
	device, _ := db.CreateDevice(ctx)
	r, err := db.EnrollInvitation(ctx, device, hash, time.Now())
	if err != nil || r.Status != "PROVISIONING" {
		t.Fatalf("undangan hasil CLI tidak bisa dipakai: %+v %v", r, err)
	}
	_, _, err = db.Idempotent(ctx, "zona-undangan", []byte("h"), func(ctx context.Context, tx *store.Tx) (int, []byte, error) {
		e, err := tx.EnrollmentForUpdate(ctx, r.ID)
		if err == nil && e.ZonesBitmap != 5 {
			t.Errorf("zona undangan = %d, ingin 5 (Lobi + Parkir)", e.ZonesBitmap)
		}
		return 200, []byte("{}"), err
	})
	if err != nil {
		t.Fatal(err)
	}
}

func TestInviteKartuHarusTerdaftar(t *testing.T) {
	db, dsn := freshStore(t)
	ctx := context.Background()
	site := siteWithZones(t, db)
	var out, errOut bytes.Buffer
	run(ctx, []string{"import", "--site", site, "--file", writeCSV(t, "tech,card_id,holder_contact,zones\niso14443a,04a1b2c3d4e5f6,,Lobi\n"), "--operator", "staf-01"}, &out, &errOut, env(dsn))
	errOut.Reset()
	if code := run(ctx, []string{"invite", "--site", site, "--card-file", writeCardFile(t, "iso14443a:04ffffffffff01\n"), "--operator", "staf-01"}, &out, &errOut, env(dsn)); code != 2 || !strings.Contains(errOut.String(), "belum terdaftar") {
		t.Fatalf("kartu tidak terdaftar: %d %s", code, errOut.String())
	}
	if code := run(ctx, []string{"invite", "--site", site, "--card-file", writeCardFile(t, "iso14443a:04a1b2c3d4e5f6\n"), "--operator", "staf-01"}, &out, &errOut, env(dsn)); code != 0 {
		t.Fatalf("kartu terdaftar: %d %s", code, errOut.String())
	}
}

func writeCardFile(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "kartu.txt")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestInviteIdentitasTidakLewatArgumen(t *testing.T) {
	// Review akhir I3 (CLAUDE.md aturan 6): identitas kartu dan kontak tidak boleh lewat argumen, karena
	// argumen tersimpan di riwayat shell dan terlihat di daftar proses. Identitas dibaca dari berkas/stdin.
	db, dsn := freshStore(t)
	ctx := context.Background()
	site := siteWithZones(t, db)
	for name, args := range map[string][]string{
		"card-id": {"--card-tech", "iso14443a", "--card-id", "04a1b2c3d4e5f6"},
		"contact": {"--contact", "budi@contoh.test"},
	} {
		var out, errOut bytes.Buffer
		full := append([]string{"invite", "--site", site, "--operator", "staf-01"}, args...)
		if code := run(ctx, full, &out, &errOut, env(dsn)); code != 2 || !strings.Contains(errOut.String(), "not defined") {
			t.Errorf("%s: kode %d %s", name, code, errOut.String())
		}
	}
	var out, errOut bytes.Buffer
	code := run(ctx, []string{"invite", "--site", site, "--card-file", writeCardFile(t, "iso14443a:04a1b2\n"), "--operator", "staf-01"}, &out, &errOut, env(dsn))
	if code != 2 || strings.Contains(errOut.String()+out.String(), "04a1b2") {
		t.Fatalf("identitas rusak: kode %d, keluaran memuat nilai: %s %s", code, out.String(), errOut.String())
	}
}

func TestInviteZonaDenganKartuDitolak(t *testing.T) {
	// Review akhir M5: zona undangan berkartu selalu diambil dari registri kartu; --zones yang diabaikan
	// diam-diam bisa memberi zona lebih luas daripada maksud operator.
	db, dsn := freshStore(t)
	ctx := context.Background()
	site := siteWithZones(t, db)
	var out, errOut bytes.Buffer
	run(ctx, []string{"import", "--site", site, "--file", writeCSV(t, "tech,card_id,holder_contact,zones\niso14443a,04a1b2c3d4e5f6,,Lobi;Parkir\n"), "--operator", "staf-01"}, &out, &errOut, env(dsn))
	errOut.Reset()
	code := run(ctx, []string{"invite", "--site", site, "--zones", "Lobi", "--card-file", writeCardFile(t, "iso14443a:04a1b2c3d4e5f6\n"), "--operator", "staf-01"}, &out, &errOut, env(dsn))
	if code != 2 || !strings.Contains(errOut.String(), "zona diambil dari registri") {
		t.Fatalf("kode %d: %s", code, errOut.String())
	}
}

func TestInviteMenolakIsianSalah(t *testing.T) {
	db, dsn := freshStore(t)
	ctx := context.Background()
	site := siteWithZones(t, db)
	for name, args := range map[string][]string{
		"zona-tak-dikenal": {"--zones", "Gudang"},
		"ttl-31":           {"--ttl", "31"},
		"ttl-0":            {"--ttl", "0"},
		"tanpa-operator":   {"--operator", ""},
	} {
		var out, errOut bytes.Buffer
		full := append([]string{"invite", "--site", site, "--operator", "staf-01"}, args...)
		if code := run(ctx, full, &out, &errOut, env(dsn)); code != 2 {
			t.Errorf("%s: kode %d %s", name, code, out.String())
		}
	}
}

func TestBacaIdentitasKartuDariStdin(t *testing.T) {
	// Review akhir I3: "-" membaca identitas dari stdin (pipe atau tempel interaktif), bukan argumen.
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.WriteString("iso14443a:04A1B2C3D4E5F6\n"); err != nil {
		t.Fatal(err)
	}
	w.Close()
	var prompt bytes.Buffer
	identity, err := readCardIdentity("-", r, &prompt)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := registry.ParseCardIdentity("iso14443a", "04a1b2c3d4e5f6")
	if !bytes.Equal(identity.MACInput(), want.MACInput()) {
		t.Fatal("identitas dari stdin berbeda")
	}
	if prompt.Len() != 0 {
		t.Fatalf("prompt tercetak untuk pipe: %q", prompt.String())
	}
}

// activeInstance membuat card instance ACTIVE dengan satu kredensial BLE di gedung uji.
func activeInstance(t *testing.T, db *store.Store, site string) string {
	t.Helper()
	ctx := context.Background()
	device, err := db.CreateDevice(ctx)
	if err != nil {
		t.Fatal(err)
	}
	id, err := db.StartEnrollment(ctx, device, site, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	credID := make([]byte, 16)
	copy(credID, id)
	pub := append([]byte{0x04}, make([]byte, 64)...)
	_, _, err = db.Idempotent(ctx, "aktif-"+id, []byte("h"), func(ctx context.Context, tx *store.Tx) (int, []byte, error) {
		return 200, []byte("{}"), tx.SaveCredential(ctx, store.Credential{CardInstanceID: id, Channel: "ble", CredID: credID, PubKey: pub, Cert: []byte{1}, NotAfter: time.Now().Add(time.Hour)})
	})
	if err != nil {
		t.Fatal(err)
	}
	return id
}

func TestListCardInstance(t *testing.T) {
	// FR-50 (sebagian): operator mendapat id instance untuk approve/suspend/resume/revoke, tanpa identitas.
	db, dsn := freshStore(t)
	ctx := context.Background()
	site := siteWithZones(t, db)
	active := activeInstance(t, db, site)
	device, _ := db.CreateDevice(ctx)
	pending, err := db.StartEnrollment(ctx, device, site, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	var out, errOut bytes.Buffer
	if code := run(ctx, []string{"list", "--site", site}, &out, &errOut, env(dsn)); code != 0 {
		t.Fatalf("list: %d %s", code, errOut.String())
	}
	text := out.String()
	if !strings.Contains(text, active) || !strings.Contains(text, pending) || !strings.Contains(text, "ACTIVE") || !strings.Contains(text, "ble") || strings.Contains(strings.ToLower(text), "hmac") {
		t.Fatalf("keluaran list:\n%s", text)
	}
	out.Reset()
	if code := run(ctx, []string{"list", "--site", site, "--status", "ACTIVE"}, &out, &errOut, env(dsn)); code != 0 || !strings.Contains(out.String(), active) || strings.Contains(out.String(), pending) {
		t.Fatalf("list ACTIVE: %d\n%s", code, out.String())
	}
	errOut.Reset()
	if code := run(ctx, []string{"list", "--site", site, "--status", "BOGUS"}, &out, &errOut, env(dsn)); code != 2 || !strings.Contains(errOut.String(), "status tidak dikenal") {
		t.Fatalf("status tak dikenal: %d %s", code, errOut.String())
	}
	errOut.Reset()
	if code := run(ctx, []string{"list", "--site", "00000000-0000-4000-8000-000000000000"}, &out, &errOut, env(dsn)); code != 2 || !strings.Contains(errOut.String(), "gedung tidak ditemukan") {
		t.Fatalf("gedung tak dikenal: %d %s", code, errOut.String())
	}
}

func cardInstanceStatus(t *testing.T, db *store.Store, site, id string) string {
	t.Helper()
	list, err := db.ListCardInstances(context.Background(), site, "")
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range list {
		if c.ID == id {
			return c.Status
		}
	}
	t.Fatalf("instance %s tidak ada", id)
	return ""
}

func TestSuspendResumeRevoke(t *testing.T) {
	// FR-51: tindakan operator lewat CLI mengubah status instance.
	db, dsn := freshStore(t)
	ctx := context.Background()
	site := siteWithZones(t, db)
	id := activeInstance(t, db, site)
	for _, step := range []struct {
		args []string
		want string
	}{
		{[]string{"suspend", "--card-instance", id, "--operator", "staf-01"}, "SUSPENDED"},
		{[]string{"resume", "--card-instance", id, "--operator", "staf-01"}, "ACTIVE"},
		{[]string{"revoke", "--card-instance", id, "--reason", "hilang", "--operator", "staf-01"}, "REVOKED"},
	} {
		var out, errOut bytes.Buffer
		if code := run(ctx, step.args, &out, &errOut, env(dsn)); code != 0 {
			t.Fatalf("%s: %d %s", step.args[0], code, errOut.String())
		}
		if got := cardInstanceStatus(t, db, site, id); got != step.want {
			t.Fatalf("%s: status %s, ingin %s", step.args[0], got, step.want)
		}
		if !strings.Contains(out.String(), id) {
			t.Fatalf("%s: keluaran tanpa id: %s", step.args[0], out.String())
		}
	}
}

func TestTransisiCLIDitolak(t *testing.T) {
	// Review Focus 3: transisi ilegal keluar dengan kode 2 dan pesan yang jelas.
	db, dsn := freshStore(t)
	ctx := context.Background()
	site := siteWithZones(t, db)
	id := activeInstance(t, db, site)
	for name, c := range map[string]struct {
		args []string
		want string
	}{
		"resume-dari-aktif": {[]string{"resume", "--card-instance", id, "--operator", "staf-01"}, "status card instance tidak mengizinkan"},
		"tak-dikenal":       {[]string{"suspend", "--card-instance", "00000000-0000-4000-8000-000000000000", "--operator", "staf-01"}, "card instance tidak ditemukan"},
		"tanpa-operator":    {[]string{"suspend", "--card-instance", id}, "--operator wajib diisi"},
	} {
		var out, errOut bytes.Buffer
		if code := run(ctx, c.args, &out, &errOut, env(dsn)); code != 2 || !strings.Contains(errOut.String(), c.want) {
			t.Errorf("%s: kode %d %s", name, code, errOut.String())
		}
	}
	if got := cardInstanceStatus(t, db, site, id); got != "ACTIVE" {
		t.Fatalf("status berubah: %s", got)
	}
}

func TestRevokeAlasanTidakValid(t *testing.T) {
	// Spesifikasi: alasan pencabutan berupa kode pendek, bukan teks bebas yang masuk audit append-only.
	db, dsn := freshStore(t)
	ctx := context.Background()
	site := siteWithZones(t, db)
	id := activeInstance(t, db, site)
	var out, errOut bytes.Buffer
	if code := run(ctx, []string{"revoke", "--card-instance", id, "--reason", "Bukan Kode", "--operator", "staf-01"}, &out, &errOut, env(dsn)); code != 2 || !strings.Contains(errOut.String(), "--reason") {
		t.Fatalf("kode %d %s", code, errOut.String())
	}
	if got := cardInstanceStatus(t, db, site, id); got != "ACTIVE" {
		t.Fatalf("status berubah: %s", got)
	}
}

func TestReasonHanyaUntukRevoke(t *testing.T) {
	// Pelajaran review undangan M5: flag yang diabaikan diam-diam menyesatkan operator.
	db, dsn := freshStore(t)
	site := siteWithZones(t, db)
	id := activeInstance(t, db, site)
	var out, errOut bytes.Buffer
	if code := run(context.Background(), []string{"suspend", "--card-instance", id, "--reason", "hilang", "--operator", "staf-01"}, &out, &errOut, env(dsn)); code != 2 || !strings.Contains(errOut.String(), "not defined") {
		t.Fatalf("suspend --reason: %d %s", code, errOut.String())
	}
}

func TestSuspendRevokeMemperingatkanPendaftaranUlang(t *testing.T) {
	// ADR-0038 (terbuka): sampai diputuskan, operator diberi tahu bahwa pendaftaran ulang kartu fisik
	// yang sama belum diblokir.
	db, dsn := freshStore(t)
	site := siteWithZones(t, db)
	id := activeInstance(t, db, site)
	for _, args := range [][]string{
		{"suspend", "--card-instance", id, "--operator", "staf-01"},
		{"revoke", "--card-instance", id, "--operator", "staf-01"},
	} {
		var out, errOut bytes.Buffer
		if code := run(context.Background(), args, &out, &errOut, env(dsn)); code != 0 || !strings.Contains(errOut.String(), "ADR-0038") {
			t.Fatalf("%s: kode %d, peringatan tidak ada: %s", args[0], code, errOut.String())
		}
	}
}
