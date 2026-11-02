package appattest

import (
	"encoding/binary"
	"fmt"
)

// pair dan cmap: map CBOR dengan urutan kunci tetap untuk test (Go map tidak berurutan).
type pair struct{ k, v any }
type cmap []pair

func cborHead(major byte, n uint64) []byte {
	switch {
	case n < 24:
		return []byte{major<<5 | byte(n)}
	case n <= 0xff:
		return []byte{major<<5 | 24, byte(n)}
	case n <= 0xffff:
		return binary.BigEndian.AppendUint16([]byte{major<<5 | 25}, uint16(n))
	case n <= 0xffff_ffff:
		return binary.BigEndian.AppendUint32([]byte{major<<5 | 26}, uint32(n))
	default:
		return binary.BigEndian.AppendUint64([]byte{major<<5 | 27}, n)
	}
}

// enc meng-encode subset CBOR yang dipakai App Attest (helper test, bukan kode produksi).
func enc(v any) []byte {
	switch x := v.(type) {
	case uint64:
		return cborHead(0, x)
	case int:
		if x < 0 {
			return cborHead(1, uint64(-1-x))
		}
		return cborHead(0, uint64(x))
	case int64:
		if x < 0 {
			return cborHead(1, uint64(-1-x))
		}
		return cborHead(0, uint64(x))
	case []byte:
		return append(cborHead(2, uint64(len(x))), x...)
	case string:
		return append(cborHead(3, uint64(len(x))), x...)
	case []any:
		out := cborHead(4, uint64(len(x)))
		for _, it := range x {
			out = append(out, enc(it)...)
		}
		return out
	case cmap:
		out := cborHead(5, uint64(len(x)))
		for _, p := range x {
			out = append(out, enc(p.k)...)
			out = append(out, enc(p.v)...)
		}
		return out
	}
	panic(fmt.Sprintf("enc: tipe %T", v))
}
