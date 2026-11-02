package loadtest

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func ms(n int) time.Duration { return time.Duration(n) * time.Millisecond }

func TestPersentil(t *testing.T) {
	var sorted []time.Duration
	for i := 1; i <= 100; i++ {
		sorted = append(sorted, ms(i))
	}
	for p, want := range map[float64]time.Duration{50: ms(50), 95: ms(95), 99: ms(99), 100: ms(100)} {
		if got := Percentile(sorted, p); got != want {
			t.Errorf("p%v = %v, ingin %v", p, got, want)
		}
	}
	if got := Percentile([]time.Duration{ms(7)}, 95); got != ms(7) {
		t.Errorf("satu sampel: %v", got)
	}
	if got := Percentile(nil, 95); got != 0 {
		t.Errorf("kosong: %v", got)
	}
}

func TestRunnerBerhentiSaatDurasiHabis(t *testing.T) {
	var n atomic.Int64
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel() // runner yang tidak berhenti sendiri tetap dihentikan sesudah test gagal
	done := make(chan time.Duration, 1)
	start := time.Now()
	go func() {
		Runner{Concurrency: 4, Duration: ms(200)}.Run(ctx, func(ctx context.Context, rec *Recorder) error {
			time.Sleep(time.Millisecond)
			n.Add(1)
			return nil
		})
		done <- time.Since(start)
	}()
	select {
	case elapsed := <-done:
		if elapsed > ms(400) {
			t.Fatalf("runner berhenti sesudah %v", elapsed)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("runner tidak berhenti saat durasi habis")
	}
	if n.Load() == 0 {
		t.Fatal("tidak ada iterasi")
	}
}

func TestRunnerLaju(t *testing.T) {
	var n atomic.Int64
	Runner{Concurrency: 4, Duration: time.Second, Rate: 50}.Run(context.Background(), func(ctx context.Context, rec *Recorder) error {
		n.Add(1)
		return nil
	})
	if got := n.Load(); got > 54 || got < 25 {
		t.Fatalf("iterasi pada laju 50/dtk selama 1 dtk = %d", got)
	}
}

func TestRecorderGalatPerStatus(t *testing.T) {
	rec := NewRecorder()
	rec.Measure(context.Background(), "langkah", func(context.Context) (int, error) { return 201, nil })
	rec.Measure(context.Background(), "langkah", func(context.Context) (int, error) { return 500, errors.New("status 500") })
	rec.Measure(context.Background(), "langkah", func(context.Context) (int, error) { return 0, errors.New("koneksi ditolak") })
	s := rec.Summary()
	if len(s) != 1 || s[0].Count != 3 || s[0].Errors != 2 || s[0].ByStatus[201] != 1 || s[0].ByStatus[500] != 1 || s[0].ByStatus[0] != 1 {
		t.Fatalf("ringkasan = %+v", s)
	}
}

func TestLaporanTanpaRahasia(t *testing.T) {
	var buf bytes.Buffer
	Report(&buf, []StepSummary{{Step: "enrol.provisioning", Count: 10, Errors: 1, ByStatus: map[int]int{200: 9, 500: 1}, P50: ms(12), P95: ms(80), P99: ms(120), Max: ms(150)}}, 2*time.Second)
	out := buf.String()
	for _, want := range []string{"durasi 2.0 dtk", "langkah", "enrol.provisioning", "10", "5.0", "12ms", "80ms", "120ms", "150ms", "200:9 500:1"} {
		if !strings.Contains(out, want) {
			t.Fatalf("laporan tanpa %q:\n%s", want, out)
		}
	}
}

func TestRunnerBerhentiSaatErrStop(t *testing.T) {
	// Baseline lab ADR-0055: pool kartu habis membuat pekerja berputar tanpa henti; ErrStop menghentikan run.
	var n atomic.Int64
	start := time.Now()
	res := Runner{Concurrency: 4, Duration: 10 * time.Second}.Run(context.Background(), func(ctx context.Context, rec *Recorder) error {
		if n.Add(1) > 10 {
			return ErrStop
		}
		return nil
	})
	if !errors.Is(res.EarlyStop, ErrStop) {
		t.Fatalf("EarlyStop = %v, ingin ErrStop", res.EarlyStop)
	}
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("runner berhenti sesudah %v", elapsed)
	}
	if got := n.Load(); got > 10+4 {
		t.Fatalf("iterasi sesudah ErrStop = %d", got)
	}
}

func TestRunnerBerhentiSaatContextDibatalkan(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	time.AfterFunc(ms(100), cancel)
	start := time.Now()
	Runner{Concurrency: 4, Duration: 10 * time.Second, Rate: 1000}.Run(ctx, func(ctx context.Context, rec *Recorder) error { return nil })
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("runner berhenti sesudah %v walau context dibatalkan", elapsed)
	}
	start = time.Now()
	ctx2, cancel2 := context.WithCancel(context.Background())
	time.AfterFunc(ms(100), cancel2)
	Runner{Concurrency: 4, Duration: 10 * time.Second}.Run(ctx2, func(ctx context.Context, rec *Recorder) error { return nil })
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("runner tanpa laju berhenti sesudah %v walau context dibatalkan", elapsed)
	}
}

func TestRunnerMelaporkanIterasi(t *testing.T) {
	res := Runner{Concurrency: 2, Duration: ms(300), Rate: 100}.Run(context.Background(), func(ctx context.Context, rec *Recorder) error { return nil })
	if res.Scheduled < 25 || res.Scheduled > 31 || res.Missed > res.Scheduled/10 || res.Iterations != res.Scheduled-res.Missed || res.Elapsed <= 0 || res.Recorder == nil {
		t.Fatalf("hasil = %+v", res)
	}
	if res.EarlyStop != nil {
		t.Fatalf("EarlyStop = %v pada run yang selesai karena durasi", res.EarlyStop)
	}
}

func TestRunnerMenghitungTokenTerlewat(t *testing.T) {
	// Review akhir ADR-0055 (Important 3): pekerja yang jenuh tidak boleh diam-diam menurunkan laju.
	res := Runner{Concurrency: 1, Duration: ms(500), Rate: 100}.Run(context.Background(), func(ctx context.Context, rec *Recorder) error {
		time.Sleep(ms(50))
		return nil
	})
	if res.Scheduled < 40 || res.MissedRatio() < 0.5 || res.Iterations != res.Scheduled-res.Missed {
		t.Fatalf("hasil = %+v, rasio terlewat %.2f", res, res.MissedRatio())
	}
	if rate := res.AchievedRate(); rate < 10 || rate > 30 {
		t.Fatalf("laju tercapai = %.1f/dtk, ingin ±20", rate)
	}
}
