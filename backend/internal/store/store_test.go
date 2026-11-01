package store

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/testpg"
)

func seed(t *testing.T, s *Store) (siteID, deviceID string) {
	t.Helper()
	ctx := context.Background()
	orgID, err := s.CreateOrganization(ctx, "Org Uji", "ID")
	if err != nil {
		t.Fatal(err)
	}
	siteID, err = s.CreateSite(ctx, orgID, "Menara Uji", "ID", "Asia/Jakarta", []byte{1, 2, 3, 4, 5, 6, 7, 8})
	if err != nil {
		t.Fatal(err)
	}
	deviceID, err = s.CreateDevice(ctx)
	if err != nil {
		t.Fatal(err)
	}
	return siteID, deviceID
}

func TestBatasDelapanKartu(t *testing.T) {
	// FR-15, TC-ENR-11 (sisi server).
	s := freshStore(t)
	siteID, deviceID := seed(t, s)
	ctx := context.Background()
	for i := 0; i < 8; i++ {
		if _, err := s.StartEnrollment(ctx, deviceID, siteID, time.Now()); err != nil {
			t.Fatalf("kartu ke-%d: %v", i+1, err)
		}
	}
	if _, err := s.StartEnrollment(ctx, deviceID, siteID, time.Now()); !errors.Is(err, ErrCardLimit) {
		t.Fatalf("kartu ke-9: err = %v, ingin ErrCardLimit", err)
	}
}

func TestRaceBatasDelapan(t *testing.T) {
	// Review Focus 3, TC-ENR-12 (uji beban): banyak permintaan paralel saat 7 kartu → tepat
	// satu sukses. Bukti deterministik protokol kunci ada di TestKunciPerangkatMenyerialkanPenambahan.
	const contenders = 6
	s := freshStore(t)
	siteID, deviceID := seed(t, s)
	ctx := context.Background()
	for i := 0; i < 7; i++ {
		if _, err := s.StartEnrollment(ctx, deviceID, siteID, time.Now()); err != nil {
			t.Fatal(err)
		}
	}
	warm := make([]interface{ Release() }, 0, contenders)
	for i := 0; i < contenders; i++ {
		conn, err := s.pool.Acquire(ctx)
		if err != nil {
			t.Fatal(err)
		}
		warm = append(warm, conn)
	}
	for _, conn := range warm {
		conn.Release()
	}
	start := make(chan struct{})
	var wg sync.WaitGroup
	results := make([]error, contenders)
	for i := range results {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			_, results[i] = s.StartEnrollment(ctx, deviceID, siteID, time.Now())
		}(i)
	}
	close(start)
	wg.Wait()
	successes := 0
	for _, err := range results {
		if err == nil {
			successes++
		} else if !errors.Is(err, ErrCardLimit) {
			t.Fatal(err)
		}
	}
	if successes != 1 {
		t.Fatalf("%d sukses dari %d kontender, ingin tepat 1", successes, contenders)
	}
	if n, err := s.ActiveCardCount(ctx, deviceID); err != nil || n != 8 {
		t.Fatalf("jumlah aktif = %d (err %v), ingin 8", n, err)
	}
}

func TestKunciPerangkatMenyerialkanPenambahan(t *testing.T) {
	// TC-ENR-12 secara deterministik: selama transaksi lain memegang kunci baris perangkat,
	// AddCardInstance harus menunggu, lalu melihat kartu ke-8 dan ditolak.
	s := freshStore(t)
	siteID, deviceID := seed(t, s)
	ctx := context.Background()
	for i := 0; i < 7; i++ {
		if _, err := s.StartEnrollment(ctx, deviceID, siteID, time.Now()); err != nil {
			t.Fatal(err)
		}
	}
	holder, err := s.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer holder.Rollback(ctx)
	var locked string
	if err := holder.QueryRow(ctx, `SELECT id FROM devices WHERE id = $1 FOR UPDATE`, deviceID).Scan(&locked); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		_, err := s.StartEnrollment(ctx, deviceID, siteID, time.Now())
		done <- err
	}()
	select {
	case err := <-done:
		t.Fatalf("penambahan paralel tidak menunggu kunci perangkat (err %v)", err)
	case <-time.After(300 * time.Millisecond):
	}
	if _, err := holder.Exec(ctx, `INSERT INTO card_instances (id, device_id, site_id, status) VALUES ($1, $2, $3, 'PROVISIONING')`, newUUID(), deviceID, siteID); err != nil {
		t.Fatal(err)
	}
	if err := holder.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-done; !errors.Is(err, ErrCardLimit) {
		t.Fatalf("err = %v, ingin ErrCardLimit", err)
	}
	if n, _ := s.ActiveCardCount(ctx, deviceID); n != 8 {
		t.Fatalf("jumlah aktif = %d, ingin 8", n)
	}
}

func TestIdempotentGagalTidakMenyimpanApaPun(t *testing.T) {
	// Temuan review I1: kredensial dan baris idempotency harus satu transaksi.
	s := freshStore(t)
	siteID, deviceID := seed(t, s)
	ctx := context.Background()
	cardID, err := s.StartEnrollment(ctx, deviceID, siteID, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	pub := append([]byte{0x04}, make([]byte, 64)...)
	_, _, err = s.Idempotent(ctx, "k-gagal", []byte("hash"), func(ctx context.Context, tx *Tx) (int, []byte, error) {
		if err := tx.SaveCredential(ctx, Credential{CardInstanceID: cardID, Channel: "ble", CredID: make([]byte, 16), PubKey: pub, Cert: []byte{1}, NotAfter: time.Now()}); err != nil {
			return 0, nil, err
		}
		return 0, nil, errors.New("koneksi klien putus")
	})
	if err == nil {
		t.Fatal("error dari fn harus diteruskan")
	}
	if n, _ := s.CredentialCount(ctx, cardID); n != 0 {
		t.Fatalf("kredensial tersimpan walau permintaan gagal: %d", n)
	}
	status, _, err := s.Idempotent(ctx, "k-gagal", []byte("hash"), func(ctx context.Context, tx *Tx) (int, []byte, error) {
		return 200, []byte("ok"), nil
	})
	if err != nil || status != 200 {
		t.Fatalf("retry setelah gagal harus dijalankan ulang: status %d err %v", status, err)
	}
}

func TestSatuKredensialAktifPerKanal(t *testing.T) {
	// Temuan review I2: satu card instance tidak boleh memegang banyak kredensial aktif per kanal.
	s := freshStore(t)
	siteID, deviceID := seed(t, s)
	ctx := context.Background()
	cardID, _ := s.StartEnrollment(ctx, deviceID, siteID, time.Now())
	pub := append([]byte{0x04}, make([]byte, 64)...)
	save := func(credByte byte) error {
		_, _, err := s.Idempotent(ctx, "k-"+string(rune('a'+credByte)), []byte{credByte}, func(ctx context.Context, tx *Tx) (int, []byte, error) {
			return 200, []byte("{}"), tx.SaveCredential(ctx, Credential{CardInstanceID: cardID, Channel: "ble", CredID: bytesOf(credByte), PubKey: pub, Cert: []byte{1}, NotAfter: time.Now()})
		})
		return err
	}
	if err := save(1); err != nil {
		t.Fatal(err)
	}
	if err := save(2); err == nil {
		t.Fatal("kredensial aktif kedua untuk kanal yang sama diterima")
	}
	if n, _ := s.CredentialCount(ctx, cardID); n != 1 {
		t.Fatalf("kredensial = %d, ingin 1", n)
	}
}

func TestPurgeIdempotencyKeys(t *testing.T) {
	// Minor 9: baris idempotency lama dibersihkan.
	s := freshStore(t)
	ctx := context.Background()
	if _, _, err := s.Idempotent(ctx, "lama", []byte("h"), func(context.Context, *Tx) (int, []byte, error) { return 200, []byte("{}"), nil }); err != nil {
		t.Fatal(err)
	}
	if n, err := s.PurgeIdempotencyKeys(ctx, time.Now().Add(time.Hour)); err != nil || n != 1 {
		t.Fatalf("dihapus = %d (err %v), ingin 1", n, err)
	}
	if n, _ := s.IdempotencyKeyCount(ctx); n != 0 {
		t.Fatalf("tersisa %d", n)
	}
}

func bytesOf(b byte) []byte {
	out := make([]byte, 16)
	out[15] = b
	return out
}

func TestMigrateParalelAman(t *testing.T) {
	// Minor 2: beberapa replika memigrasi database baru bersamaan.
	if adminDSN == "" {
		testpg.Skip(t, skipReason)
	}
	ctx := context.Background()
	dsn, err := testpg.NewDatabase(ctx, adminDSN)
	if err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	errs := make([]error, 4)
	for i := range errs {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			s, err := Open(ctx, dsn)
			if err != nil {
				errs[i] = err
				return
			}
			defer s.Close()
			errs[i] = s.Migrate(ctx)
		}(i)
	}
	wg.Wait()
	for i, err := range errs {
		if err != nil {
			t.Fatalf("replika %d: %v", i, err)
		}
	}
}

func TestMigrateDiDatabaseReadOnlyDilewati(t *testing.T) {
	// Minor 2: app yang diarahkan ke hot standby (read-only, ADR-0014) tetap bisa start.
	s := freshStore(t)
	ctx := context.Background()
	var name string
	if err := s.pool.QueryRow(ctx, `SELECT current_database()`).Scan(&name); err != nil {
		t.Fatal(err)
	}
	if _, err := s.pool.Exec(ctx, "ALTER DATABASE "+name+" SET default_transaction_read_only = on"); err != nil {
		t.Fatal(err)
	}
	ro, err := Open(ctx, strings.Replace(adminDSN, "/postgres?", "/"+name+"?", 1))
	if err != nil {
		t.Fatal(err)
	}
	defer ro.Close()
	if err := ro.Migrate(ctx); err != nil {
		t.Fatalf("migrasi di database read-only: %v", err)
	}
}

func TestMigrateIdempoten(t *testing.T) {
	s := freshStore(t)
	if err := s.Migrate(context.Background()); err != nil {
		t.Fatalf("migrasi kedua: %v", err)
	}
}
