package middleware_test

import (
	"bytes"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi"
	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/middleware"
)

// uuidCookie は、Java 版の CookieCsrfTokenRepository と同じ形の Set-Cookie である。
var uuidCookie = regexp.MustCompile(`^XSRF-TOKEN=[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}; Path=/$`)

const sampleCSRF = "4f1c2b7e-1d2a-4c3b-9e8f-0a1b2c3d4e5f"

// serve は、偽の送信の検査の後ろに、通ったかを記録する処理を置いて、要求を1つ送る。
func serve(t *testing.T, req *http.Request) (*httptest.ResponseRecorder, bool) {
	t.Helper()
	passed := false
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		passed = true
		w.WriteHeader(http.StatusNoContent)
	})
	rec := httptest.NewRecorder()
	middleware.CSRF(next).ServeHTTP(rec, req)
	return rec, passed
}

func withToken(req *http.Request, cookie, header string) *http.Request {
	if cookie != "" {
		req.Header.Set("Cookie", "XSRF-TOKEN="+cookie)
	}
	if header != "" {
		req.Header.Set("X-XSRF-TOKEN", header)
	}
	return req
}

func assertForbidden(t *testing.T, rec *httptest.ResponseRecorder, passed bool) {
	t.Helper()
	if passed {
		t.Error("検査に通らない要求を、後ろの処理に渡しました")
	}
	if rec.Code != http.StatusForbidden {
		t.Errorf("ステータス = %d, want 403", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json;charset=UTF-8" {
		t.Errorf("Content-Type = %q, want application/json;charset=UTF-8", got)
	}
	if got := rec.Body.String(); got != `{"message":"アクセス権限がありません。"}` {
		t.Errorf("本文 = %s, want Java 版と同じ本文", got)
	}
}

// Cookie とヘッダが一致しない要求に、Java 版と同じ 403 と本文を返し、Cookie が無ければ新しい Cookie を付けることを確かめる。
func TestCSRF_MismatchReturns403WithNewCookie(t *testing.T) {
	t.Run("Cookie が無ければ新しい Cookie を付けて 403", func(t *testing.T) {
		rec, passed := serve(t, withToken(httptest.NewRequest(http.MethodPost, "/api/resumes", nil), "", sampleCSRF))
		assertForbidden(t, rec, passed)
		cookies := rec.Header().Values("Set-Cookie")
		if len(cookies) != 1 || !uuidCookie.MatchString(cookies[0]) {
			t.Errorf("Set-Cookie = %q, want XSRF-TOKEN=<UUID>; Path=/ を1つ", cookies)
		}
	})
	t.Run("空の Cookie は無いと同じに扱う", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPut, "/api/users/me", nil)
		req.Header.Set("Cookie", "XSRF-TOKEN=")
		rec, passed := serve(t, req)
		assertForbidden(t, rec, passed)
		if cookies := rec.Header().Values("Set-Cookie"); len(cookies) != 1 || !uuidCookie.MatchString(cookies[0]) {
			t.Errorf("Set-Cookie = %q, want 新しい XSRF-TOKEN", cookies)
		}
	})
	for _, tc := range []struct{ name, method, header string }{
		{"ヘッダが違う", http.MethodPost, "different"},
		{"ヘッダが無い", http.MethodDelete, ""},
		{"PATCH も検査する", http.MethodPatch, "different"},
	} {
		t.Run(tc.name+"なら、Cookie を替えずに 403", func(t *testing.T) {
			rec, passed := serve(t, withToken(httptest.NewRequest(tc.method, "/api/resumes/x", nil), sampleCSRF, tc.header))
			assertForbidden(t, rec, passed)
			if cookies := rec.Header().Values("Set-Cookie"); len(cookies) != 0 {
				t.Errorf("Set-Cookie = %q, want なし(Java 版は Cookie があるときに作り直さない)", cookies)
			}
		})
	}
	t.Run("一致すれば通す", func(t *testing.T) {
		rec, passed := serve(t, withToken(httptest.NewRequest(http.MethodPost, "/api/resumes", nil), sampleCSRF, sampleCSRF))
		if !passed || rec.Code != http.StatusNoContent {
			t.Errorf("通った %t, ステータス %d, want 通して 204", passed, rec.Code)
		}
		if cookies := rec.Header().Values("Set-Cookie"); len(cookies) != 0 {
			t.Errorf("Set-Cookie = %q, want なし", cookies)
		}
	})
	for _, path := range []string{"/api/auth/login", "/api/auth", "/actuator/health"} {
		t.Run(path+" は Java 版と同じく検査しないが、Cookie を付ける", func(t *testing.T) {
			rec, passed := serve(t, httptest.NewRequest(http.MethodPost, path, nil))
			if !passed {
				t.Errorf("%s の POST を断りました", path)
			}
			if cookies := rec.Header().Values("Set-Cookie"); len(cookies) != 1 || !uuidCookie.MatchString(cookies[0]) {
				t.Errorf("Set-Cookie = %q, want 新しい XSRF-TOKEN", cookies)
			}
		})
	}
	t.Run("/api/authx は検査から外さない", func(t *testing.T) {
		rec, passed := serve(t, httptest.NewRequest(http.MethodPost, "/api/authx", nil))
		assertForbidden(t, rec, passed)
	})
}

// GET と HEAD と TRACE と OPTIONS を、トークンが無くても通すことを確かめる。
func TestCSRF_GetPasses(t *testing.T) {
	for _, method := range []string{http.MethodGet, http.MethodHead, http.MethodTrace} {
		t.Run(method+" はトークンが無くても通し、Cookie を付ける", func(t *testing.T) {
			rec, passed := serve(t, httptest.NewRequest(method, "/api/resumes", nil))
			if !passed || rec.Code != http.StatusNoContent {
				t.Errorf("通った %t, ステータス %d, want 通して 204", passed, rec.Code)
			}
			if cookies := rec.Header().Values("Set-Cookie"); len(cookies) != 1 || !uuidCookie.MatchString(cookies[0]) {
				t.Errorf("Set-Cookie = %q, want 新しい XSRF-TOKEN", cookies)
			}
		})
	}
	t.Run("Cookie があれば作り直さない", func(t *testing.T) {
		rec, passed := serve(t, withToken(httptest.NewRequest(http.MethodGet, "/api/resumes", nil), sampleCSRF, ""))
		if !passed {
			t.Error("GET を断りました")
		}
		if cookies := rec.Header().Values("Set-Cookie"); len(cookies) != 0 {
			t.Errorf("Set-Cookie = %q, want なし", cookies)
		}
	})
	t.Run("OPTIONS は Cookie も付けずに通す", func(t *testing.T) {
		rec, passed := serve(t, httptest.NewRequest(http.MethodOptions, "/api/resumes", nil))
		if !passed {
			t.Error("OPTIONS を断りました")
		}
		if cookies := rec.Header().Values("Set-Cookie"); len(cookies) != 0 {
			t.Errorf("Set-Cookie = %q, want なし", cookies)
		}
	})
	t.Run("作るトークンは毎回違う", func(t *testing.T) {
		first, _ := serve(t, httptest.NewRequest(http.MethodGet, "/", nil))
		second, _ := serve(t, httptest.NewRequest(http.MethodGet, "/", nil))
		if first.Header().Get("Set-Cookie") == second.Header().Get("Set-Cookie") {
			t.Error("2つの要求に同じトークンを作りました")
		}
	})
}

// 偽の送信の検査が、ログインの状態の検査より前に動くことを、HTTP の受け口の全体で確かめる。
func TestCSRF_RunsBeforeAuth(t *testing.T) {
	authCalled := 0
	handler := httpapi.New(httpapi.Options{
		Logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
		DB:     nil,
		Auth: func(http.Handler) http.Handler {
			return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				authCalled++
				w.WriteHeader(http.StatusUnauthorized)
			})
		},
	})

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/api/resumes", bytes.NewBufferString("{}")))
	if rec.Code != http.StatusForbidden || authCalled != 0 {
		t.Errorf("トークンの無い POST: ステータス %d, ログインの検査を %d 回呼んだ, want 403 で 0 回", rec.Code, authCalled)
	}

	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, withToken(httptest.NewRequest(http.MethodPost, "/api/resumes", bytes.NewBufferString("{}")), sampleCSRF, sampleCSRF))
	if rec.Code != http.StatusUnauthorized || authCalled != 1 {
		t.Errorf("トークンの一致する POST: ステータス %d, ログインの検査を %d 回呼んだ, want 401 で 1 回", rec.Code, authCalled)
	}
}
