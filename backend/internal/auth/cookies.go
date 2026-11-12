package auth

import (
	"strconv"
	"strings"
	"time"
)

// この節の関数は、Java 版の CookieUtil(Spring の ResponseCookie.toString())と同じ文字列で、Set-Cookie の値を作る。
// http.Cookie.String() は、属性の順と Expires の書き方が Java 版と違うので使わない。
// 属性の順は、名前=値、Path、Max-Age、Expires、Secure、HttpOnly、SameSite である。

const (
	// ChallengeCookieName は、2段階の認証の途中であることを示す Cookie の名前である。
	ChallengeCookieName = "twoFactorChallenge"
	// ChallengeCookiePath は、2段階の認証の途中であることを示す Cookie を送る先である。
	ChallengeCookiePath = "/api/auth/2fa"
	// challengeCookieMaxAge は、2段階の認証の途中であることを示す Cookie の有効な時間(秒)である。
	challengeCookieMaxAge = 600
	// expiresFormat は、Spring が Expires を書く形(EEE, dd MMM yyyy HH:mm:ss zzz、グリニッジの時刻)である。
	expiresFormat = "Mon, 02 Jan 2006 15:04:05 GMT"
)

// cookieAttrs は、1つの Set-Cookie の値の属性である。maxAge が負なら、Max-Age と Expires を書かない。
// httpOnlyLax が真なら、HttpOnly と SameSite=Lax を書く。Java 版は、この2つをいつも一緒に付けるか、一緒に付けないためである。
type cookieAttrs struct {
	name, value, path   string
	maxAge              int
	expires             time.Time
	secure, httpOnlyLax bool
}

// String は、属性を Spring の ResponseCookie.toString() と同じ順で並べる。
func (c cookieAttrs) String() string {
	var b strings.Builder
	b.WriteString(c.name + "=" + c.value)
	b.WriteString("; Path=" + c.path)
	if c.maxAge >= 0 {
		b.WriteString("; Max-Age=" + strconv.Itoa(c.maxAge))
		b.WriteString("; Expires=" + c.expires.UTC().Format(expiresFormat))
	}
	if c.secure {
		b.WriteString("; Secure")
	}
	if c.httpOnlyLax {
		b.WriteString("; HttpOnly; SameSite=Lax")
	}
	return b.String()
}

// SessionCookie は、accessToken と refreshToken を置く Cookie の値を作る。Max-Age を付けない。
// Java 版の CookieUtil.createHttpOnlyCookie(name, value, secure) にあたる。
func SessionCookie(name, value string, secure bool) string {
	return cookieAttrs{name: name, value: value, path: "/", maxAge: -1, secure: secure, httpOnlyLax: true}.String()
}

// ChallengeCookie は、2段階の認証の途中であることを示す Cookie の値を作る。Expires には now の600秒あとを書く。
// Java 版の LoginController が CookieUtil.createHttpOnlyCookie に Path と600秒を渡すのにあたる。
func ChallengeCookie(value string, secure bool, now time.Time) string {
	return cookieAttrs{
		name: ChallengeCookieName, value: value, path: ChallengeCookiePath,
		maxAge: challengeCookieMaxAge, expires: now.Add(challengeCookieMaxAge * time.Second),
		secure: secure, httpOnlyLax: true,
	}.String()
}

// DeleteCookie は、Cookie を消す値を作る。Java 版の CookieUtil.deleteCookie にあたる。
func DeleteCookie(name, path string, secure bool) string {
	return cookieAttrs{name: name, path: path, maxAge: 0, expires: time.Unix(0, 0), secure: secure, httpOnlyLax: true}.String()
}

// ExpiredAccessTokenCookie は、正しくない accessToken を消す値を作る。HttpOnly と SameSite と Secure を付けない。
// Java 版の JwtAuthenticationFilter が ResponseCookie を path と maxAge(0) だけで作るのにあたる。
func ExpiredAccessTokenCookie() string {
	return cookieAttrs{name: "accessToken", path: "/", maxAge: 0, expires: time.Unix(0, 0)}.String()
}
