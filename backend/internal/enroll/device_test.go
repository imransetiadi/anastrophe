package enroll

import (
	"context"
	"crypto/rand"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"testing"

	"github.com/imransetiadi/anastrophe/backend/internal/store"
	"github.com/jackc/pgx/v5"
)

// newDeviceID membuat UUID v4 acak seperti yang dibuat app untuk perangkat baru (ADR-0045).
func newDeviceID(t *testing.T) string {
	t.Helper()
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func (f fixture) deviceRows(t *testing.T, id string) int {
	t.Helper()
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, f.dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close(ctx)
	var n int
	if err := conn.QueryRow(ctx, `SELECT count(*) FROM devices WHERE id = $1`, id).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestEnrolmentKartuMembuatPerangkatBaru(t *testing.T) {
	// ADR-0045: perangkat app produksi belum terdaftar; enrolment pertamanya membuat baris perangkat.
	f := newFixture(t)
	device := newDeviceID(t)
	body := f.cardBody()
	body["device_id"] = device
	rec := f.do(t, http.MethodPost, "/v1/enrollments", "", body)
	if _, status := enrolResult(t, rec.Body); rec.Code != http.StatusCreated || status != "PROVISIONING" {
		t.Fatalf("enrolment perangkat baru: %d %s", rec.Code, rec.Body)
	}
	if n := f.deviceRows(t, device); n != 1 {
		t.Fatalf("baris perangkat = %d, ingin 1", n)
	}
}

func TestEnrolmentUndanganMembuatPerangkatBaru(t *testing.T) {
	f := newFixture(t)
	device := newDeviceID(t)
	token := f.invitation(t, store.Invitation{ZonesBitmap: 1}, f.h.Now())
	rec := f.do(t, http.MethodPost, "/v1/enrollments", "", map[string]string{"device_id": device, "invitation": token})
	if _, status := enrolResult(t, rec.Body); rec.Code != http.StatusCreated || status != "PROVISIONING" {
		t.Fatalf("enrolment undangan perangkat baru: %d %s", rec.Code, rec.Body)
	}
	if n := f.deviceRows(t, device); n != 1 {
		t.Fatalf("baris perangkat = %d, ingin 1", n)
	}
}

func TestEnrolmentDitolakTanpaBarisPerangkat(t *testing.T) {
	// Review Focus 2: enrolment yang ditolak tidak meninggalkan baris perangkat, juga lewat jalur
	// Idempotency-Key (respons 4xx tidak di-commit).
	f := newFixture(t)
	cases := []struct {
		name string
		body func(device string) map[string]any
		want string
	}{
		{"kartu tak terdaftar", func(device string) map[string]any {
			return map[string]any{"device_id": device, "site_id": f.siteID, "card": map[string]string{"tech": "iso14443a", "id": "04ffffffffffff"}}
		}, "ENR-NOT-REGISTERED"},
		{"gedung tak dikenal", func(device string) map[string]any {
			return map[string]any{"device_id": device, "site_id": newDeviceID(t), "card": map[string]string{"tech": "iso14443a", "id": labCardHex(0)}}
		}, "ENR-NOT-FOUND"},
		{"undangan tidak sah", func(device string) map[string]any {
			return map[string]any{"device_id": device, "invitation": strings.Repeat("A", 42) + "w"}
		}, "ENR-INVITATION-INVALID"},
	}
	for _, c := range cases {
		for _, key := range []string{"", "tolak-" + strings.ReplaceAll(c.name, " ", "-")} {
			device := newDeviceID(t)
			rec := f.do(t, http.MethodPost, "/v1/enrollments", key, c.body(device))
			if rec.Code < 400 || problemType(t, rec) != c.want {
				t.Fatalf("%s (key %q): %d %s", c.name, key, rec.Code, rec.Body)
			}
			if n := f.deviceRows(t, device); n != 0 {
				t.Fatalf("%s (key %q): baris perangkat tertinggal: %d", c.name, key, n)
			}
		}
	}
}

func TestEnrolmentPerangkatBaruBersamaan(t *testing.T) {
	// Dua enrolment pertama dari perangkat baru yang sama berjalan bersamaan: keduanya berhasil dan
	// hanya satu baris perangkat dibuat.
	f := newFixture(t)
	device := newDeviceID(t)
	bodies := []map[string]any{f.cardBody(), f.cardBody()}
	codes := make([]int, len(bodies))
	var wg sync.WaitGroup
	for i, body := range bodies {
		body["device_id"] = device
		wg.Add(1)
		go func() {
			defer wg.Done()
			codes[i] = f.do(t, http.MethodPost, "/v1/enrollments", "", body).Code
		}()
	}
	wg.Wait()
	for i, code := range codes {
		if code != http.StatusCreated {
			t.Fatalf("enrolment %d: %d", i, code)
		}
	}
	if n := f.deviceRows(t, device); n != 1 {
		t.Fatalf("baris perangkat = %d, ingin 1", n)
	}
}

func TestPermintaanMenungguPerKartuDibatasi(t *testing.T) {
	// Review akhir #2 (ADR-0047): satu identitas kartu dengan device_id acak tidak bisa membanjiri antrean
	// persetujuan; batas 4 permintaan menunggu per kartu (default batas anggota FR-36).
	f := newFixture(t)
	card := map[string]string{"tech": "iso14443a", "id": labCardHex(0)}
	body := func(device string) map[string]any {
		return map[string]any{"device_id": device, "site_id": f.siteID, "card": card}
	}
	if rec := f.do(t, http.MethodPost, "/v1/enrollments", "", body(f.deviceID)); rec.Code != http.StatusCreated {
		t.Fatalf("pemegang pertama: %d %s", rec.Code, rec.Body)
	}
	var waiting []string
	for i := 0; i < 4; i++ {
		device := newDeviceID(t)
		rec := f.do(t, http.MethodPost, "/v1/enrollments", "", body(device))
		if _, status := enrolResult(t, rec.Body); rec.Code != http.StatusCreated || status != "PENDING_APPROVAL" {
			t.Fatalf("perangkat tambahan %d: %d %s", i+1, rec.Code, rec.Body)
		}
		waiting = append(waiting, device)
	}
	extra := newDeviceID(t)
	rec := f.do(t, http.MethodPost, "/v1/enrollments", "", body(extra))
	if rec.Code != http.StatusConflict || problemType(t, rec) != "ENR-PENDING-LIMIT" {
		t.Fatalf("permintaan ke-5: %d %s", rec.Code, rec.Body)
	}
	if n := f.deviceRows(t, extra); n != 0 {
		t.Fatalf("baris perangkat tertinggal setelah ENR-PENDING-LIMIT: %d", n)
	}
	// Perangkat yang sudah menunggu tetap bisa melanjutkan permintaannya (ADR-0034).
	rec = f.do(t, http.MethodPost, "/v1/enrollments", "", body(waiting[0]))
	if _, status := enrolResult(t, rec.Body); rec.Code != http.StatusOK || status != "PENDING_APPROVAL" {
		t.Fatalf("melanjutkan permintaan menunggu: %d %s", rec.Code, rec.Body)
	}
}
