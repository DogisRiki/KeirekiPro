//go:build compat

package harness

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"
	"time"

	gojwt "github.com/golang-jwt/jwt/v5"
)

const (
	expireTestJWTKey = "expire-test-jwt-key-0123456789abcdef"
	// expireTestLabel は、Java 版と Go 版が確認のリンクの鍵を導くラベルである。テストでは実装の定数を使わずに書く。
	expireTestLabel = "keirekipro-email-verification-v1"
)

// expireTestNow は、期限切れにする段のテストで使う今の時刻である。
var expireTestNow = time.Date(2026, 11, 11, 9, 30, 0, 0, time.UTC)

// signTestJWT は、ヘッダ header と本体 payload を、鍵 key の HS256 で署名した JWT を返す。
func signTestJWT(t *testing.T, header, payload string, key []byte) string {
	t.Helper()
	enc := base64.RawURLEncoding
	signing := enc.EncodeToString([]byte(header)) + "." + enc.EncodeToString([]byte(payload))
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(signing))
	return signing + "." + enc.EncodeToString(mac.Sum(nil))
}

// emailVerificationTestKey は、確認のリンクの鍵を HMAC-SHA256(secret, ラベル)で導く。
func emailVerificationTestKey(secret string) []byte {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(expireTestLabel))
	return mac.Sum(nil)
}

// parseTestJWT は、値 token の署名を鍵 key の HS256 で確かめ、ヘッダの文字と本体の項目を返す。期限は確かめない。
func parseTestJWT(t *testing.T, token string, key []byte) (string, map[string]any) {
	t.Helper()
	claims := gojwt.MapClaims{}
	_, err := gojwt.NewParser(gojwt.WithValidMethods([]string{"HS256"}), gojwt.WithoutClaimsValidation(), gojwt.WithJSONNumber()).
		ParseWithClaims(token, claims, func(*gojwt.Token) (any, error) { return key, nil })
	if err != nil {
		t.Fatalf("書き換えた値 %q の署名を確かめられません: %v", token, err)
	}
	header, err := base64.RawURLEncoding.DecodeString(strings.Split(token, ".")[0])
	if err != nil {
		t.Fatalf("書き換えた値のヘッダを読めません: %v", err)
	}
	return string(header), claims
}

func claimInt(t *testing.T, claims map[string]any, name string) int64 {
	t.Helper()
	n, ok := claims[name].(json.Number)
	if !ok {
		t.Fatalf("項目 %s が数ではありません: %#v", name, claims[name])
	}
	v, err := n.Int64()
	if err != nil {
		t.Fatalf("項目 %s を整数として読めません: %v", name, err)
	}
	return v
}

func newExpireSession() *Session {
	s := NewSession()
	s.now = func() time.Time { return expireTestNow }
	return s
}

func TestExpire_AccessTokenKeepsClaims(t *testing.T) {
	header := `{"alg":"HS256","typ":"JWT"}`
	payload := `{"sub":"7b0c1a4e-9f1d-4c55-8e2a-0d6b3f1e2a77","roles":["USER","ADMIN"],"tv":3,"jti":"a1b2c3d4-0000-4000-8000-000000000001","iat":1800000000,"exp":1800000600}`
	token := signTestJWT(t, header, payload, []byte(expireTestJWTKey))

	tests := []struct {
		name  string
		step  Step
		setup func(s *Session)
		read  func(s *Session) (string, bool)
	}{
		{
			name: "Cookie の束の Cookie",
			step: Step{Name: "期限を切らす", Expire: &ExpireStep{Cookie: "accessToken"}},
			setup: func(s *Session) {
				s.cookies[cookieKey{name: "accessToken", path: "/"}] = token
				s.cookies[cookieKey{name: "refreshToken", path: "/api/auth"}] = "other"
			},
			read: func(s *Session) (string, bool) {
				v, ok := s.cookies[cookieKey{name: "accessToken", path: "/"}]
				return v, ok
			},
		},
		{
			name:  "取り出した値",
			step:  Step{Name: "期限を切らす", Expire: &ExpireStep{Var: "token"}},
			setup: func(s *Session) { s.vars["token"] = token },
			read: func(s *Session) (string, bool) {
				v, ok := s.vars["token"]
				return v, ok
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := newExpireSession()
			tt.setup(s)
			if err := s.Expire(tt.step, expireTestJWTKey); err != nil {
				t.Fatalf("Expire が誤りを返しました: %v", err)
			}
			got, ok := tt.read(s)
			if !ok {
				t.Fatal("書き換えた値がありません")
			}
			if got == token {
				t.Fatal("値が書き換わっていません")
			}
			gotHeader, claims := parseTestJWT(t, got, []byte(expireTestJWTKey))
			if gotHeader != header {
				t.Errorf("ヘッダが %s でした。期待は %s です", gotHeader, header)
			}
			if got, want := claimInt(t, claims, "exp"), expireTestNow.Add(-time.Minute).Unix(); got != want {
				t.Errorf("exp が %d でした。期待は今の1分前の %d です", got, want)
			}
			if got, want := claimInt(t, claims, "iat"), expireTestNow.Add(-11*time.Minute).Unix(); got != want {
				t.Errorf("iat が %d でした。期待は今の11分前の %d です", got, want)
			}
			if got := claims["sub"]; got != "7b0c1a4e-9f1d-4c55-8e2a-0d6b3f1e2a77" {
				t.Errorf("sub が %v でした", got)
			}
			if got := claims["jti"]; got != "a1b2c3d4-0000-4000-8000-000000000001" {
				t.Errorf("jti が %v でした", got)
			}
			if got := claimInt(t, claims, "tv"); got != 3 {
				t.Errorf("世代の番号 tv が %d でした。期待は 3 です", got)
			}
			roles, _ := json.Marshal(claims["roles"])
			if string(roles) != `["USER","ADMIN"]` {
				t.Errorf("roles が %s でした", roles)
			}
			if len(claims) != 6 {
				t.Errorf("項目の数が %d でした。期待は 6 です: %v", len(claims), claims)
			}
		})
	}
	t.Run("Cookie の束のほかの Cookie は変えない", func(t *testing.T) {
		s := newExpireSession()
		s.cookies[cookieKey{name: "accessToken", path: "/"}] = token
		s.cookies[cookieKey{name: "refreshToken", path: "/api/auth"}] = "other"
		if err := s.Expire(Step{Name: "期限を切らす", Expire: &ExpireStep{Cookie: "accessToken"}}, expireTestJWTKey); err != nil {
			t.Fatalf("Expire が誤りを返しました: %v", err)
		}
		if got := s.cookies[cookieKey{name: "refreshToken", path: "/api/auth"}]; got != "other" {
			t.Errorf("refreshToken が %q に変わりました", got)
		}
	})
	t.Run("同じ名前の Cookie はパスによらずすべて書き換える", func(t *testing.T) {
		s := newExpireSession()
		s.cookies[cookieKey{name: "accessToken", path: "/"}] = token
		s.cookies[cookieKey{name: "accessToken", path: "/api"}] = token
		if err := s.Expire(Step{Name: "期限を切らす", Expire: &ExpireStep{Cookie: "accessToken"}}, expireTestJWTKey); err != nil {
			t.Fatalf("Expire が誤りを返しました: %v", err)
		}
		for _, path := range []string{"/", "/api"} {
			got := s.cookies[cookieKey{name: "accessToken", path: path}]
			_, claims := parseTestJWT(t, got, []byte(expireTestJWTKey))
			if got, want := claimInt(t, claims, "exp"), expireTestNow.Add(-time.Minute).Unix(); got != want {
				t.Errorf("パス %s の Cookie の exp が %d でした。期待は %d です", path, got, want)
			}
		}
	})
	t.Run("読めない Cookie があるときは同じ名前のどの Cookie も書き換えない", func(t *testing.T) {
		s := newExpireSession()
		s.cookies[cookieKey{name: "accessToken", path: "/"}] = token
		s.cookies[cookieKey{name: "accessToken", path: "/api"}] = "not-a-jwt"
		if err := s.Expire(Step{Name: "期限を切らす", Expire: &ExpireStep{Cookie: "accessToken"}}, expireTestJWTKey); err == nil {
			t.Fatal("Expire が誤りを返しませんでした")
		}
		if got := s.cookies[cookieKey{name: "accessToken", path: "/"}]; got != token {
			t.Error("読める Cookie が書き換わりました")
		}
	})
}

func TestExpire_EmailVerificationLexp(t *testing.T) {
	header := `{"alg":"HS256","typ":"JWT"}`
	payload := `{"aud":"keirekipro-email-verification","jti":"5f0e2b7a-1111-4222-8333-444455556666","sub":"0e8d6c1b-2222-4333-8444-555566667777","purpose":"REGISTRATION","email":"a&b<c>@example.com","lexp":1800003600}`
	key := emailVerificationTestKey(expireTestJWTKey)
	token := signTestJWT(t, header, payload, key)

	s := newExpireSession()
	s.vars["link"] = token
	if err := s.Expire(Step{Name: "リンクの期限を切らす", Expire: &ExpireStep{Var: "link"}}, expireTestJWTKey); err != nil {
		t.Fatalf("Expire が誤りを返しました: %v", err)
	}
	got := s.vars["link"]
	// 確認のリンクの値は、ログインの状態の値の鍵では確かめられない
	if _, err := gojwt.NewParser(gojwt.WithValidMethods([]string{"HS256"}), gojwt.WithoutClaimsValidation()).
		Parse(got, func(*gojwt.Token) (any, error) { return []byte(expireTestJWTKey), nil }); err == nil {
		t.Error("書き換えた確認のリンクの値が、ログインの状態の値の鍵で署名されています")
	}
	gotHeader, claims := parseTestJWT(t, got, key)
	if gotHeader != header {
		t.Errorf("ヘッダが %s でした。期待は %s です", gotHeader, header)
	}
	if got, want := claimInt(t, claims, "lexp"), expireTestNow.Add(-time.Minute).Unix(); got != want {
		t.Errorf("lexp が %d でした。期待は今の1分前の %d です", got, want)
	}
	want := map[string]string{
		"aud":     "keirekipro-email-verification",
		"jti":     "5f0e2b7a-1111-4222-8333-444455556666",
		"sub":     "0e8d6c1b-2222-4333-8444-555566667777",
		"purpose": "REGISTRATION",
		"email":   "a&b<c>@example.com",
	}
	for name, w := range want {
		if claims[name] != w {
			t.Errorf("項目 %s が %v でした。期待は %s です", name, claims[name], w)
		}
	}
	for _, name := range []string{"iat", "exp"} {
		if _, ok := claims[name]; ok {
			t.Errorf("確認のリンクの値に、元に無い項目 %s が足されました", name)
		}
	}
	if len(claims) != 6 {
		t.Errorf("項目の数が %d でした。期待は 6 です: %v", len(claims), claims)
	}
}

func TestExpire_MissingValueFails(t *testing.T) {
	valid := signTestJWT(t, `{"alg":"HS256","typ":"JWT"}`, `{"sub":"x","iat":1,"exp":2}`, []byte(expireTestJWTKey))
	tests := []struct {
		name  string
		step  Step
		setup func(s *Session)
		want  []string
	}{
		{
			name: "Cookie が無い",
			step: Step{Name: "期限を切らす", Expire: &ExpireStep{Cookie: "accessToken"}},
			setup: func(s *Session) {
				s.cookies[cookieKey{name: "refreshToken", path: "/"}] = valid
			},
			want: []string{"期限を切らす", "accessToken", "Cookie の束にありません"},
		},
		{
			name:  "取り出した値が無い",
			step:  Step{Name: "期限を切らす", Expire: &ExpireStep{Var: "token"}},
			setup: func(s *Session) { s.vars["other"] = valid },
			want:  []string{"期限を切らす", "token", "capture で取り出していません"},
		},
		{
			name:  "JWT の形でない",
			step:  Step{Name: "期限を切らす", Expire: &ExpireStep{Var: "token"}},
			setup: func(s *Session) { s.vars["token"] = "not-a-jwt" },
			want:  []string{"期限を切らす", "token"},
		},
		{
			name:  "本体が JSON でない",
			step:  Step{Name: "期限を切らす", Expire: &ExpireStep{Var: "token"}},
			setup: func(s *Session) { s.vars["token"] = "eyJhbGciOiJIUzI1NiJ9.bm90LWpzb24.c2ln" },
			want:  []string{"期限を切らす", "token"},
		},
		{
			name:  "本体が base64url でない",
			step:  Step{Name: "期限を切らす", Expire: &ExpireStep{Var: "token"}},
			setup: func(s *Session) { s.vars["token"] = "eyJhbGciOiJIUzI1NiJ9.!!!.c2ln" },
			want:  []string{"期限を切らす", "token"},
		},
		{
			name:  "本体が null",
			step:  Step{Name: "期限を切らす", Expire: &ExpireStep{Var: "token"}},
			setup: func(s *Session) { s.vars["token"] = "eyJhbGciOiJIUzI1NiJ9.bnVsbA.c2ln" },
			want:  []string{"期限を切らす", "token"},
		},
		{
			name: "Cookie の値が JWT の形でない",
			step: Step{Name: "期限を切らす", Expire: &ExpireStep{Cookie: "accessToken"}},
			setup: func(s *Session) {
				s.cookies[cookieKey{name: "accessToken", path: "/"}] = "not-a-jwt"
			},
			want: []string{"期限を切らす", "accessToken"},
		},
		{
			name:  "expire を持たない段",
			step:  Step{Name: "期限を切らす"},
			setup: func(*Session) {},
			want:  []string{"期限を切らす", "expire"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := newExpireSession()
			tt.setup(s)
			err := s.Expire(tt.step, expireTestJWTKey)
			if err == nil {
				t.Fatal("Expire が誤りを返しませんでした")
			}
			for _, w := range tt.want {
				if !strings.Contains(err.Error(), w) {
					t.Errorf("誤り %q に %q が含まれません", err, w)
				}
			}
		})
	}
	t.Run("値が無いときはほかの値を変えない", func(t *testing.T) {
		s := newExpireSession()
		s.vars["other"] = valid
		_ = s.Expire(Step{Name: "期限を切らす", Expire: &ExpireStep{Var: "token"}}, expireTestJWTKey)
		if s.vars["other"] != valid {
			t.Error("ほかの取り出した値が変わりました")
		}
		if _, ok := s.vars["token"]; ok {
			t.Error("無かった取り出した値が足されました")
		}
	})
}
