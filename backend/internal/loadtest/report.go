package loadtest

import (
	"fmt"
	"io"
	"sort"
	"strconv"
	"strings"
	"text/tabwriter"
	"time"
)

// Report menulis ringkasan per langkah: jumlah, galat, laju, persentil, dan sebaran status. Hanya nama
// langkah dan angka yang ditulis, tidak pernah isi permintaan.
func Report(w io.Writer, summaries []StepSummary, elapsed time.Duration) {
	fmt.Fprintf(w, "durasi %.1f dtk\n", elapsed.Seconds())
	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "langkah\tjumlah\tgalat\trps\tp50\tp95\tp99\tmaks\tstatus")
	for _, s := range summaries {
		rps := 0.0
		if elapsed > 0 {
			rps = float64(s.Count) / elapsed.Seconds()
		}
		fmt.Fprintf(tw, "%s\t%d\t%d\t%.1f\t%s\t%s\t%s\t%s\t%s\n", s.Step, s.Count, s.Errors, rps,
			round(s.P50), round(s.P95), round(s.P99), round(s.Max), statuses(s.ByStatus))
	}
	_ = tw.Flush()
}

func round(d time.Duration) time.Duration {
	if d >= time.Millisecond {
		return d.Round(time.Millisecond)
	}
	return d.Round(time.Microsecond)
}

func statuses(by map[int]int) string {
	codes := make([]int, 0, len(by))
	for c := range by {
		codes = append(codes, c)
	}
	sort.Ints(codes)
	parts := make([]string, len(codes))
	for i, c := range codes {
		parts[i] = strconv.Itoa(c) + ":" + strconv.Itoa(by[c])
	}
	return strings.Join(parts, " ")
}
