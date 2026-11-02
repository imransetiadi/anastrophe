package appattest

import (
	"errors"
	"math"
	"unicode/utf8"
)

// maxCBORDepth membatasi sarang array/map; objek App Attest paling dalam tiga tingkat.
const maxCBORDepth = 8

// maxCBORItems membatasi jumlah item per objek (attestation contoh Apple ±13, kunci COSE 11). Tanpa batas
// ini, banyak item kecil yang sah di dalam 64 KiB memperbesar alokasi ±133× (review akhir ADR-0052).
const maxCBORItems = 128

var errCBOR = errors.New("cbor tidak valid")

// decodeCBOR mengurai tepat satu item CBOR (RFC 8949) dari subset yang dipakai App Attest: uint, negint,
// byte string, teks, array, dan map berkunci teks atau integer (kunci integer dinormalkan ke int64). Tag,
// float, simple value, panjang tak tentu, kunci duplikat, sarang lebih dari maxCBORDepth, lebih dari
// maxCBORItems item, dan sisa byte ditolak. Encoding bukan-terpendek diterima: integritas objek dijaga tanda
// tangan, bukan bentuk CBOR.
func decodeCBOR(data []byte) (any, error) {
	budget := maxCBORItems
	v, rest, err := cborItem(data, 0, &budget)
	if err != nil {
		return nil, err
	}
	if len(rest) != 0 {
		return nil, errCBOR
	}
	return v, nil
}

// cborPrefix mengurai satu item di awal data dan mengembalikan sisanya (kunci COSE di authData).
func cborPrefix(data []byte) (any, []byte, error) {
	budget := maxCBORItems
	return cborItem(data, 0, &budget)
}

func cborItem(data []byte, depth int, budget *int) (any, []byte, error) {
	*budget--
	if len(data) == 0 || depth > maxCBORDepth || *budget < 0 {
		return nil, nil, errCBOR
	}
	major, info := data[0]>>5, data[0]&0x1f
	data = data[1:]
	var n uint64
	switch {
	case info < 24:
		n = uint64(info)
	case info <= 27:
		size := 1 << (info - 24)
		if len(data) < size {
			return nil, nil, errCBOR
		}
		for _, b := range data[:size] {
			n = n<<8 | uint64(b)
		}
		data = data[size:]
	default: // 28–30 cadangan, 31 panjang tak tentu
		return nil, nil, errCBOR
	}
	switch major {
	case 0:
		return n, data, nil
	case 1:
		if n > math.MaxInt64 {
			return nil, nil, errCBOR
		}
		return -1 - int64(n), data, nil
	case 2, 3:
		// Panjang dicek terhadap sisa data sebelum menyalin, jadi panjang palsu tidak memicu alokasi besar.
		if n > uint64(len(data)) {
			return nil, nil, errCBOR
		}
		if major == 3 {
			if !utf8.Valid(data[:n]) {
				return nil, nil, errCBOR
			}
			return string(data[:n]), data[n:], nil
		}
		return append([]byte(nil), data[:n]...), data[n:], nil
	case 4:
		if n > uint64(len(data)) { // setiap item minimal 1 byte
			return nil, nil, errCBOR
		}
		items := make([]any, 0, min(n, 16))
		for i := uint64(0); i < n; i++ {
			v, rest, err := cborItem(data, depth+1, budget)
			if err != nil {
				return nil, nil, err
			}
			items, data = append(items, v), rest
		}
		return items, data, nil
	case 5:
		if n > uint64(len(data))/2 { // setiap pasangan minimal 2 byte
			return nil, nil, errCBOR
		}
		m := make(map[any]any, min(n, 16))
		for i := uint64(0); i < n; i++ {
			k, rest, err := cborItem(data, depth+1, budget)
			if err != nil {
				return nil, nil, err
			}
			switch kk := k.(type) {
			case string, int64:
			case uint64:
				if kk > math.MaxInt64 {
					return nil, nil, errCBOR
				}
				k = int64(kk)
			default:
				return nil, nil, errCBOR
			}
			if _, duplicate := m[k]; duplicate {
				return nil, nil, errCBOR
			}
			v, rest, err := cborItem(rest, depth+1, budget)
			if err != nil {
				return nil, nil, err
			}
			m[k], data = v, rest
		}
		return m, data, nil
	default: // 6 tag, 7 float/simple
		return nil, nil, errCBOR
	}
}
