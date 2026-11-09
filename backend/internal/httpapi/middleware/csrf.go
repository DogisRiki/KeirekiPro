package middleware

import (
	"crypto/rand"
	"crypto/subtle"
	"fmt"
	"net/http"
	"strings"
)

// 画面が使う Cookie とヘッダの名前である。名前は要件9の受入基準1で今と同じにする。
const (
	csrfCookieName = "XSRF-TOKEN"
	csrfHeaderName = "X-XSRF-TOKEN"
)

// CSRF は、偽の送信の検査を行う。
//
//   - OPTIONS の要求は、何もせずに通す
//   - GET と HEAD と OPTIONS のほかの要求で、経路が /api/auth の下でなければ、ヘッダ X-XSRF-TOKEN と Cookie XSRF-TOKEN を比べる。
//     Cookie が無いか空か、2つが一致しなければ、新しいトークンの Cookie を付けて、403 と {"message":"アクセス権限がありません。"} を返す
//   - 検査を通った要求と、検査しない要求で、Cookie が無いか空なら、新しいトークンの Cookie を付けて先へ渡す
//
// /api/auth の下を検査しないのは、画面がログインに使う通信の部品が、トークンをヘッダに写さないためである。
// 検査すると、今の画面からログインできなくなる(要件9の受入基準1)。
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
		if requiresCSRFCheck(r) && (token == "" || subtle.ConstantTimeCompare([]byte(r.Header.Get(csrfHeaderName)), []byte(token)) != 1) {
			setTokenCookie(w)
			writeMessage(w, http.StatusForbidden, "application/json;charset=UTF-8", MessageForbidden)
			return
		}
		if token == "" {
			setTokenCookie(w)
		}
		next.ServeHTTP(w, r)
	})
}

// setTokenCookie は、新しいトークンの Cookie XSRF-TOKEN を付ける。
// 画面の JavaScript がこの Cookie を読んでヘッダ X-XSRF-TOKEN に写すので、HttpOnly を付けない。
// gosec は、http.Cookie に Secure と HttpOnly と SameSite のすべてを求める。この Cookie は HttpOnly を付けられないので、
// http.Cookie を使わずに Set-Cookie の行を書く。トークンは newToken が作る UUID なので、行を壊す文字を含まない。
// Cookie の性質(Path=/ だけを付ける)は、design の「安全」の節のとおり、今と同じにする。
func setTokenCookie(w http.ResponseWriter) {
	w.Header().Add("Set-Cookie", csrfCookieName+"="+newToken()+"; Path=/")
}

// requiresCSRFCheck は、偽の送信の検査をする要求かを返す。
func requiresCSRFCheck(r *http.Request) bool {
	switch r.Method {
	case http.MethodGet, http.MethodHead, http.MethodOptions:
		return false
	}
	return !underPath(r.URL.Path, "/api/auth")
}

// underPath は、path が prefix そのものか、prefix の下の経路かを返す。
func underPath(path, prefix string) bool {
	return path == prefix || strings.HasPrefix(path, prefix+"/")
}

// newToken は、乱数の UUID(版4)の形のトークンを作る。
func newToken() string {
	var b [16]byte
	// crypto/rand.Read は、誤りを返さない(Go 1.24 からは、乱数を読めなければプログラムを止める)
	_, _ = rand.Read(b[:])
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
