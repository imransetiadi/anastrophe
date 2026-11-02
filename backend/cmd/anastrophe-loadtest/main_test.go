package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func TestTolakHostNonLoopback(t *testing.T) {
	// ADR-0055: alat uji beban tidak boleh membebani server sungguhan tanpa sengaja.
	for _, base := range []string{"https://api.contoh.id", "http://10.0.0.5:8080", "http://192.168.1.10", "http://127.0.0.1.contoh.id", "http://127.0.0.1@contoh.id"} {
		if err := checkTarget(base, false); err == nil {
			t.Errorf("%s diterima tanpa -allow-remote", base)
		}
		if err := checkTarget(base, true); err != nil {
			t.Errorf("%s ditolak dengan -allow-remote: %v", base, err)
		}
	}
	for _, base := range []string{"http://127.0.0.1:8080", "http://localhost:8080", "http://[::1]:8080", "http://127.0.0.2"} {
		if err := checkTarget(base, false); err != nil {
			t.Errorf("%s ditolak: %v", base, err)
		}
	}
	if err := checkTarget("ftp://127.0.0.1", true); err == nil {
		t.Error("skema bukan http(s) diterima")
	}
}

func TestGenCardsCLI(t *testing.T) {
	var out, errOut bytes.Buffer
	if code := run([]string{"gen-cards", "-n", "3", "-offset", "100000"}, &out, &errOut); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	lines := strings.Split(strings.TrimSpace(out.String()), "\n")
	if len(lines) != 4 || lines[0] != "tech,card_id,holder_contact,zones" || !strings.HasPrefix(lines[1], "iso14443a,084c54000186a0") {
		t.Fatalf("keluaran = %q", out.String())
	}
}

func TestRunConfigSingkat(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/config" {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{}`))
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	t.Cleanup(server.Close)
	var out, errOut bytes.Buffer
	code := run([]string{"run", "-base", server.URL, "-scenario", "config", "-duration", "200ms", "-concurrency", "2"}, &out, &errOut)
	if code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	if !strings.Contains(out.String(), "config") || !strings.Contains(out.String(), "200:") {
		t.Fatalf("laporan = %q", out.String())
	}
}

func TestRunMenolakTargetRemote(t *testing.T) {
	var out, errOut bytes.Buffer
	if code := run([]string{"run", "-base", "https://api.contoh.id", "-scenario", "config"}, &out, &errOut); code == 0 {
		t.Fatal("target remote diterima")
	}
}

func TestRunGagalBilaGalatMelebihiBatas(t *testing.T) {
	// TC-PERF-05: galat < 0,1%; server yang selalu 500 harus membuat alat keluar dengan kode 1.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	t.Cleanup(server.Close)
	var out, errOut bytes.Buffer
	if code := run([]string{"run", "-base", server.URL, "-scenario", "config", "-duration", "100ms", "-concurrency", "1"}, &out, &errOut); code != 1 {
		t.Fatalf("exit %d, ingin 1: %s", code, errOut.String())
	}
	if !strings.Contains(errOut.String(), "tingkat galat") {
		t.Fatalf("stderr = %q", errOut.String())
	}
}

func TestRunTidakMengikutiRedirect(t *testing.T) {
	// Review akhir ADR-0055 (Important 1): redirect ke host lain melewati penjaga loopback; 3xx harus galat.
	var remoteHits int
	remote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		remoteHits++
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(remote.Close)
	local := httptest.NewServer(http.RedirectHandler(remote.URL+"/v1/config", http.StatusFound))
	t.Cleanup(local.Close)
	var out, errOut bytes.Buffer
	if code := run([]string{"run", "-base", local.URL, "-scenario", "config", "-duration", "100ms", "-concurrency", "1"}, &out, &errOut); code != 1 {
		t.Fatalf("exit %d, ingin 1 (3xx = galat): %s %s", code, out.String(), errOut.String())
	}
	if remoteHits != 0 || !strings.Contains(out.String(), "302:") {
		t.Fatalf("redirect diikuti: %d hit ke host lain; laporan %q", remoteHits, out.String())
	}
}

func TestRunBaseGarisMiringDiakhir(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/config" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(server.Close)
	var out, errOut bytes.Buffer
	if code := run([]string{"run", "-base", server.URL + "/", "-scenario", "config", "-duration", "100ms", "-concurrency", "1"}, &out, &errOut); code != 0 {
		t.Fatalf("exit %d: %s %s", code, out.String(), errOut.String())
	}
}

func TestRunGagalBilaLajuTidakTercapai(t *testing.T) {
	// Review akhir ADR-0055 (Important 3): laju target yang tidak tercapai harus terlihat dan gagal.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		time.Sleep(50 * time.Millisecond)
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(server.Close)
	var out, errOut bytes.Buffer
	code := run([]string{"run", "-base", server.URL, "-scenario", "config", "-duration", "500ms", "-concurrency", "1", "-rate", "100"}, &out, &errOut)
	if code != 1 || !strings.Contains(out.String(), "tercapai") || !strings.Contains(errOut.String(), "laju") {
		t.Fatalf("exit %d; laporan %q; stderr %q", code, out.String(), errOut.String())
	}
}

func TestRunMetrikGagalTerlihat(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/config" {
			w.WriteHeader(http.StatusOK)
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	t.Cleanup(server.Close)
	var out, errOut bytes.Buffer
	code := run([]string{"run", "-base", server.URL, "-scenario", "config", "-duration", "100ms", "-concurrency", "1", "-metrics", server.URL + "/metrics"}, &out, &errOut)
	if code != 0 || !strings.Contains(out.String(), "metrik server tidak tersedia") || strings.Contains(out.String(), "porsi ≤ 0,3 dtk:\n  ") {
		t.Fatalf("exit %d; laporan %q", code, out.String())
	}
}

func TestRunBerhentiLebihAwalTerlihat(t *testing.T) {
	// -prepare 0: renew tanpa kredensial berhenti segera dengan exit 3, bukan berputar atau lolos.
	var out, errOut bytes.Buffer
	cards := t.TempDir() + "/kartu.csv"
	if err := os.WriteFile(cards, []byte("tech,card_id,holder_contact,zones\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	code := run([]string{"run", "-base", "http://127.0.0.1:1", "-scenario", "renew", "-site", "x", "-cards", cards, "-prepare", "0", "-duration", "200ms", "-concurrency", "1"}, &out, &errOut)
	if code != 3 || !strings.Contains(errOut.String(), "berhenti lebih awal") {
		t.Fatalf("exit %d; stderr %q", code, errOut.String())
	}
}

func TestBatasGalatInklusif(t *testing.T) {
	// TC-PERF-05: galat harus < 0,1%; tepat 0,1% gagal.
	if !errorRateExceeded(1, 1000, 0.001) || errorRateExceeded(0, 1000, 0.001) || errorRateExceeded(0, 0, 0.001) {
		t.Fatal("batas galat tidak inklusif")
	}
	// -max-galat 0 berarti tanpa galat sama sekali, bukan batas yang mustahil dipenuhi.
	if errorRateExceeded(0, 1000, 0) || !errorRateExceeded(1, 1000, 0) {
		t.Fatal("-max-galat 0 salah tafsir")
	}
}
