package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/gen"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/logging"
)

const (
	javaUnexpected = `{"message":"予期せぬエラーが発生しました。","errors":{}}`
	javaBadRequest = `{"message":"入力エラーがあります。","errors":{}}`
	sampleCSRF     = "4f1c2b7e-1d2a-4c3b-9e8f-0a1b2c3d4e5f"
	sampleResumeID = "0b8f3c9e-6a1d-4f2e-9c7b-5d4e3f2a1b0c"
)

// server は、ログを logs に書く HTTP の受け口を作る。
func server(handlers gen.StrictServerInterface, db httpapi.HealthDB) (http.Handler, *bytes.Buffer) {
	logs := &bytes.Buffer{}
	logger := logging.New(logs, logging.Options{Service: logging.Service{Name: "keirekipro"}})
	return httpapi.New(httpapi.Options{Logger: logger, DB: db, Handlers: handlers}), logs
}

// send は、偽の送信の検査に通る Cookie とヘッダを付けて、要求を1つ送る。
func send(handler http.Handler, method, path, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Cookie", "XSRF-TOKEN="+sampleCSRF)
	req.Header.Set("X-XSRF-TOKEN", sampleCSRF)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

// logLines は、書かれたログを1行ずつ JSON として読む。
func logLines(t *testing.T, logs *bytes.Buffer) []map[string]any {
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

// requestLog は、要求のログの行の http と event の項目を返す。
func requestLog(t *testing.T, logs *bytes.Buffer) map[string]any {
	t.Helper()
	for _, line := range logLines(t, logs) {
		if line["message"] == "request" {
			return line
		}
	}
	t.Fatalf("要求のログがありません: %s", logs.String())
	return nil
}

func assertBody(t *testing.T, rec *httptest.ResponseRecorder, status int, contentType, body string) {
	t.Helper()
	if rec.Code != status {
		t.Errorf("ステータス = %d, want %d", rec.Code, status)
	}
	if got := rec.Header().Get("Content-Type"); got != contentType {
		t.Errorf("Content-Type = %q, want %q", got, contentType)
	}
	if got := rec.Body.String(); got != body {
		t.Errorf("本文 = %s, want %s", got, body)
	}
}

// まだ作っていない操作に 501 を返し、要求のログに経路の型とステータスを書き、Cookie を書かないことを確かめる。
func TestUnimplementedReturns501(t *testing.T) {
	for _, tc := range []struct{ method, path, route, body string }{
		{http.MethodGet, "/api/resumes", "/api/resumes", ""},
		{http.MethodGet, "/api/resumes/" + sampleResumeID, "/api/resumes/{resumeId}", ""},
		{http.MethodPost, "/api/auth/login", "/api/auth/login", `{"email":"a@example.com","password":"x"}`},
		{http.MethodDelete, "/api/users/me", "/api/users/me", ""},
	} {
		t.Run(tc.method+" "+tc.path, func(t *testing.T) {
			handler, logs := server(nil, nil)
			rec := send(handler, tc.method, tc.path, tc.body)
			assertBody(t, rec, http.StatusNotImplemented, "application/json", `{"message":"未実装です。"}`)

			line := requestLog(t, logs)
			httpFields, _ := line["http"].(map[string]any)
			request, _ := httpFields["request"].(map[string]any)
			response, _ := httpFields["response"].(map[string]any)
			if request["method"] != tc.method || httpFields["route"] != tc.route || response["status_code"] != float64(501) {
				t.Errorf("要求のログ = %v, want %s %s 501", line, tc.method, tc.route)
			}
			if strings.Contains(logs.String(), sampleCSRF) || strings.Contains(logs.String(), "password") {
				t.Errorf("ログに Cookie か要求の本文を書いています: %s", logs.String())
			}
		})
	}
}

// 本文を JSON として読めない要求に、Java 版と同じ 400 と {message, errors} を返すことを確かめる。
func TestBadJSONReturns400MessageErrors(t *testing.T) {
	for name, body := range map[string]string{
		"JSON の構文の誤り": `{"email":`,
		"値の型の誤り":      `{"email":1,"password":"x"}`,
		"本文が無い":       ``,
	} {
		t.Run(name, func(t *testing.T) {
			handler, _ := server(nil, nil)
			rec := send(handler, http.MethodPost, "/api/auth/login", body)
			assertBody(t, rec, http.StatusBadRequest, "application/json", javaBadRequest)
		})
	}
	t.Run("経路の値の形の誤りは、Java 版と同じ 500 にし、ログに値を書かない", func(t *testing.T) {
		handler, logs := server(nil, nil)
		rec := send(handler, http.MethodDelete, "/api/resumes/"+sampleResumeID+"/careers/not-a-uuid", "")
		assertBody(t, rec, http.StatusInternalServerError, "application/json", javaUnexpected)
		if !strings.Contains(logs.String(), `"type":"*gen.InvalidParamFormatError"`) || strings.Contains(logs.String(), "not-a-uuid") {
			t.Errorf("ログ = %s, want 誤りの型だけ", logs.String())
		}
	})
}

// panicking は、経歴書の一覧の操作でパニックを起こし、経歴書を作る操作で誤りを返す。
type panicking struct {
	httpapi.Unimplemented
}

func (panicking) ListResumes(context.Context, gen.ListResumesRequestObject) (gen.ListResumesResponseObject, error) {
	panic("想定外の状態")
}

func (panicking) GetResume(context.Context, gen.GetResumeRequestObject) (gen.GetResumeResponseObject, error) {
	return nil, errors.New("データベースにつなげません")
}

// パニックと想定外の誤りに、Java 版と同じ 500 と本文を返し、スタックをログに書くことを確かめる。
func TestPanicReturns500JavaBody(t *testing.T) {
	handler, logs := server(panicking{}, nil)
	rec := send(handler, http.MethodGet, "/api/resumes", "")
	assertBody(t, rec, http.StatusInternalServerError, "application/json", javaUnexpected)

	var panicLine map[string]any
	for _, line := range logLines(t, logs) {
		if line["message"] == "unexpected_exception" {
			panicLine = line
		}
	}
	errorFields, _ := panicLine["error"].(map[string]any)
	stack, _ := errorFields["stack_trace"].(string)
	if errorFields["message"] != "panic: 想定外の状態" || !strings.Contains(stack, "goroutine") {
		t.Errorf("パニックのログ = %v, want 誤りの文とスタック", panicLine)
	}
	if logLevel, _ := panicLine["log"].(map[string]any); logLevel["level"] != "ERROR" {
		t.Errorf("パニックのログの重さ = %v, want ERROR", panicLine["log"])
	}
	response, _ := requestLog(t, logs)["http"].(map[string]any)["response"].(map[string]any)
	if response["status_code"] != float64(500) {
		t.Errorf("要求のログのステータス = %v, want 500", response["status_code"])
	}

	t.Run("操作が返した誤りも 500 にする", func(t *testing.T) {
		handler, logs := server(panicking{}, nil)
		rec := send(handler, http.MethodGet, "/api/resumes/"+sampleResumeID, "")
		assertBody(t, rec, http.StatusInternalServerError, "application/json", javaUnexpected)
		if !strings.Contains(logs.String(), "データベースにつなげません") {
			t.Errorf("ログ = %s, want 誤りの文", logs.String())
		}
	})
}

// 仕様書に無い経路に 404 を返し、本番でも API の説明画面を開けないことを確かめる。
func TestUnknownRouteReturns404(t *testing.T) {
	for _, path := range []string{"/swagger-ui/index.html", "/v3/api-docs", "/api/unknown", "/"} {
		t.Run(path, func(t *testing.T) {
			handler, logs := server(nil, nil)
			rec := send(handler, http.MethodGet, path, "")
			if rec.Code != http.StatusNotFound {
				t.Errorf("%s のステータス = %d, want 404", path, rec.Code)
			}
			httpFields, _ := requestLog(t, logs)["http"].(map[string]any)
			if httpFields["route"] != "" {
				t.Errorf("経路の型 = %v, want 空", httpFields["route"])
			}
		})
	}
}

// CORS の処理が、偽の送信の検査より前に動くことを確かめる。
// 偽の送信の検査は OPTIONS の要求を検査しないので、プリフライトでは順を見分けられない。
// そのため、許す送り元からのヘッダ X-XSRF-TOKEN の無い POST に、偽の送信の検査が返す 403 の応答に
// Access-Control-Allow-Origin が付くことで、CORS の処理が先に動いたことを確かめる。
func TestCORS_RunsBeforeCSRF(t *testing.T) {
	handler := httpapi.New(httpapi.Options{
		Logger:             logging.New(&bytes.Buffer{}, logging.Options{Service: logging.Service{Name: "keirekipro"}}),
		CORSAllowedOrigins: []string{"http://localhost:5173", "http://localhost:8082"},
	})
	req := httptest.NewRequest(http.MethodPost, "http://localhost:8081/api/resumes", strings.NewReader("{}"))
	req.Header.Set("Origin", "http://localhost:8082")
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden || rec.Body.String() != `{"message":"アクセス権限がありません。"}` {
		t.Errorf("応答 = %d %s, want 偽の送信の検査の 403", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "http://localhost:8082" {
		t.Errorf("Access-Control-Allow-Origin = %q, want http://localhost:8082", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Credentials"); got != "true" {
		t.Errorf("Access-Control-Allow-Credentials = %q, want true", got)
	}
}
