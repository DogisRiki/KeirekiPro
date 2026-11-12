package auth

import (
	"testing"
	"time"
)

// この節のテストが比べる文字列は、Java 版の CookieUtil と JwtAuthenticationFilter が書く Set-Cookie の値を、
// Java のコンテナで実際に出したものである。

// TestSessionCookie は、accessToken と refreshToken の Cookie が、Max-Age を持たず、
// Secure を Path のあと HttpOnly の前に置くことを確かめる。
func TestSessionCookie(t *testing.T) {
	cases := []struct {
		name, value string
		secure      bool
		want        string
	}{
		{"accessToken", "tok", false, "accessToken=tok; Path=/; HttpOnly; SameSite=Lax"},
		{"accessToken", "tok", true, "accessToken=tok; Path=/; Secure; HttpOnly; SameSite=Lax"},
		{"refreshToken", "rt", false, "refreshToken=rt; Path=/; HttpOnly; SameSite=Lax"},
		{"refreshToken", "rt", true, "refreshToken=rt; Path=/; Secure; HttpOnly; SameSite=Lax"},
	}
	for _, c := range cases {
		if got := SessionCookie(c.name, c.value, c.secure); got != c.want {
			t.Errorf("SessionCookie(%q, %q, %v) = %q, want %q", c.name, c.value, c.secure, got, c.want)
		}
	}
}

// TestChallengeCookie は、twoFactorChallenge の Cookie が、Path=/api/auth/2fa と Max-Age=600 を持ち、
// Expires に、渡した時刻の600秒あとをグリニッジの時刻で書くことを確かめる。
func TestChallengeCookie(t *testing.T) {
	jst := time.FixedZone("JST", 9*60*60)
	cases := []struct {
		now    time.Time
		secure bool
		want   string
	}{
		{
			time.Date(2026, 11, 11, 4, 47, 26, 0, time.UTC), false,
			"twoFactorChallenge=ch; Path=/api/auth/2fa; Max-Age=600; Expires=Wed, 11 Nov 2026 04:57:26 GMT; HttpOnly; SameSite=Lax",
		},
		{
			time.Date(2026, 11, 11, 4, 47, 26, 0, time.UTC), true,
			"twoFactorChallenge=ch; Path=/api/auth/2fa; Max-Age=600; Expires=Wed, 11 Nov 2026 04:57:26 GMT; Secure; HttpOnly; SameSite=Lax",
		},
		{
			// 日本の時刻を渡しても、グリニッジの時刻で書き、日を2桁で書き、秒より細かい値を書かない。
			time.Date(2026, 1, 2, 8, 55, 0, 999_000_000, jst), false,
			"twoFactorChallenge=ch; Path=/api/auth/2fa; Max-Age=600; Expires=Fri, 02 Jan 2026 00:05:00 GMT; HttpOnly; SameSite=Lax",
		},
	}
	for _, c := range cases {
		if got := ChallengeCookie("ch", c.secure, c.now); got != c.want {
			t.Errorf("ChallengeCookie(%q, %v, %v) = %q, want %q", "ch", c.secure, c.now, got, c.want)
		}
	}
}

// TestDeleteCookie は、Cookie を消す値が、Max-Age=0 と1970年の Expires を持ち、渡した Path を使うことを確かめる。
func TestDeleteCookie(t *testing.T) {
	cases := []struct {
		name, path string
		secure     bool
		want       string
	}{
		{"refreshToken", "/", false, "refreshToken=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Lax"},
		{"refreshToken", "/", true, "refreshToken=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; HttpOnly; SameSite=Lax"},
		{"twoFactorChallenge", "/api/auth/2fa", false, "twoFactorChallenge=; Path=/api/auth/2fa; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Lax"},
		{"twoFactorChallenge", "/api/auth/2fa", true, "twoFactorChallenge=; Path=/api/auth/2fa; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; HttpOnly; SameSite=Lax"},
	}
	for _, c := range cases {
		if got := DeleteCookie(c.name, c.path, c.secure); got != c.want {
			t.Errorf("DeleteCookie(%q, %q, %v) = %q, want %q", c.name, c.path, c.secure, got, c.want)
		}
	}
}

// TestExpiredAccessTokenCookie は、正しくない accessToken を消す値が、Java 版の JwtAuthenticationFilter と同じく、
// HttpOnly と SameSite と Secure を持たないことを確かめる。
func TestExpiredAccessTokenCookie(t *testing.T) {
	want := "accessToken=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
	if got := ExpiredAccessTokenCookie(); got != want {
		t.Errorf("ExpiredAccessTokenCookie() = %q, want %q", got, want)
	}
}
