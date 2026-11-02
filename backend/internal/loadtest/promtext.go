package loadtest

import (
	"strconv"
	"strings"
)

// Share adalah porsi permintaan satu rute yang selesai dalam batas tertentu, dari selisih dua eksposisi
// /metrics (ADR-0054): sisi server untuk dibandingkan dengan persentil sisi klien.
type Share struct {
	Route  string
	Count  uint64
	Within uint64
}

// Ratio = Within/Count; 0 bila tidak ada permintaan.
func (s Share) Ratio() float64 {
	if s.Count == 0 {
		return 0
	}
	return float64(s.Within) / float64(s.Count)
}

const durationMetric = "anastrophe_http_request_duration_seconds"

// ParseDurationShares menghitung, per rute, selisih _count dan selisih bucket le=<le> antara teks eksposisi
// sebelum dan sesudah run. Rute yang hanya ada di teks sesudah dihitung dari nol.
func ParseDurationShares(before, after, le string) map[string]Share {
	b, a := parseDuration(before, le), parseDuration(after, le)
	out := map[string]Share{}
	for route, now := range a {
		prev := b[route]
		if now.count < prev.count || now.within < prev.within {
			continue // server dimulai ulang di tengah run
		}
		out[route] = Share{Route: route, Count: now.count - prev.count, Within: now.within - prev.within}
	}
	return out
}

type durationCounts struct{ count, within uint64 }

func parseDuration(text, le string) map[string]durationCounts {
	out := map[string]durationCounts{}
	for _, line := range strings.Split(text, "\n") {
		var isBucket bool
		var rest string
		switch {
		case strings.HasPrefix(line, durationMetric+"_bucket{"):
			isBucket, rest = true, line[len(durationMetric+"_bucket{"):]
		case strings.HasPrefix(line, durationMetric+"_count{"):
			rest = line[len(durationMetric+"_count{"):]
		default:
			continue
		}
		labels, value, ok := parseLabels(rest)
		if !ok {
			continue
		}
		n, err := strconv.ParseUint(strings.TrimSpace(value), 10, 64)
		if err != nil {
			continue
		}
		route := labels["route"]
		c := out[route]
		if isBucket {
			if labels["le"] != le {
				continue
			}
			c.within = n
		} else {
			c.count = n
		}
		out[route] = c
	}
	return out
}

// parseLabels membaca `k="v",k2="v2"} nilai` dengan escape \\, \" dan \n; mengembalikan label dan teks nilai.
func parseLabels(s string) (map[string]string, string, bool) {
	labels := map[string]string{}
	for {
		if strings.HasPrefix(s, "}") {
			return labels, s[1:], true
		}
		eq := strings.Index(s, `="`)
		if eq <= 0 {
			return nil, "", false
		}
		key := strings.TrimPrefix(s[:eq], ",")
		s = s[eq+2:]
		var value strings.Builder
		closed := false
		for i := 0; i < len(s); i++ {
			switch c := s[i]; {
			case c == '\\' && i+1 < len(s):
				i++
				switch s[i] {
				case 'n':
					value.WriteByte('\n')
				default:
					value.WriteByte(s[i])
				}
			case c == '"':
				s, closed = s[i+1:], true
			default:
				value.WriteByte(c)
			}
			if closed {
				break
			}
		}
		if !closed {
			return nil, "", false
		}
		labels[key] = value.String()
	}
}
