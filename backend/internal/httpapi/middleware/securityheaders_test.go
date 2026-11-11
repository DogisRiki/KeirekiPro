package middleware_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/DogisRiki/KeirekiPro/backend/internal/httpapi/middleware"
)

// javaSecurityHeaders は、Java 版の Spring Security が既定で応答に置く6つのヘッダである。
var javaSecurityHeaders = map[string]string{
	"Cache-Control":          "no-cache, no-store, max-age=0, must-revalidate",
	"Pragma":                 "no-cache",
	"Expires":                "0",
	"X-Content-Type-Options": "nosniff",
	"X-Frame-Options":        "DENY",
	"X-XSS-Protection":       "0",
}

// assertSecurityHeaders は、応答に6つのヘッダが1つずつ、Java 版と同じ値で置かれたかを確かめる。
func assertSecurityHeaders(t *testing.T, header http.Header) {
	t.Helper()
	for name, want := range javaSecurityHeaders {
		got := header.Values(name)
		if len(got) != 1 || got[0] != want {
			t.Errorf("ヘッダ %s = %q, want [%q]", name, got, want)
		}
	}
}

// sentHeader は、応答を書き始めた時点のヘッダ、つまり実際に送られたヘッダを返す。
// rec.Header() は書き始めたあとに置いたヘッダも見せるので、送られたヘッダの確かめには使わない。
func sentHeader(t *testing.T, rec *httptest.ResponseRecorder) http.Header {
	t.Helper()
	res := rec.Result()
	if err := res.Body.Close(); err != nil {
		t.Fatalf("応答の本文を閉じられない: %v", err)
	}
	return res.Header
}

// TestSecurityHeaders_OnAllStatuses は、次の処理が返す状態の番号によらず、6つのヘッダが付くことを確かめる。
// 500 は、外側の Recover が、次の処理のパニックを受け止めて返す応答で確かめる。
func TestSecurityHeaders_OnAllStatuses(t *testing.T) {
	_, logger := newLogger()
	cases := []struct {
		name   string
		next   http.HandlerFunc
		status int
	}{
		{"200", func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{}`))
		}, http.StatusOK},
		{"404", http.NotFound, http.StatusNotFound},
		{"403", func(w http.ResponseWriter, _ *http.Request) {
			middleware.WriteError(w, http.StatusForbidden, middleware.MessageForbidden)
		}, http.StatusForbidden},
		{"500", func(http.ResponseWriter, *http.Request) {
			panic("想定外")
		}, http.StatusInternalServerError},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			handler := middleware.Recover(logger)(middleware.SecurityHeaders(tc.next))
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/users/me", nil))
			if rec.Code != tc.status {
				t.Fatalf("状態の番号 = %d, want %d", rec.Code, tc.status)
			}
			assertSecurityHeaders(t, sentHeader(t, rec))
		})
	}
}

// TestSecurityHeaders_HandlerOverrideKept は、次の処理がヘッダを上書きしたときに、上書きした値が残ることを確かめる。
// 上書きしなかったヘッダは、中間処理の値のまま残る。
func TestSecurityHeaders_HandlerOverrideKept(t *testing.T) {
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Cache-Control", "max-age=60")
		w.WriteHeader(http.StatusOK)
	})
	rec := httptest.NewRecorder()
	middleware.SecurityHeaders(next).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	header := sentHeader(t, rec)
	if got := header.Values("Cache-Control"); len(got) != 1 || got[0] != "max-age=60" {
		t.Errorf("Cache-Control = %q, want [\"max-age=60\"]", got)
	}
	for name, want := range javaSecurityHeaders {
		if name == "Cache-Control" {
			continue
		}
		if got := header.Get(name); got != want {
			t.Errorf("ヘッダ %s = %q, want %q", name, got, want)
		}
	}
}
