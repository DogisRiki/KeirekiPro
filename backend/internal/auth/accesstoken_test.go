package auth

import (
	"errors"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
)

// testSigningKey は、テストで値に署名する鍵の文字列である。
const testSigningKey = "test-jwt-secret-0123456789abcdef0123456789abcdef"

// testUserID は、テストの値の sub に入れる利用者の ID である。
const testUserID = "0f8fad5b-d9cb-469f-a165-70867728950e"

// newTokenService は、今の時刻を now に決めた、ログインの状態の値を扱う Service を作る。
// データベースの接続の束を渡さないので、データベースを読む前に断る場合だけを確かめられる。
func newTokenService(now time.Time) *Service {
	return New(Deps{
		JWT: config.JWT{Secret: testSigningKey, AccessTokenValidity: 10 * time.Minute},
		Now: func() time.Time { return now },
	})
}

// signToken は、claims を method と key で署名した値を作る。
func signToken(t *testing.T, method jwt.SigningMethod, claims jwt.MapClaims, key any) string {
	t.Helper()
	token, err := jwt.NewWithClaims(method, claims).SignedString(key)
	if err != nil {
		t.Fatalf("値に署名できない: %v", err)
	}
	return token
}

// validClaims は、now に発行した、有効な時間が10分の値の項目を作る。
func validClaims(now time.Time) jwt.MapClaims {
	return jwt.MapClaims{
		"sub":          testUserID,
		"roles":        []string{"USER"},
		"tokenVersion": 0,
		"iat":          now.Unix(),
		"exp":          now.Add(10 * time.Minute).Unix(),
	}
}

// assertInvalidToken は、VerifyAccessToken が ErrInvalidToken を返したかを確かめる。
func assertInvalidToken(t *testing.T, svc *Service, token string) {
	t.Helper()
	p, err := svc.VerifyAccessToken(t.Context(), token)
	if !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("VerifyAccessToken = %+v, %v, want ErrInvalidToken", p, err)
	}
}

// TestAccessToken_RejectsExpired は、有効な時間を過ぎた値と、exp の無い値を断ることを確かめる。
// Java 版の java-jwt と同じく、時刻のずれの猶予を持たない。
func TestAccessToken_RejectsExpired(t *testing.T) {
	issued := time.Date(2026, 11, 11, 4, 0, 0, 0, time.UTC)
	token := signToken(t, jwt.SigningMethodHS256, validClaims(issued), []byte(testSigningKey))
	for _, now := range []time.Time{
		issued.Add(10 * time.Minute),
		issued.Add(10*time.Minute + time.Second),
		issued.Add(24 * time.Hour),
	} {
		t.Run(now.Sub(issued).String(), func(t *testing.T) {
			assertInvalidToken(t, newTokenService(now), token)
		})
	}
	t.Run("exp が無い", func(t *testing.T) {
		claims := validClaims(issued)
		delete(claims, "exp")
		assertInvalidToken(t, newTokenService(issued), signToken(t, jwt.SigningMethodHS256, claims, []byte(testSigningKey)))
	})
	t.Run("iat が今より後", func(t *testing.T) {
		claims := validClaims(issued.Add(time.Minute))
		assertInvalidToken(t, newTokenService(issued), signToken(t, jwt.SigningMethodHS256, claims, []byte(testSigningKey)))
	})
}

// TestAccessToken_RejectsBadSignature は、違う鍵で署名した値と、署名のあとに書き換えた値を断ることを確かめる。
func TestAccessToken_RejectsBadSignature(t *testing.T) {
	now := time.Date(2026, 11, 11, 4, 0, 0, 0, time.UTC)
	svc := newTokenService(now)
	t.Run("違う鍵", func(t *testing.T) {
		assertInvalidToken(t, svc, signToken(t, jwt.SigningMethodHS256, validClaims(now), []byte(testSigningKey+"x")))
	})
	t.Run("項目の書き換え", func(t *testing.T) {
		good := signToken(t, jwt.SigningMethodHS256, validClaims(now), []byte(testSigningKey))
		admin := validClaims(now)
		admin["roles"] = []string{"USER", "ADMIN"}
		forged := signToken(t, jwt.SigningMethodHS256, admin, []byte(testSigningKey+"x"))
		// 書き換えた項目の部分と、元の署名をつなぐ。
		goodParts := splitToken(t, good)
		forgedParts := splitToken(t, forged)
		assertInvalidToken(t, svc, forgedParts[0]+"."+forgedParts[1]+"."+goodParts[2])
	})
	t.Run("値の形でない", func(t *testing.T) {
		assertInvalidToken(t, svc, "not-a-jwt")
	})
}

// TestAccessToken_RejectsAlgNone は、署名の無い値と、HS256 でない方式で署名した値を断ることを確かめる。
// Java 版は Algorithm.HMAC256 で検証するので、ほかの方式の値を断る。
func TestAccessToken_RejectsAlgNone(t *testing.T) {
	now := time.Date(2026, 11, 11, 4, 0, 0, 0, time.UTC)
	svc := newTokenService(now)
	t.Run("none", func(t *testing.T) {
		assertInvalidToken(t, svc, signToken(t, jwt.SigningMethodNone, validClaims(now), jwt.UnsafeAllowNoneSignatureType))
	})
	t.Run("HS384", func(t *testing.T) {
		assertInvalidToken(t, svc, signToken(t, jwt.SigningMethodHS384, validClaims(now), []byte(testSigningKey)))
	})
	t.Run("HS512", func(t *testing.T) {
		assertInvalidToken(t, svc, signToken(t, jwt.SigningMethodHS512, validClaims(now), []byte(testSigningKey)))
	})
}

// TestAccessToken_RejectsNonUUIDSub は、sub が UUID でない値と、sub か tokenVersion の無い値を断ることを確かめる。
// どれも、データベースを読む前に断る。
func TestAccessToken_RejectsNonUUIDSub(t *testing.T) {
	now := time.Date(2026, 11, 11, 4, 0, 0, 0, time.UTC)
	svc := newTokenService(now)
	cases := []struct {
		name   string
		modify func(jwt.MapClaims)
	}{
		{"UUID でない", func(c jwt.MapClaims) { c["sub"] = "not-a-uuid" }},
		{"空", func(c jwt.MapClaims) { c["sub"] = "" }},
		{"sub が無い", func(c jwt.MapClaims) { delete(c, "sub") }},
		{"tokenVersion が無い", func(c jwt.MapClaims) { delete(c, "tokenVersion") }},
		{"tokenVersion が文字列", func(c jwt.MapClaims) { c["tokenVersion"] = "0" }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			claims := validClaims(now)
			tc.modify(claims)
			assertInvalidToken(t, svc, signToken(t, jwt.SigningMethodHS256, claims, []byte(testSigningKey)))
		})
	}
}

// splitToken は、値を、ヘッダと項目と署名の3つに分ける。
func splitToken(t *testing.T, token string) [3]string {
	t.Helper()
	var parts [3]string
	n := 0
	start := 0
	for i := 0; i <= len(token); i++ {
		if i == len(token) || token[i] == '.' {
			if n == 3 {
				t.Fatalf("値 %q の区切りが3つより多い", token)
			}
			parts[n] = token[start:i]
			n++
			start = i + 1
		}
	}
	if n != 3 {
		t.Fatalf("値 %q を3つに分けられない", token)
	}
	return parts
}
