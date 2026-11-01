package certs

import (
	"encoding/binary"
	"errors"
	"sort"
)

// CBOR minimal (RFC 8949) untuk CredentialCert: uint, nint, bstr, tstr, array, map
// berkunci integer (diurutkan menaik agar deterministik), dan tag. Encoding panjang
// selalu minimal, sama dengan scripts/anp1/lab_ca.py.

type tagged struct {
	tag   uint64
	value any
}

func head(major byte, n uint64) []byte {
	switch {
	case n < 24:
		return []byte{major<<5 | byte(n)}
	case n <= 0xFF:
		return []byte{major<<5 | 24, byte(n)}
	case n <= 0xFFFF:
		return binary.BigEndian.AppendUint16([]byte{major<<5 | 25}, uint16(n))
	case n <= 0xFFFFFFFF:
		return binary.BigEndian.AppendUint32([]byte{major<<5 | 26}, uint32(n))
	default:
		return binary.BigEndian.AppendUint64([]byte{major<<5 | 27}, n)
	}
}

func encode(v any) ([]byte, error) {
	switch x := v.(type) {
	case uint64:
		return head(0, x), nil
	case int64:
		if x >= 0 {
			return head(0, uint64(x)), nil
		}
		return head(1, uint64(-1-x)), nil
	case []byte:
		return append(head(2, uint64(len(x))), x...), nil
	case string:
		return append(head(3, uint64(len(x))), x...), nil
	case []any:
		out := head(4, uint64(len(x)))
		for _, item := range x {
			b, err := encode(item)
			if err != nil {
				return nil, err
			}
			out = append(out, b...)
		}
		return out, nil
	case map[int64]any:
		keys := make([]int64, 0, len(x))
		for k := range x {
			keys = append(keys, k)
		}
		sort.Slice(keys, func(i, j int) bool { return keys[i] < keys[j] })
		out := head(5, uint64(len(x)))
		for _, k := range keys {
			kb, _ := encode(k)
			vb, err := encode(x[k])
			if err != nil {
				return nil, err
			}
			out = append(append(out, kb...), vb...)
		}
		return out, nil
	case tagged:
		b, err := encode(x.value)
		if err != nil {
			return nil, err
		}
		return append(head(6, x.tag), b...), nil
	default:
		return nil, errors.New("cbor: tipe tidak didukung")
	}
}

var errCBOR = errors.New("cbor: data tidak valid")

func decode(data []byte) (any, error) {
	v, rest, err := decodeItem(data, 0)
	if err != nil {
		return nil, err
	}
	if len(rest) != 0 {
		return nil, errCBOR
	}
	return v, nil
}

func decodeItem(data []byte, depth int) (any, []byte, error) {
	if len(data) == 0 || depth > 8 {
		return nil, nil, errCBOR
	}
	major, info := data[0]>>5, data[0]&0x1F
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
	default:
		return nil, nil, errCBOR
	}
	switch major {
	case 0:
		return n, data, nil
	case 1:
		return -1 - int64(n), data, nil
	case 2, 3:
		if uint64(len(data)) < n {
			return nil, nil, errCBOR
		}
		if major == 2 {
			return append([]byte(nil), data[:n]...), data[n:], nil
		}
		return string(data[:n]), data[n:], nil
	case 4:
		items := make([]any, 0, min(n, 16))
		for i := uint64(0); i < n; i++ {
			item, rest, err := decodeItem(data, depth+1)
			if err != nil {
				return nil, nil, err
			}
			items, data = append(items, item), rest
		}
		return items, data, nil
	case 5:
		m := make(map[int64]any, min(n, 16))
		for i := uint64(0); i < n; i++ {
			k, rest, err := decodeItem(data, depth+1)
			if err != nil {
				return nil, nil, err
			}
			var key int64
			switch kk := k.(type) {
			case uint64:
				key = int64(kk)
			case int64:
				key = kk
			default:
				return nil, nil, errCBOR
			}
			v, rest, err := decodeItem(rest, depth+1)
			if err != nil {
				return nil, nil, err
			}
			m[key], data = v, rest
		}
		return m, data, nil
	case 6:
		v, rest, err := decodeItem(data, depth+1)
		if err != nil {
			return nil, nil, err
		}
		return tagged{tag: n, value: v}, rest, nil
	default:
		return nil, nil, errCBOR
	}
}
