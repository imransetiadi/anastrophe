// Package loadtest menjalankan uji beban API Anastrophe (TC-PERF-05, ADR-0055) dan merangkum latensi per
// langkah. Hasil di laptop adalah baseline lab, bukan bukti produksi.
package loadtest

import (
	"context"
	"errors"
	"math"
	"sort"
	"sync"
	"sync/atomic"
	"time"
)

// Step menjalankan satu permintaan HTTP dan mengembalikan statusnya (0 bila tidak ada respons). Galat berarti
// langkah gagal, termasuk status yang tidak diharapkan skenario.
type Step func(ctx context.Context) (int, error)

// ErrStop dikembalikan Iteration bila run tidak bisa berlanjut (mis. pool kartu habis): Runner berhenti
// memulai iterasi baru, alih-alih berputar tanpa henti.
var ErrStop = errors.New("loadtest: run dihentikan")

// Iteration adalah satu putaran skenario. Setiap langkah dicatat lewat rec.Measure; galat yang dikembalikan
// tidak dihitung ulang oleh Runner, jadi galat di luar langkah (mis. pool habis) dicatat sendiri oleh skenario.
type Iteration func(ctx context.Context, rec *Recorder) error

type sample struct {
	d      time.Duration
	status int
	failed bool
}

// Recorder mengumpulkan sampel latensi per langkah; aman dipakai bersamaan.
type Recorder struct {
	mu    sync.Mutex
	steps map[string][]sample
}

// NewRecorder membuat perekam kosong.
func NewRecorder() *Recorder { return &Recorder{steps: map[string][]sample{}} }

// Observe mencatat satu langkah.
func (r *Recorder) Observe(step string, d time.Duration, status int, err error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.steps[step] = append(r.steps[step], sample{d: d, status: status, failed: err != nil})
}

// Measure menjalankan fn, mengukur durasinya, dan mencatatnya di bawah nama langkah.
func (r *Recorder) Measure(ctx context.Context, step string, fn Step) (int, error) {
	start := time.Now()
	status, err := fn(ctx)
	r.Observe(step, time.Since(start), status, err)
	return status, err
}

// StepSummary merangkum satu langkah: jumlah, galat, status, dan persentil latensi.
type StepSummary struct {
	Step               string
	Count, Errors      int
	ByStatus           map[int]int
	P50, P95, P99, Max time.Duration
}

// Summary merangkum semua langkah, terurut menurut nama.
func (r *Recorder) Summary() []StepSummary {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]StepSummary, 0, len(r.steps))
	for name, samples := range r.steps {
		s := StepSummary{Step: name, Count: len(samples), ByStatus: map[int]int{}}
		durations := make([]time.Duration, len(samples))
		for i, x := range samples {
			durations[i] = x.d
			s.ByStatus[x.status]++
			if x.failed {
				s.Errors++
			}
		}
		sort.Slice(durations, func(i, j int) bool { return durations[i] < durations[j] })
		s.P50, s.P95, s.P99 = Percentile(durations, 50), Percentile(durations, 95), Percentile(durations, 99)
		if len(durations) > 0 {
			s.Max = durations[len(durations)-1]
		}
		out = append(out, s)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Step < out[j].Step })
	return out
}

// Percentile memakai metode nearest-rank pada sampel terurut: indeks ceil(p/100·n) − 1. Kosong → 0.
func Percentile(sorted []time.Duration, p float64) time.Duration {
	if len(sorted) == 0 {
		return 0
	}
	i := int(math.Ceil(p/100*float64(len(sorted)))) - 1
	return sorted[min(max(i, 0), len(sorted)-1)]
}

// Runner menjalankan Concurrency pekerja selama Duration. Saat durasi habis tidak ada iterasi baru yang dimulai,
// tetapi iterasi yang sedang berjalan diselesaikan dengan context pemanggil, agar permintaan yang terpotong
// tidak dihitung sebagai galat.
//
// Rate > 0 menjadwalkan token dengan selang tetap untuk semua pekerja. Token yang jatuh tempo saat semua pekerja
// masih sibuk dibuang dan dihitung Missed, bukan ditunda. Pekerja tetap closed-loop: latensi diukur dari awal
// permintaan, bukan dari jadwalnya, jadi server yang melambat menurunkan laju alih-alih menaikkan latensi
// (coordinated omission). Karena itu laju yang tidak tercapai harus terlihat dari Missed.
type Runner struct {
	Concurrency int
	Duration    time.Duration
	Rate        float64
}

// Result adalah hasil satu run. Dengan Rate > 0 setiap token terjadwal menjadi satu iterasi atau terlewat, jadi
// Iterations == Scheduled - Missed.
type Result struct {
	Recorder   *Recorder
	Elapsed    time.Duration
	Iterations int64 // iterasi yang dimulai
	Scheduled  int64 // token laju yang jatuh tempo selama run; 0 tanpa Rate
	Missed     int64 // token yang tidak diambil pekerja mana pun pada jadwalnya
	EarlyStop  error // galat ErrStop pertama bila iterasi menghentikan run; nil bila durasi habis atau context dibatalkan
}

// AchievedRate adalah jumlah iterasi per detik yang benar-benar dimulai.
func (r Result) AchievedRate() float64 {
	if r.Elapsed <= 0 {
		return 0
	}
	return float64(r.Iterations) / r.Elapsed.Seconds()
}

// MissedRatio adalah porsi token terjadwal yang terlewat; 0 tanpa Rate.
func (r Result) MissedRatio() float64 {
	if r.Scheduled == 0 {
		return 0
	}
	return float64(r.Missed) / float64(r.Scheduled)
}

// Run menjalankan iterasi sampai durasi habis, context dibatalkan, atau sebuah iterasi mengembalikan ErrStop.
func (r Runner) Run(ctx context.Context, it Iteration) Result {
	rec := NewRecorder()
	stop := make(chan struct{})
	var stopOnce sync.Once
	halt := func() { stopOnce.Do(func() { close(stop) }) }
	timer := time.AfterFunc(r.Duration, halt)
	defer timer.Stop()
	var iterations, scheduled, missed atomic.Int64
	var earlyStop error
	var earlyOnce sync.Once
	start := time.Now()
	var tokens chan struct{}
	var ticking sync.WaitGroup
	if r.Rate > 0 {
		tokens = make(chan struct{})
		interval := time.Duration(float64(time.Second) / r.Rate)
		ticking.Add(1)
		go func() {
			defer ticking.Done()
			next := start.Add(interval)
			tick := time.NewTimer(interval)
			defer tick.Stop()
			for {
				select {
				case <-stop:
					return
				case <-ctx.Done():
					return
				case <-tick.C:
				}
				select {
				case <-stop:
					return
				case <-ctx.Done():
					return
				default:
				}
				scheduled.Add(1)
				select {
				case tokens <- struct{}{}:
				default:
					missed.Add(1) // semua pekerja masih sibuk
				}
				next = next.Add(interval)
				tick.Reset(time.Until(next))
			}
		}()
	}
	var wg sync.WaitGroup
	for range max(r.Concurrency, 1) {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				if tokens != nil {
					select {
					case <-stop:
						return
					case <-ctx.Done():
						return
					case <-tokens:
					}
				} else {
					select {
					case <-stop:
						return
					case <-ctx.Done():
						return
					default:
					}
				}
				iterations.Add(1)
				if err := it(ctx, rec); errors.Is(err, ErrStop) {
					earlyOnce.Do(func() { earlyStop = err })
					halt()
					return
				}
			}
		}()
	}
	wg.Wait()
	elapsed := time.Since(start)
	ticking.Wait() // penjadwal ikut berhenti karena stop atau context, jadi hitungan token sudah final
	return Result{Recorder: rec, Elapsed: elapsed, Iterations: iterations.Load(), Scheduled: scheduled.Load(),
		Missed: missed.Load(), EarlyStop: earlyStop}
}
