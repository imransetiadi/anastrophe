package loadtest

import (
	"math"
	"testing"
)

func TestPorsiDariMetrik(t *testing.T) {
	before := `# TYPE anastrophe_http_request_duration_seconds histogram
anastrophe_http_request_duration_seconds_bucket{route="GET /v1/config",le="0.25"} 9
anastrophe_http_request_duration_seconds_bucket{route="GET /v1/config",le="0.3"} 10
anastrophe_http_request_duration_seconds_bucket{route="GET /v1/config",le="0.5"} 10
anastrophe_http_request_duration_seconds_bucket{route="GET /v1/config",le="+Inf"} 10
anastrophe_http_request_duration_seconds_count{route="GET /v1/config"} 10
`
	// Bucket sesudah 0.3 (0.5, +Inf) selalu ada di eksposisi nyata dan tidak boleh menimpa porsi.
	after := `anastrophe_http_request_duration_seconds_bucket{route="GET /v1/config",le="0.3"} 105
anastrophe_http_request_duration_seconds_bucket{route="GET /v1/config",le="0.5"} 109
anastrophe_http_request_duration_seconds_bucket{route="GET /v1/config",le="+Inf"} 110
anastrophe_http_request_duration_seconds_count{route="GET /v1/config"} 110
anastrophe_http_request_duration_seconds_bucket{route="POST /v1/x \"q\" \\ y",le="0.3"} 3
anastrophe_http_request_duration_seconds_count{route="POST /v1/x \"q\" \\ y"} 4
anastrophe_http_requests_total{route="GET /v1/config",status="200"} 110
`
	shares := ParseDurationShares(before, after, "0.3")
	cfg := shares["GET /v1/config"]
	if cfg.Count != 100 || cfg.Within != 95 || math.Abs(cfg.Ratio()-0.95) > 1e-9 {
		t.Fatalf("config = %+v", cfg)
	}
	baru := shares[`POST /v1/x "q" \ y`]
	if baru.Count != 4 || baru.Within != 3 {
		t.Fatalf("rute baru (label ter-escape) = %+v; semua: %v", baru, shares)
	}
	if len(shares) != 2 {
		t.Fatalf("rute = %v", shares)
	}
	if (Share{}).Ratio() != 0 {
		t.Fatal("rasio tanpa permintaan harus 0")
	}
}
