package appattest

import (
	"bytes"
	"errors"
	"testing"
)

func TestDecodeCBORLulus(t *testing.T) {
	data := enc(cmap{
		{"fmt", "apple-appattest"},
		{-2, []byte{1, 2}},
		{1, []any{uint64(5), -7, "x"}},
	})
	v, err := decodeCBOR(data)
	if err != nil {
		t.Fatal(err)
	}
	m, ok := v.(map[any]any)
	if !ok || len(m) != 3 {
		t.Fatalf("hasil = %#v", v)
	}
	if m["fmt"] != "apple-appattest" {
		t.Fatalf("fmt = %#v", m["fmt"])
	}
	if b, ok := m[int64(-2)].([]byte); !ok || !bytes.Equal(b, []byte{1, 2}) {
		t.Fatalf("kunci -2 = %#v", m[int64(-2)])
	}
	arr, ok := m[int64(1)].([]any) // kunci uint dinormalkan ke int64
	if !ok || len(arr) != 3 || arr[0] != uint64(5) || arr[1] != int64(-7) || arr[2] != "x" {
		t.Fatalf("kunci 1 = %#v", m[int64(1)])
	}
}

func TestDecodeCBORMenolak(t *testing.T) {
	nested := bytes.Repeat([]byte{0x81}, 10)
	for name, data := range map[string][]byte{
		"terpotong":             {0x45, 1, 2, 3},
		"kosong":                {},
		"byte_tak_tentu":        {0x5f, 0x41, 0x00, 0xff},
		"array_tak_tentu":       {0x9f, 0x00, 0xff},
		"kedalaman_berlebih":    append(nested, 0x00),
		"kunci_duplikat":        {0xa2, 0x61, 'a', 0x01, 0x61, 'a', 0x02},
		"sisa_byte":             {0x01, 0x00},
		"tag":                   {0xc1, 0x00},
		"simple_true":           {0xf5},
		"float_half":            {0xf9, 0x00, 0x00},
		"panjang_byte_2^32":     {0x5a, 0xff, 0xff, 0xff, 0xff},
		"panjang_8_byte":        {0x5b, 0, 0, 0, 1, 0, 0, 0, 0},
		"utf8_rusak":            {0x62, 0xff, 0xfe},
		"kunci_map_byte":        {0xa1, 0x41, 0x00, 0x01},
		"array_lebih_dari_data": {0x9a, 0x00, 0x01, 0x00, 0x00},
		"map_lebih_dari_data":   {0xba, 0x00, 0x01, 0x00, 0x00},
		"info_cadangan":         {0x1c},
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := decodeCBOR(data); err == nil {
				t.Fatalf("data %x diterima", data)
			} else if errors.Is(err, ErrInvalid) {
				t.Fatalf("decoder mentah tidak membungkus ErrInvalid; pemanggil yang memberi alasan: %v", err)
			}
		})
	}
}
