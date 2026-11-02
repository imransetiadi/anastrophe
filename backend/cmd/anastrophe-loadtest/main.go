// Command anastrophe-loadtest menjalankan uji beban API Anastrophe (TC-PERF-05, ADR-0055). Hasil di laptop
// adalah baseline lab, bukan bukti produksi.
//
//	go -C backend run ./cmd/anastrophe-loadtest gen-cards -n 5000 [-offset 0] > kartu-beban.csv
//	go -C backend run ./cmd/anastrophe-registry import --site <uuid> --file "$PWD/kartu-beban.csv" --operator lab
//	go -C backend run ./cmd/anastrophe-loadtest run -base http://127.0.0.1:8080 -scenario enrol \
//	    -site <uuid> -cards "$PWD/kartu-beban.csv" -duration 20s -concurrency 8 -metrics http://127.0.0.1:9090/metrics
//
// Skenario: config, lookup (-code), enrol (-site -cards), renew (-site -cards; -prepare kredensial
// disiapkan lebih dulu tanpa diukur). Hanya host loopback kecuali -allow-remote; redirect tidak diikuti.
//
// Pekerja closed-loop: tanpa -rate setiap pekerja langsung memulai iterasi berikutnya. Dengan -rate, token yang
// jatuh tempo saat semua pekerja sibuk dihitung terlewat.
//
// Exit 1 bila tingkat galat mencapai -max-galat (bawaan 0,001: TC-PERF-05 menuntut < 0,1%) atau lebih dari 5%
// token laju terlewat; exit 3 bila run berhenti lebih awal (pool kartu atau kredensial habis); exit 2 untuk
// galat pemakaian.
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
	"strings"
	"time"

	"github.com/imransetiadi/anastrophe/backend/internal/loadtest"
)

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

const usage = "pemakaian: anastrophe-loadtest gen-cards [-n N] [-offset N] | run -base <url> -scenario config|lookup|enrol|renew [-duration 20s] [-concurrency 8] [-rate 0] [-site <uuid>] [-code <kode>] [-cards <csv>] [-prepare 100] [-metrics <url>] [-max-galat 0.001] [-allow-remote]"

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
		offset := fs.Int("offset", 0, "nomor kartu pertama; run berurutan butuh rentang terpisah")
		if err := fs.Parse(args[1:]); err != nil {
			return 2
		}
		if err := loadtest.GenerateCards(stdout, *n, *offset); err != nil {
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
	maxErrors := fs.Float64("max-galat", 0.001, "tingkat galat harus di bawah batas ini (0 = tanpa galat); dicapai = exit 1")
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
	},
		// Tujuan redirect bisa melewati penjaga loopback, dan satu sampel menjadi dua permintaan; 3xx dihitung galat.
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	client := &loadtest.Client{Base: strings.TrimRight(*base, "/"), HTTP: httpClient, SiteID: *site, JoinCode: *code, Creds: &loadtest.CredPool{}}
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
	var before string
	var metricsErr error
	if *metricsURL != "" {
		before, metricsErr = fetch(ctx, httpClient, *metricsURL)
	}
	res := loadtest.Runner{Concurrency: *concurrency, Duration: *duration, Rate: *rate}.Run(ctx, iteration)
	summaries := res.Recorder.Summary()
	loadtest.Report(stdout, summaries, res.Elapsed)
	if *rate > 0 {
		fmt.Fprintf(stdout, "laju: target %.1f/dtk, tercapai %.1f/dtk; %d dari %d token terlewat karena semua pekerja sibuk\n",
			*rate, res.AchievedRate(), res.Missed, res.Scheduled)
	}
	var after string
	if *metricsURL != "" && metricsErr == nil {
		after, metricsErr = fetch(ctx, httpClient, *metricsURL)
	}
	if metricsErr != nil {
		fmt.Fprintf(stdout, "metrik server tidak tersedia (%v); porsi ≤ 0,3 dtk dari server tidak dihitung\n", metricsErr)
	} else if *metricsURL != "" {
		shares := loadtest.ParseDurationShares(before, after, "0.3")
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
	exitCode := 0
	if errorRateExceeded(failed, total, *maxErrors) {
		fmt.Fprintf(stderr, "tingkat galat %.3f%% tidak di bawah batas %.3f%%\n", 100*float64(failed)/float64(total), 100**maxErrors)
		exitCode = 1
	}
	if res.MissedRatio() > maxMissedRatio {
		fmt.Fprintf(stderr, "laju target tidak tercapai: %.1f%% token terlewat (batas %.0f%%); naikkan -concurrency atau turunkan -rate\n",
			100*res.MissedRatio(), 100*maxMissedRatio)
		exitCode = 1
	}
	if res.EarlyStop != nil {
		fmt.Fprintf(stderr, "run berhenti lebih awal sesudah %.1f dari %.1f dtk: %v\n", res.Elapsed.Seconds(), duration.Seconds(), res.EarlyStop)
		exitCode = 3
	}
	return exitCode
}

// maxMissedRatio: lebih dari 5% token terlewat berarti laju target tidak diuji.
const maxMissedRatio = 0.05

// errorRateExceeded: TC-PERF-05 menuntut galat < 0,1%, jadi tepat di batas sudah gagal. Batas 0 berarti tanpa
// galat sama sekali.
func errorRateExceeded(failed, total int, limit float64) bool {
	return failed > 0 && float64(failed)/float64(total) >= limit
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

func fetch(ctx context.Context, c *http.Client, target string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return "", err
	}
	resp, err := c.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("status %d", resp.StatusCode)
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	return string(raw), err
}
