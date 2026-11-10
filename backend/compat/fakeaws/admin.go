//go:build compat

package fakeaws

import (
	"encoding/json"
	"io"
	"log"
	"log/slog"
	"net/http"
)

// maxSecretSize は、登録を受ける秘密の値の大きさの上限である。Secrets Manager の上限と同じ 64KiB にする。
const maxSecretSize = 64 << 10

// putSecret は、比べる検査が、版の秘密の値を登録する口である。本文がそのまま秘密の値になる。
func (s *Server) putSecret(w http.ResponseWriter, r *http.Request) {
	value, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxSecretSize))
	if err != nil {
		http.Error(w, "秘密の値を読めません: "+err.Error(), http.StatusBadRequest)
		return
	}
	s.SetSecret(r.PathValue("version"), r.PathValue("name"), string(value))
	w.WriteHeader(http.StatusNoContent)
}

// listObjects は、比べる検査が、版が覚えているオブジェクトを読む口である。
func (s *Server) listObjects(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, s.Objects(r.PathValue("version")))
}

// listEmails は、比べる検査が、版が受けたメールを読む口である。
func (s *Server) listEmails(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, s.Emails(r.PathValue("version")))
}

// clearRecords は、比べる検査が、筋書きの始めにオブジェクトとメールを消す口である。
func (s *Server) clearRecords(w http.ResponseWriter, _ *http.Request) {
	s.ClearRecords()
	w.WriteHeader(http.StatusNoContent)
}

// notImplemented は、受けると決めていない S3 の操作とパスを、比べる検査で見つかるように 501 で断る。
func (s *Server) notImplemented(w http.ResponseWriter, r *http.Request) {
	s.reject(w, r, r.Method+" "+r.URL.Path)
}

// reject は、受けると決めていない操作を 501 で断り、比べる検査が見つけられるように fakeaws_unexpected_request をログに出す。
// operation は、断った操作の名前である。SES と Secrets Manager の操作の名前は、パスでなく本文とヘッダにある。
func (s *Server) reject(w http.ResponseWriter, r *http.Request, operation string) {
	slog.LogAttrs(r.Context(), slog.LevelWarn, "fakeaws_unexpected_request",
		slog.String("method", r.Method), slog.String("uri", r.URL.RequestURI()), slog.String("operation", operation))
	writeS3Error(w, http.StatusNotImplemented, "NotImplemented", "fakeaws はこの操作を受けません: "+operation, "")
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("fakeaws: 応答を書けません: %v", err)
	}
}
