package middleware_test

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/middleware"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/logging"
)

const javaUnexpected = `{"message":"予期せぬエラーが発生しました。","errors":{}}`

// newLogger は、ログを logs に書くロガーを作る。
func newLogger() (*bytes.Buffer, *slog.Logger) {
	logs := &bytes.Buffer{}
	return logs, logging.New(logs, logging.Options{Service: logging.Service{Name: "keirekipro"}})
}

// records は、書かれたログを1行ずつ JSON として読む。
func records(t *testing.T, logs *bytes.Buffer) []map[string]any {
	t.Helper()
	var lines []map[string]any
	for line := range strings.SplitSeq(strings.TrimSpace(logs.String()), "\n") {
		if line == "" {
			continue
		}
		var record map[string]any
		if err := json.Unmarshal([]byte(line), &record); err != nil {
			t.Fatalf("ログの行 %q を読めません: %v", line, err)
		}
		lines = append(lines, record)
	}
	return lines
}

// field は、入れ子の項目を、点で区切った名前で取り出す。
func field(record map[string]any, path string) any {
	var current any = record
	for name := range strings.SplitSeq(path, ".") {
		next, ok := current.(map[string]any)
		if !ok {
			return nil
		}
		current = next[name]
	}
	return current
}

// 誤りの本文が、Java 版の AppExceptionHandler と同じ形であることを確かめる。
func TestWriteError_JavaBody(t *testing.T) {
	rec := httptest.NewRecorder()
	middleware.WriteError(rec, http.StatusBadRequest, middleware.MessageBadRequest)
	if rec.Code != http.StatusBadRequest || rec.Header().Get("Content-Type") != "application/json" ||
		rec.Body.String() != `{"message":"入力エラーがあります。","errors":{}}` {
		t.Errorf("WriteError = %d %q %s", rec.Code, rec.Header().Get("Content-Type"), rec.Body.String())
	}

	rec = httptest.NewRecorder()
	middleware.WriteMessage(rec, http.StatusNotImplemented, `"引用符"`)
	if rec.Code != http.StatusNotImplemented || rec.Header().Get("Content-Type") != "application/json" ||
		rec.Body.String() != `{"message":"\"引用符\""}` {
		t.Errorf("WriteMessage = %d %q %s", rec.Code, rec.Header().Get("Content-Type"), rec.Body.String())
	}
}

// パニックを受け止めて 500 と Java 版の本文を返し、スタックを ERROR のログに書くことを確かめる。
func TestRecover_PanicReturns500(t *testing.T) {
	logs, logger := newLogger()
	handler := middleware.Recover(logger)(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic("想定外の状態")
	}))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))

	if rec.Code != http.StatusInternalServerError || rec.Body.String() != javaUnexpected {
		t.Errorf("応答 = %d %s, want 500 と Java 版の本文", rec.Code, rec.Body.String())
	}
	lines := records(t, logs)
	if len(lines) != 1 {
		t.Fatalf("ログ = %v, want 1行", lines)
	}
	stack, _ := field(lines[0], "error.stack_trace").(string)
	if lines[0]["message"] != "unexpected_exception" || field(lines[0], "log.level") != "ERROR" ||
		field(lines[0], "error.message") != "panic: 想定外の状態" || !strings.Contains(stack, "goroutine") {
		t.Errorf("ログ = %v, want ERROR の unexpected_exception と誤りの文とスタック", lines[0])
	}
}

// 応答を書き始めたあとのパニックでは、本文を書き足さずにログだけを書くことを確かめる。
func TestRecover_AfterWriteLogsOnly(t *testing.T) {
	for name, write := range map[string]func(http.ResponseWriter){
		"ヘッダを書いたあと": func(w http.ResponseWriter) { w.WriteHeader(http.StatusAccepted) },
		"本文を書いたあと":  func(w http.ResponseWriter) { _, _ = w.Write([]byte("途中")) },
	} {
		t.Run(name, func(t *testing.T) {
			logs, logger := newLogger()
			handler := middleware.Recover(logger)(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				write(w)
				panic("書いたあとのパニック")
			}))
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
			if strings.Contains(rec.Body.String(), "予期せぬエラー") {
				t.Errorf("本文 = %s, want 書き足さない", rec.Body.String())
			}
			if len(records(t, logs)) != 1 {
				t.Errorf("ログ = %s, want 1行", logs.String())
			}
		})
	}
}

// net/http が応答を打ち切るためのパニックは、受け止めずに投げ直すことを確かめる。
func TestRecover_RethrowsAbortHandler(t *testing.T) {
	logs, logger := newLogger()
	handler := middleware.Recover(logger)(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic(http.ErrAbortHandler)
	}))
	defer func() {
		if recovered := recover(); recovered != http.ErrAbortHandler {
			t.Errorf("投げ直したもの = %v, want http.ErrAbortHandler", recovered)
		}
		if logs.Len() != 0 {
			t.Errorf("ログ = %s, want なし", logs.String())
		}
	}()
	handler.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/", nil))
	t.Error("パニックが投げ直されませんでした")
}

// requestLogged は、RequestLog と RecordRoute を経路の登録の表に重ねて要求を1つ送り、要求のログを返す。
func requestLogged(t *testing.T, mux *http.ServeMux, method, path string) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	logs, logger := newLogger()
	handler := middleware.Recover(logger)(middleware.RequestLog(logger)(middleware.RecordRoute(mux)))
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(method, path, nil)
	req.Header.Set("Cookie", "XSRF-TOKEN="+sampleCSRF)
	req.Header.Set("Authorization", "Bearer 秘密")
	handler.ServeHTTP(rec, req)
	if strings.Contains(logs.String(), sampleCSRF) || strings.Contains(logs.String(), "秘密") {
		t.Errorf("ログに Cookie か Authorization を書いています: %s", logs.String())
	}
	for _, line := range records(t, logs) {
		if line["message"] == "request" {
			return rec, line
		}
	}
	t.Fatalf("要求のログがありません: %s", logs.String())
	return nil, nil
}

// 要求のログに、メソッドと経路の型と、実際に返したステータスを書くことを確かめる。
func TestRequestLog_MethodRouteStatus(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/resumes/{resumeId}", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusCreated)
		w.WriteHeader(http.StatusTeapot)
	})
	mux.HandleFunc("GET /api/body", func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write([]byte("本文")) })
	mux.HandleFunc("GET /api/empty", func(http.ResponseWriter, *http.Request) {})
	mux.HandleFunc("GET /api/panic", func(http.ResponseWriter, *http.Request) { panic("落ちる") })

	for _, tc := range []struct {
		method, path, route string
		status              float64
	}{
		{http.MethodPost, "/api/resumes/abc", "/api/resumes/{resumeId}", 201},
		{http.MethodGet, "/api/body", "/api/body", 200},
		{http.MethodGet, "/api/empty", "/api/empty", 200},
		{http.MethodGet, "/api/panic", "/api/panic", 500},
		{http.MethodGet, "/api/unknown", "", 404},
		{http.MethodDelete, "/api/body", "", 405},
	} {
		t.Run(tc.method+" "+tc.path, func(t *testing.T) {
			_, line := requestLogged(t, mux, tc.method, tc.path)
			if field(line, "http.request.method") != tc.method || field(line, "http.route") != tc.route ||
				field(line, "http.response.status_code") != tc.status {
				t.Errorf("要求のログ = %v, want %s %q %v", line, tc.method, tc.route, tc.status)
			}
			if duration, ok := field(line, "event.duration").(float64); !ok || duration <= 0 {
				t.Errorf("かかった時間 = %v, want 正の数", field(line, "event.duration"))
			}
		})
	}
}

// RequestLog の外で RecordRoute を使っても、経路の登録の表にそのまま渡すことを確かめる。
func TestRecordRoute_WithoutRequestLog(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/body", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) })
	rec := httptest.NewRecorder()
	middleware.RecordRoute(mux).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/body", nil))
	if rec.Code != http.StatusNoContent {
		t.Errorf("ステータス = %d, want 204", rec.Code)
	}
}

// 応答の書き手を包んでも、http.ResponseController で元の書き手の機能を使えることを確かめる。
func TestWrappers_Unwrap(t *testing.T) {
	_, logger := newLogger()
	handler := middleware.Recover(logger)(middleware.RequestLog(logger)(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if err := http.NewResponseController(w).Flush(); err != nil {
			t.Errorf("Flush = %v, want 成功", err)
		}
	})))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if !rec.Flushed {
		t.Error("元の書き手の Flush が呼ばれませんでした")
	}
}
