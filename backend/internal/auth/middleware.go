package auth

import (
	"errors"
	"fmt"
	"net/http"
	"slices"
	"strings"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/authctx"
)

// loginCookieName は、ログインの状態の値を持つ Cookie の名前である(Java 版の JwtAuthenticationFilter と同じ)。
const loginCookieName = "accessToken"

// adminRole は、/api/admin の下を使える役割の名前である(Java 版の hasRole("ADMIN") と同じ)。
const adminRole = "ADMIN"

// forbiddenBody は、役割の足りない要求を断るときの本文である(Java 版の accessDeniedHandler と同じ)。
var forbiddenBody = `{"message":"` + MessageForbidden + `"}`

// Identify は、Cookie accessToken のログインの状態の値を確かめ、受け付けた値の利用者と役割を context に入れて次に渡す、
// 値を読む段の中間処理を返す。Java 版の JwtAuthenticationFilter と同じ動きをする。
//   - メソッドが OPTIONS(大文字と小文字を区別しない)か、経路が /api/auth で始まる要求では、値を読まない
//   - Cookie が無ければ、利用者の無い要求として次に渡す
//   - 値を受け付けないとき(ErrInvalidToken)は、Cookie を消す Set-Cookie を足し、利用者の無い要求として次に渡す
//   - 利用者がまだ居るかは確かめない
//   - データベースを読めないときは、次に渡さず、誤りを持つパニックで処理を打ち切る。外側のパニックの受け止めが、
//     誤りをログに書き、決まった本文の 500 で答える
func Identify(svc *Service) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if strings.EqualFold(r.Method, http.MethodOptions) || strings.HasPrefix(r.URL.Path, "/api/auth") {
				next.ServeHTTP(w, r)
				return
			}
			cookie, err := r.Cookie(loginCookieName)
			if err != nil {
				next.ServeHTTP(w, r)
				return
			}
			p, err := svc.VerifyAccessToken(r.Context(), cookie.Value)
			switch {
			case err == nil:
				next.ServeHTTP(w, r.WithContext(authctx.With(r.Context(), p.UserID, p.Roles)))
			case errors.Is(err, ErrInvalidToken):
				w.Header().Add("Set-Cookie", ExpiredAccessTokenCookie())
				next.ServeHTTP(w, r)
			default:
				panic(fmt.Errorf("auth: ログインの状態の値を確かめられない: %w", err))
			}
		})
	}
}

// RequireLogin は、ログインの要る要求を、利用者が居なければ 401 で、/api/admin の下で役割 ADMIN が無ければ 403 で断る、
// ログインを求める段の中間処理を返す。Java 版の SecurityConfig と同じ要求をログイン無しで通す。
func RequireLogin() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if isPublic(r) {
				next.ServeHTTP(w, r)
				return
			}
			if _, ok := authctx.UserID(r.Context()); !ok {
				// Java 版の HttpStatusEntryPoint と同じく、本文の無い 401 で答える。
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			if under(r.URL.Path, "/api/admin") && !slices.Contains(authctx.Roles(r.Context()), adminRole) {
				w.Header().Set("Content-Type", "application/json;charset=UTF-8")
				w.WriteHeader(http.StatusForbidden)
				_, _ = w.Write([]byte(forbiddenBody))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// isPublic は、要求が、Java 版の SecurityConfig の permitAll に当たるかを返す。/healthz は Go 版の生きているかの確認である。
func isPublic(r *http.Request) bool {
	if r.Method == http.MethodOptions {
		return true
	}
	p := r.URL.Path
	return under(p, "/api/auth") || under(p, "/actuator") || under(p, "/swagger-ui") || under(p, "/v3/api-docs") ||
		p == "/swagger-ui.html" || p == "/healthz"
}

// under は、経路 p が base そのものか base の下にあるかを返す。Spring の「base/**」と同じく、base に続く文字が / の経路だけを下とみなす。
func under(p, base string) bool {
	return p == base || strings.HasPrefix(p, base+"/")
}
