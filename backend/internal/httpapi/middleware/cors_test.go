package middleware_test

import (
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/middleware"
)

// テストの CORS の許す送り元は、dev と test の設定と同じ2つである。
const (
	originFrontend = "http://localhost:5173"
	originAPIDocs  = "http://localhost:8082"
	originApp      = "https://app.keirekipro.click"
	originEvil     = "http://evil.example"
)

var devOrigins = []string{originFrontend, originAPIDocs}

// corsVary は、Java 版の記録のとおり、すべての応答に値ごとに別の行で付く Vary である。
var corsVary = []string{"Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers"}

// serveCORS は、CORS の処理の後ろに、通ったかを記録する処理を置いて、要求を1つ送る。
func serveCORS(t *testing.T, allowed []string, req *http.Request) (*httptest.ResponseRecorder, bool) {
	t.Helper()
	passed := false
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		passed = true
		w.WriteHeader(http.StatusNoContent)
	})
	rec := httptest.NewRecorder()
	middleware.CORS(allowed)(next).ServeHTTP(rec, req)
	return rec, passed
}

// preflight は、送り元 origin から、メソッド method を求めるプリフライトを作る。headers が空でなければ Access-Control-Request-Headers を付ける。
func preflight(origin, method, headers string) *http.Request {
	req := httptest.NewRequest(http.MethodOptions, "http://localhost:8081/api/resumes", nil)
	req.Header.Set("Origin", origin)
	req.Header.Set("Access-Control-Request-Method", method)
	if headers != "" {
		req.Header.Set("Access-Control-Request-Headers", headers)
	}
	return req
}

// assertHeaders は、want の各ヘッダの値を確かめる。値が空なら、そのヘッダが無いことを確かめる。
func assertHeaders(t *testing.T, rec *httptest.ResponseRecorder, want map[string]string) {
	t.Helper()
	if got := rec.Header().Values("Vary"); !slices.Equal(got, corsVary) {
		t.Errorf("Vary = %q, want %q", got, corsVary)
	}
	for name, value := range want {
		got := rec.Header().Values(name)
		switch {
		case value == "" && len(got) != 0:
			t.Errorf("%s = %q, want 無い", name, got)
		case value != "" && (len(got) != 1 || got[0] != value):
			t.Errorf("%s = %q, want %q", name, got, value)
		}
	}
}

// assertCORSRejected は、Java 版と同じく、403 と本文 Invalid CORS request を返し、後ろの処理に渡さなかったことを確かめる。
func assertCORSRejected(t *testing.T, rec *httptest.ResponseRecorder, passed bool) {
	t.Helper()
	if passed {
		t.Error("CORS の処理が断る要求を、後ろの処理に渡しました")
	}
	if rec.Code != http.StatusForbidden {
		t.Errorf("ステータス = %d, want 403", rec.Code)
	}
	if got := rec.Body.String(); got != "Invalid CORS request" {
		t.Errorf("本文 = %q, want Invalid CORS request", got)
	}
	assertHeaders(t, rec, map[string]string{
		"Access-Control-Allow-Origin":      "",
		"Access-Control-Allow-Credentials": "",
	})
}

// 許す送り元のプリフライトに、200 と、Java 版の記録のとおりの5つのヘッダを返し、Access-Control-Max-Age を付けず、後ろの処理に渡さないことを確かめる。
func TestCORS_PreflightAllowed(t *testing.T) {
	for _, origin := range devOrigins {
		t.Run(origin, func(t *testing.T) {
			rec, passed := serveCORS(t, devOrigins, preflight(origin, http.MethodPost, "content-type,x-xsrf-token"))
			if passed {
				t.Error("プリフライトを後ろの処理に渡しました")
			}
			if rec.Code != http.StatusOK {
				t.Errorf("ステータス = %d, want 200", rec.Code)
			}
			assertHeaders(t, rec, map[string]string{
				"Access-Control-Allow-Origin":      origin,
				"Access-Control-Allow-Methods":     "GET,POST,PUT,DELETE,PATCH,OPTIONS",
				"Access-Control-Allow-Headers":     "content-type, x-xsrf-token",
				"Access-Control-Allow-Credentials": "true",
				"Access-Control-Expose-Headers":    "Content-Disposition, X-Request-Id",
				"Access-Control-Max-Age":           "",
			})
		})
	}
}

// Access-Control-Request-Headers の無いプリフライトに、Access-Control-Allow-Headers を Java 版の記録のとおりに扱うことを確かめる。
func TestCORS_PreflightWithoutRequestHeaders(t *testing.T) {
	rec, passed := serveCORS(t, devOrigins, preflight(originAPIDocs, http.MethodPost, ""))
	if passed || rec.Code != http.StatusOK {
		t.Errorf("ステータス = %d, 後ろの処理に渡した = %v, want 200 で渡さない", rec.Code, passed)
	}
	assertHeaders(t, rec, map[string]string{
		"Access-Control-Allow-Origin":  originAPIDocs,
		"Access-Control-Allow-Headers": "",
	})
}

// 許す6つのメソッドのほかのメソッドのプリフライトに、403 と Invalid CORS request を返すことを確かめる。
func TestCORS_PreflightMethodNotAllowed(t *testing.T) {
	for _, method := range []string{http.MethodTrace, http.MethodHead, "post"} {
		t.Run(method, func(t *testing.T) {
			rec, passed := serveCORS(t, devOrigins, preflight(originFrontend, method, ""))
			assertCORSRejected(t, rec, passed)
		})
	}
}

// 許さない送り元からの要求に、プリフライトかどうかによらず、403 と Invalid CORS request を返すことを確かめる。
func TestCORS_OriginNotAllowed(t *testing.T) {
	t.Run("プリフライト", func(t *testing.T) {
		rec, passed := serveCORS(t, devOrigins, preflight(originEvil, http.MethodPost, ""))
		assertCORSRejected(t, rec, passed)
	})
	t.Run("GET", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "http://localhost:8081/actuator/health", nil)
		req.Header.Set("Origin", originEvil)
		rec, passed := serveCORS(t, devOrigins, req)
		assertCORSRejected(t, rec, passed)
	})
	t.Run("本番の設定で開発環境の送り元", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "http://app.keirekipro.click/api/resumes", nil)
		req.Header.Set("Origin", originAPIDocs)
		rec, passed := serveCORS(t, []string{originApp}, req)
		assertCORSRejected(t, rec, passed)
	})
	// 本物の受け口は、Content-Type の無い応答に本文から推した Content-Type を付ける。テストの記録用の応答の部品はそれをしないので、
	// Java 版と同じく Content-Type を付けないことは、本物の受け口を立てて確かめる
	t.Run("Content-Type を付けない", func(t *testing.T) {
		next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) })
		server := httptest.NewServer(middleware.CORS(devOrigins)(next))
		t.Cleanup(server.Close)
		req, err := http.NewRequestWithContext(t.Context(), http.MethodGet, server.URL, nil)
		if err != nil {
			t.Fatalf("要求を作れません: %v", err)
		}
		req.Header.Set("Origin", originEvil)
		res, err := server.Client().Do(req)
		if err != nil {
			t.Fatalf("要求を送れません: %v", err)
		}
		_ = res.Body.Close()
		if got := res.Header.Values("Content-Type"); res.StatusCode != http.StatusForbidden || len(got) != 0 {
			t.Errorf("応答 = %d, Content-Type = %q, want 403 で Content-Type が無い", res.StatusCode, got)
		}
	})
}

// プリフライトでない要求に、3つのヘッダを付けて後ろの処理に渡すことを確かめる。
func TestCORS_ActualRequestHeaders(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "http://localhost:8081/api/resumes", nil)
	req.Header.Set("Origin", originAPIDocs)
	rec, passed := serveCORS(t, devOrigins, req)
	if !passed || rec.Code != http.StatusNoContent {
		t.Errorf("ステータス = %d, 後ろの処理に渡した = %v, want 後ろの処理の 204", rec.Code, passed)
	}
	assertHeaders(t, rec, map[string]string{
		"Access-Control-Allow-Origin":      originAPIDocs,
		"Access-Control-Allow-Credentials": "true",
		"Access-Control-Expose-Headers":    "Content-Disposition, X-Request-Id",
		"Access-Control-Allow-Methods":     "",
		"Access-Control-Allow-Headers":     "",
	})
}

// 許す送り元からのプリフライトでない HEAD に、Java 版と同じく 403 と Invalid CORS request を返し、
// GET には Access-Control-Allow-Origin を付けて後ろの処理に渡すことを確かめる。
func TestCORS_ActualRequestMethod(t *testing.T) {
	t.Run("HEAD", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodHead, "http://localhost:8081/actuator/health", nil)
		req.Header.Set("Origin", originFrontend)
		rec, passed := serveCORS(t, devOrigins, req)
		assertCORSRejected(t, rec, passed)
	})
	t.Run("GET", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "http://localhost:8081/actuator/health", nil)
		req.Header.Set("Origin", originFrontend)
		rec, passed := serveCORS(t, devOrigins, req)
		if !passed {
			t.Error("GET を後ろの処理に渡しませんでした")
		}
		assertHeaders(t, rec, map[string]string{"Access-Control-Allow-Origin": originFrontend})
	})
}

// Origin の無い要求と、Origin が要求の宛先と同じ送り元の要求に、Vary だけを付けて後ろの処理に渡すことを確かめる。
func TestCORS_NoOriginOnlyVary(t *testing.T) {
	for _, tc := range []struct {
		name   string
		target string
		origin string
	}{
		{name: "Origin が無い", target: "http://localhost:8081/actuator/health"},
		{name: "同じ送り元", target: "http://localhost:8081/actuator/health", origin: "http://localhost:8081"},
		{name: "同じ送り元で既定のポート", target: "http://example.test/actuator/health", origin: "http://example.test:80"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, tc.target, nil)
			if tc.origin != "" {
				req.Header.Set("Origin", tc.origin)
			}
			rec, passed := serveCORS(t, devOrigins, req)
			if !passed {
				t.Error("CORS の要求でない要求を、後ろの処理に渡しませんでした")
			}
			assertHeaders(t, rec, map[string]string{
				"Access-Control-Allow-Origin":      "",
				"Access-Control-Allow-Credentials": "",
				"Access-Control-Expose-Headers":    "",
			})
		})
	}
}

// 本番の設定で、方式が http に見える書き込みの要求に Origin: https://app.keirekipro.click を付けると、後ろの処理に渡すことを確かめる。
// 本番では ALB が TLS を終えるので、Go 版が受ける要求の方式は http になり、画面からの要求も CORS の要求として扱われる。
func TestCORS_ProdWriteFromAppOrigin(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "http://app.keirekipro.click/api/resumes", nil)
	req.Header.Set("Origin", originApp)
	rec, passed := serveCORS(t, []string{originApp}, req)
	if !passed {
		t.Errorf("ステータス = %d, want 後ろの処理に渡す", rec.Code)
	}
	assertHeaders(t, rec, map[string]string{
		"Access-Control-Allow-Origin":      originApp,
		"Access-Control-Allow-Credentials": "true",
	})
}
