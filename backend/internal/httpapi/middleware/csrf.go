package middleware

import (
	"crypto/rand"
	"crypto/subtle"
	"fmt"
	"net/http"
	"strings"
)

// Java 版の SecurityConfig の csrfTokenRepository と同じ名前である。
const (
	csrfCookieName = "XSRF-TOKEN"
	csrfHeaderName = "X-XSRF-TOKEN"
)

// CSRF は、偽の送信の検査を、Java 版の Spring Security の CsrfFilter と CsrfCookieFilter と同じに行う。
//
//   - OPTIONS の要求は、何もせずに通す
//   - Cookie XSRF-TOKEN が無いか空なら、新しいトークンを作り、XSRF-TOKEN=<トークン>; Path=/ の Cookie を付ける。
//     画面の JavaScript がこの Cookie を読んでヘッダ X-XSRF-TOKEN に写すので、Java 版と同じく HttpOnly を付けない。
//     Java 版は、本番で X-Forwarded-* を読まずに要求を http とみなすので、Secure も SameSite も付けない
//   - GET と HEAD と TRACE のほかの要求で、経路が /api/auth と /actuator の下でなければ、
//     ヘッダ X-XSRF-TOKEN と Cookie のトークンを比べる。一致しなければ、403 と {"message":"アクセス権限がありません。"} を返す
func CSRF(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions {
			next.ServeHTTP(w, r)
			return
		}
		token := ""
		if cookie, err := r.Cookie(csrfCookieName); err == nil {
			token = cookie.Value
		}
		if token == "" {
			token = newToken()
			// gosec は、http.Cookie に Secure と HttpOnly と SameSite のすべてを求める。この Cookie は HttpOnly を付けられないので、
			// http.Cookie を使わずに Set-Cookie の行を書く。トークンは newToken が作る UUID なので、行を壊す文字を含まない
			w.Header().Add("Set-Cookie", csrfCookieName+"="+token+"; Path=/")
		}
		if requiresCSRFCheck(r) && subtle.ConstantTimeCompare([]byte(r.Header.Get(csrfHeaderName)), []byte(token)) != 1 {
			writeMessage(w, http.StatusForbidden, "application/json;charset=UTF-8", MessageForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// requiresCSRFCheck は、Java 版の CsrfFilter が検査する要求かを返す。
// Java 版は、GET と HEAD と TRACE と OPTIONS を検査せず、/api/auth/** と /actuator/** を検査から外している。
func requiresCSRFCheck(r *http.Request) bool {
	switch r.Method {
	case http.MethodGet, http.MethodHead, http.MethodTrace, http.MethodOptions:
		return false
	}
	return !underPath(r.URL.Path, "/api/auth") && !underPath(r.URL.Path, "/actuator")
}

// underPath は、path が prefix そのものか、prefix の下の経路かを返す。
func underPath(path, prefix string) bool {
	return path == prefix || strings.HasPrefix(path, prefix+"/")
}

// newToken は、Java 版の CookieCsrfTokenRepository と同じ、乱数の UUID の形のトークンを作る。
func newToken() string {
	var b [16]byte
	// crypto/rand.Read は、誤りを返さない(Go 1.24 からは、乱数を読めなければプログラムを止める)
	_, _ = rand.Read(b[:])
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
