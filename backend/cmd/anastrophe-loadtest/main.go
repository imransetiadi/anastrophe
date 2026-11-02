// Command anastrophe-loadtest menjalankan uji beban API Anastrophe (TC-PERF-05, ADR-0055). Hasil di laptop
// adalah baseline lab, bukan bukti produksi.
//
//	go -C backend run ./cmd/anastrophe-loadtest gen-cards -n 5000 > kartu-beban.csv
//	go -C backend run ./cmd/anastrophe-registry import --site <uuid> --file kartu-beban.csv --operator lab
//	go -C backend run ./cmd/anastrophe-loadtest run -base http://127.0.0.1:8080 -scenario enrol \
//	    -site <uuid> -cards kartu-beban.csv -duration 20s -concurrency 8 -metrics http://127.0.0.1:9090/metrics
//
// Skenario: config, lookup (-code), enrol (-site -cards), renew (-site -cards; -prepare kredensial
// disiapkan lebih dulu tanpa diukur). Hanya host loopback kecuali -allow-remote. Exit 1 bila tingkat galat
// melebihi -max-galat (bawaan 0,001 sesuai TC-PERF-05).
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"sort"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/loadtest"
)

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

const usage = "pemakaian: anastrophe-loadtest gen-cards [-n N] | run -base <url> -scenario config|lookup|enrol|renew [-duration 20s] [-concurrency 8] [-rate 0] [-site <uuid>] [-code <kode>] [-cards <csv>] [-prepare 100] [-metrics <url>] [-max-galat 0.001] [-allow-remote]"

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprintln(stderr, usage)
		return 2
	}
	switch args[0] {
	case "gen-cards":
		fs := flag.NewFlagSet("gen-cards", flag.ContinueOnError)
		fs.SetOutput(stderr)
		n := fs.Int("n", 1000, "jumlah kartu sintetis")
		if err := fs.Parse(args[1:]); err != nil {
			return 2
		}
		if err := loadtest.GenerateCards(stdout, *n); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return 0
	case "run":
		return runLoad(args[1:], stdout, stderr)
	default:
		fmt.Fprintln(stderr, usage)
		return 2
	}
}

func runLoad(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("run", flag.ContinueOnError)
	fs.SetOutput(stderr)
	base := fs.String("base", "", "alamat API, mis. http://127.0.0.1:8080")
	scenario := fs.String("scenario", "config", "config|lookup|enrol|renew")
	duration := fs.Duration("duration", 20*time.Second, "durasi pengukuran")
	concurrency := fs.Int("concurrency", 8, "jumlah pekerja")
	rate := fs.Float64("rate", 0, "batas iterasi per detik untuk semua pekerja (0 = tanpa batas)")
	site := fs.String("site", "", "site_id gedung kartu sintetis")
	code := fs.String("code", "", "kode gedung untuk skenario lookup")
	cardsFile := fs.String("cards", "", "CSV gen-cards yang sudah diimpor ke registri")
	prepare := fs.Int("prepare", 100, "jumlah kredensial yang disiapkan untuk skenario renew")
	metricsURL := fs.String("metrics", "", "URL /metrics listener internal (opsional)")
	maxErrors := fs.Float64("max-galat", 0.001, "batas tingkat galat; dilewati = exit 1")
	allowRemote := fs.Bool("allow-remote", false, "izinkan host bukan loopback (hati-hati: membebani server sungguhan)")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	fail := func(err error) int {
		fmt.Fprintln(stderr, "anastrophe-loadtest:", err)
		return 2
	}
	if err := checkTarget(*base, *allowRemote); err != nil {
		return fail(err)
	}
	if *metricsURL != "" {
		if err := checkTarget(*metricsURL, *allowRemote); err != nil {
			return fail(err)
		}
	}
	httpClient := &http.Client{Timeout: 30 * time.Second, Transport: &http.Transport{
		MaxIdleConns: 2 * max(*concurrency, 1), MaxIdleConnsPerHost: 2 * max(*concurrency, 1), IdleConnTimeout: 90 * time.Second,
	}}
	client := &loadtest.Client{Base: *base, HTTP: httpClient, SiteID: *site, JoinCode: *code, Creds: &loadtest.CredPool{}}
	if *cardsFile != "" {
		f, err := os.Open(*cardsFile)
		if err != nil {
			return fail(err)
		}
		client.Cards, err = loadtest.LoadCards(f)
		f.Close()
		if err != nil {
			return fail(err)
		}
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	var iteration loadtest.Iteration
	switch *scenario {
	case "config":
		iteration = client.Config
	case "lookup":
		if *code == "" {
			return fail(errors.New("skenario lookup butuh -code"))
		}
		iteration = client.Lookup
	case "enrol", "renew":
		if *site == "" || client.Cards == nil {
			return fail(errors.New("skenario " + *scenario + " butuh -site dan -cards"))
		}
		iteration = client.Enrol
		if *scenario == "renew" {
			setup := loadtest.NewRecorder()
			for client.Creds.Len() < *prepare {
				if err := client.Enrol(ctx, setup); err != nil {
					return fail(fmt.Errorf("menyiapkan kredensial: %w", err))
				}
			}
			iteration = client.Renew
		}
	default:
		return fail(errors.New("skenario tak dikenal: " + *scenario))
	}
	before := ""
	if *metricsURL != "" {
		before = fetch(ctx, httpClient, *metricsURL)
	}
	rec, elapsed := loadtest.Runner{Concurrency: *concurrency, Duration: *duration, Rate: *rate}.Run(ctx, iteration)
	summaries := rec.Summary()
	loadtest.Report(stdout, summaries, elapsed)
	if *metricsURL != "" {
		shares := loadtest.ParseDurationShares(before, fetch(ctx, httpClient, *metricsURL), "0.3")
		routes := make([]string, 0, len(shares))
		for r := range shares {
			routes = append(routes, r)
		}
		sort.Strings(routes)
		fmt.Fprintln(stdout, "server (histogram /metrics), porsi ≤ 0,3 dtk:")
		for _, r := range routes {
			if s := shares[r]; s.Count > 0 {
				fmt.Fprintf(stdout, "  %s: %.2f%% dari %d\n", r, 100*s.Ratio(), s.Count)
			}
		}
	}
	total, failed := 0, 0
	for _, s := range summaries {
		total += s.Count
		failed += s.Errors
	}
	if total > 0 && float64(failed)/float64(total) > *maxErrors {
		fmt.Fprintf(stderr, "tingkat galat %.3f%% melebihi batas %.3f%%\n", 100*float64(failed)/float64(total), 100**maxErrors)
		return 1
	}
	return 0
}

// checkTarget menolak host bukan loopback kecuali diizinkan eksplisit, agar server sungguhan tidak dibebani
// tanpa sengaja (ADR-0055).
func checkTarget(raw string, allowRemote bool) error {
	u, err := url.Parse(raw)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return errors.New("alamat harus http(s)://host[:port]")
	}
	if allowRemote {
		return nil
	}
	host := u.Hostname()
	if host == "localhost" {
		return nil
	}
	if ip := net.ParseIP(host); ip != nil && ip.IsLoopback() {
		return nil
	}
	return fmt.Errorf("host %q bukan loopback; pakai -allow-remote bila memang disengaja", host)
}

func fetch(ctx context.Context, c *http.Client, target string) string {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return ""
	}
	resp, err := c.Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	return string(raw)
}
