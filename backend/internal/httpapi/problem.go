package httpapi

import (
	"encoding/json"
	"net/http"
)

// Problem adalah error API RFC 9457. Type berisi kode katalog SDD §15 (mis. "ENR-LIMIT").
type Problem struct {
	Type   string `json:"type"`
	Title  string `json:"title,omitempty"`
	Status int    `json:"status"`
}

// NewProblem membuat Problem dengan judul baku dari kode status HTTP.
func NewProblem(code string, status int) Problem {
	return Problem{Type: code, Title: http.StatusText(status), Status: status}
}

// WriteProblem menulis Problem sebagai application/problem+json.
func WriteProblem(w http.ResponseWriter, p Problem) {
	w.Header().Set("Content-Type", "application/problem+json")
	w.WriteHeader(p.Status)
	_ = json.NewEncoder(w).Encode(p)
}

// WriteJSON menulis respons sukses.
func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
