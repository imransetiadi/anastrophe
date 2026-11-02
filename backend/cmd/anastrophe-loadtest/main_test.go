package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestTolakHostNonLoopback(t *testing.T) {
	// ADR-0055: alat uji beban tidak boleh membebani server sungguhan tanpa sengaja.
	for _, base := range []string{"https://api.contoh.id", "http://10.0.0.5:8080", "http://192.168.1.10", "http://127.0.0.1.contoh.id"} {
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
	if code := run([]string{"gen-cards", "-n", "3"}, &out, &errOut); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	lines := strings.Split(strings.TrimSpace(out.String()), "\n")
	if len(lines) != 4 || lines[0] != "tech,card_id,holder_contact,zones" || !strings.HasPrefix(lines[1], "iso14443a,084c54") {
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
