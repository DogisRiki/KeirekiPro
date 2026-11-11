package auth

import (
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/authctx"
)

// passed は、次の処理に要求が届いたかと、届いた要求の利用者を覚える、次の処理の代わりである。
type passed struct {
	called bool
	userID uuid.UUID
	hasID  bool
	roles  []string
}

func (p *passed) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p.called = true
		p.userID, p.hasID = authctx.UserID(r.Context())
		p.roles = authctx.Roles(r.Context())
		w.WriteHeader(http.StatusTeapot)
	})
}

// serve は、handler に要求を1つ渡し、応答の状態の番号とヘッダと本文を返す。
func serve(t *testing.T, handler http.Handler, r *http.Request) (int, http.Header, string) {
	t.Helper()
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, r)
	res := rec.Result()
	defer func() {
		if err := res.Body.Close(); err != nil {
			t.Errorf("応答の本文を閉じられない: %v", err)
		}
	}()
	body, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatalf("応答の本文を読めない: %v", err)
	}
	return res.StatusCode, res.Header, string(body)
}

// withUser は、要求の context に、ログインした利用者を入れる。
func withUser(r *http.Request, id uuid.UUID, roles ...string) *http.Request {
	return r.WithContext(authctx.With(r.Context(), id, roles))
}

// TestRequireLogin_PublicPathBoundaries は、Java 版の permitAll と同じ要求だけを、ログインを求めずに通すことを確かめる。
// Spring の「/x/**」は、/x と /x/ と /x の下に当たり、/xy には当たらない。
func TestRequireLogin_PublicPathBoundaries(t *testing.T) {
	cases := []struct {
		method, path string
		public       bool
	}{
		{http.MethodOptions, "/api/users/me", true},
		{http.MethodOptions, "/api/admin/users", true},
		{"options", "/api/users/me", false},
		{http.MethodGet, "/api/auth", true},
		{http.MethodGet, "/api/auth/", true},
		{http.MethodPost, "/api/auth/login", true},
		{http.MethodPost, "/api/auth/2fa/verify", true},
		{http.MethodGet, "/api/authx", false},
		{http.MethodGet, "/api/authx/login", false},
		{http.MethodGet, "/api", false},
		{http.MethodGet, "/actuator", true},
		{http.MethodGet, "/actuator/health", true},
		{http.MethodGet, "/actuatorx", false},
		{http.MethodGet, "/healthz", true},
		{http.MethodGet, "/healthz/x", false},
		{http.MethodGet, "/healthzx", false},
		{http.MethodGet, "/swagger-ui", true},
		{http.MethodGet, "/swagger-ui/index.html", true},
		{http.MethodGet, "/swagger-ui.html", true},
		{http.MethodGet, "/swagger-uix", false},
		{http.MethodGet, "/v3/api-docs", true},
		{http.MethodGet, "/v3/api-docs/swagger-config", true},
		{http.MethodGet, "/v3/api-docsx", false},
		{http.MethodGet, "/api/users/me", false},
		{http.MethodGet, "/", false},
	}
	for _, tc := range cases {
		t.Run(tc.method+" "+tc.path, func(t *testing.T) {
			var p passed
			status, _, body := serve(t, RequireLogin()(p.handler()), httptest.NewRequest(tc.method, tc.path, nil))
			if tc.public {
				if !p.called || status != http.StatusTeapot {
					t.Errorf("ログインしていない要求を通さない: 状態の番号 %d, 本文 %q", status, body)
				}
				return
			}
			if p.called || status != http.StatusUnauthorized {
				t.Errorf("ログインしていない要求を断らない: 状態の番号 %d, 次に渡した %t", status, p.called)
			}
		})
	}
}

// TestRequireLogin_NoUser401 は、ログインの要る要求に利用者が居なければ、Java 版の HttpStatusEntryPoint と同じく、
// 本文の無い 401 で断ることを確かめる。/api/admin/ の下も、ログインしていなければ 403 でなく 401 である。
func TestRequireLogin_NoUser401(t *testing.T) {
	for _, path := range []string{"/api/users/me", "/api/resumes", "/api/admin/users", "/no/such/path"} {
		t.Run(path, func(t *testing.T) {
			var p passed
			status, header, body := serve(t, RequireLogin()(p.handler()), httptest.NewRequest(http.MethodGet, path, nil))
			if status != http.StatusUnauthorized || body != "" || p.called {
				t.Errorf("応答 = %d, %q, 次に渡した %t, want 401, 空, false", status, body, p.called)
			}
			if got := header.Get("Content-Type"); got != "" {
				t.Errorf("Content-Type = %q, want 空", got)
			}
		})
	}
}

// TestRequireLogin_AdminForbidden は、/api/admin の下の要求を、役割 ADMIN の無い利用者なら、
// Java 版の accessDeniedHandler と同じ 403 と本文と Content-Type で断ることを確かめる。
func TestRequireLogin_AdminForbidden(t *testing.T) {
	id := uuid.MustParse(testUserID)
	cases := []struct {
		name  string
		path  string
		roles []string
		allow bool
	}{
		{"USER だけ", "/api/admin/users", []string{"USER"}, false},
		{"役割が無い", "/api/admin/users", nil, false},
		{"/api/admin そのもの", "/api/admin", []string{"USER"}, false},
		{"小文字の admin", "/api/admin/users", []string{"admin"}, false},
		{"ROLE_ を付けた名前", "/api/admin/users", []string{"ROLE_ADMIN"}, false},
		{"ADMIN を持つ", "/api/admin/users", []string{"USER", "ADMIN"}, true},
		{"/api/adminx は管理者の経路でない", "/api/adminx", []string{"USER"}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var p passed
			r := withUser(httptest.NewRequest(http.MethodGet, tc.path, nil), id, tc.roles...)
			status, header, body := serve(t, RequireLogin()(p.handler()), r)
			if tc.allow {
				if !p.called || status != http.StatusTeapot {
					t.Errorf("要求を通さない: 状態の番号 %d, 本文 %q", status, body)
				}
				return
			}
			if p.called || status != http.StatusForbidden {
				t.Fatalf("応答 = %d, 次に渡した %t, want 403, false", status, p.called)
			}
			if body != `{"message":"アクセス権限がありません。"}` {
				t.Errorf("本文 = %q", body)
			}
			if got := header.Values("Content-Type"); len(got) != 1 || got[0] != "application/json;charset=UTF-8" {
				t.Errorf("Content-Type = %q, want [application/json;charset=UTF-8]", got)
			}
		})
	}
}

// TestRequireLogin_PassesAuthctxUser は、ログインした利用者の要求を、利用者を context に持たせたまま次の処理に渡すことを確かめる。
// ほかのまとまりの処理は、この利用者を authctx で読む。
func TestRequireLogin_PassesAuthctxUser(t *testing.T) {
	id := uuid.MustParse(testUserID)
	for _, path := range []string{"/api/users/me", "/api/admin/users", "/no/such/path"} {
		t.Run(path, func(t *testing.T) {
			var p passed
			r := withUser(httptest.NewRequest(http.MethodGet, path, nil), id, "USER", "ADMIN")
			status, _, _ := serve(t, RequireLogin()(p.handler()), r)
			if status != http.StatusTeapot || !p.called || !p.hasID || p.userID != id || !slices.Equal(p.roles, []string{"USER", "ADMIN"}) {
				t.Errorf("次の処理 = %+v, 状態の番号 %d, want 利用者 %s と役割 [USER ADMIN]", p, status, id)
			}
		})
	}
}

// TestIdentify_SkipsAuthPathsAndOptions は、Java 版の shouldNotFilter と同じく、メソッドが OPTIONS の要求と、
// 経路が /api/auth で始まる要求では、Cookie を読まずに次に渡すことを確かめる。
// Java 版は文字列の前方一致なので、/api/authx も読まない。メソッドは大文字と小文字を区別しない。
func TestIdentify_SkipsAuthPathsAndOptions(t *testing.T) {
	svc := newTokenService(time.Date(2026, 11, 11, 4, 0, 0, 0, time.UTC))
	cases := []struct{ method, path string }{
		{http.MethodOptions, "/api/users/me"},
		{"options", "/api/users/me"},
		{http.MethodPost, "/api/auth/login"},
		{http.MethodGet, "/api/auth"},
		{http.MethodGet, "/api/authx"},
	}
	for _, tc := range cases {
		t.Run(tc.method+" "+tc.path, func(t *testing.T) {
			var p passed
			r := httptest.NewRequest(tc.method, tc.path, nil)
			r.Header.Add("Cookie", "accessToken=not-a-jwt")
			status, header, _ := serve(t, Identify(svc)(p.handler()), r)
			if status != http.StatusTeapot || !p.called || p.hasID {
				t.Errorf("次の処理 = %+v, 状態の番号 %d, want 利用者の無い要求として渡す", p, status)
			}
			if got := header.Values("Set-Cookie"); len(got) != 0 {
				t.Errorf("Set-Cookie = %q, want 無し", got)
			}
		})
	}
}

// TestIdentify_NoCookie は、Cookie accessToken が無ければ、利用者の無い要求として次に渡し、Cookie を消さないことを確かめる。
func TestIdentify_NoCookie(t *testing.T) {
	svc := newTokenService(time.Date(2026, 11, 11, 4, 0, 0, 0, time.UTC))
	var p passed
	r := httptest.NewRequest(http.MethodGet, "/api/users/me", nil)
	r.Header.Add("Cookie", "refreshToken=x")
	status, header, _ := serve(t, Identify(svc)(p.handler()), r)
	if status != http.StatusTeapot || !p.called || p.hasID {
		t.Errorf("次の処理 = %+v, 状態の番号 %d, want 利用者の無い要求として渡す", p, status)
	}
	if got := header.Values("Set-Cookie"); len(got) != 0 {
		t.Errorf("Set-Cookie = %q, want 無し", got)
	}
}
