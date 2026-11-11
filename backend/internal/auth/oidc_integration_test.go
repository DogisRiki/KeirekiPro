package auth

import (
	"encoding/base64"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/config"
	"github.com/DogisRiki/KeirekiPro/backend/internal/platform/redisstore"
)

// rfc7636Octets は、RFC 7636 の付録 B の例の code_verifier の32バイトである。
var rfc7636Octets = []byte{
	116, 24, 223, 180, 151, 153, 224, 37, 79, 250, 96, 125, 216, 173, 187, 186,
	22, 212, 37, 77, 105, 214, 191, 240, 91, 88, 5, 88, 83, 132, 141, 121,
}

const (
	// rfc7636Verifier と rfc7636Challenge は、RFC 7636 の付録 B の例の code_verifier と、その S256 の code_challenge である。
	rfc7636Verifier  = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
	rfc7636Challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
	// testCallbackURI は、Java 版の開発環境の認証の受け口が作る戻り先の URL である。
	testCallbackURI = "http://localhost:8080/api/auth/oidc/callback"
)

// testOIDCConfig は、Java 版の application.yaml と同じログインの開始の接続先と scope に、テストのクライアントの ID を
// 足した設定である。
func testOIDCConfig() config.OIDC {
	return config.OIDC{
		Google: config.Provider{
			AuthURL:  "https://accounts.google.com/o/oauth2/v2/auth",
			Scopes:   "openid email profile",
			ClientID: "google-client-id",
		},
		GitHub: config.Provider{
			AuthURL:  "https://github.com/login/oauth/authorize",
			Scopes:   "read:user user:email",
			ClientID: "github-client-id",
		},
	}
}

// newOIDCService は、テストの Valkey と testOIDCConfig の設定と、乱数の関数 random を使う Service と、
// Redis に直に読み書きするクライアントを作る。
func newOIDCService(t *testing.T, random func([]byte) (int, error)) (*Service, redis.UniversalClient) {
	t.Helper()
	client := redisstore.New(redisstore.Options{Addr: testRedisAddr})
	t.Cleanup(func() { _ = client.Close() })
	return New(Deps{Redis: client, OIDC: testOIDCConfig(), Random: random}), client
}

// oidcStartRandom は、1つ目の32バイトに RFC 7636 の例の code_verifier のバイトを、2つ目の32バイトにテストごとに違う
// バイトを返す乱数の関数と、2つ目の32バイトから作られる state を返す。Java 版の StartOidcAuthorizationUseCase は、
// code_verifier を先に、state をあとに作る。
func oidcStartRandom() (func([]byte) (int, error), string) {
	a, b := uuid.New(), uuid.New()
	stateBytes := append(a[:], b[:]...)
	raw := append(append([]byte{}, rfc7636Octets...), stateBytes...)
	return fixedRandom(raw), base64.RawURLEncoding.EncodeToString(stateBytes)
}

// oidcKeys は、state の3つの記録のキーを返す。
func oidcKeys(state string) []string {
	return []string{"oidc:state:" + state, "oidc:provider:" + state, "oidc:code_verifier:" + state}
}

// TestStartOIDC_URLParamsOrder は、ログインの開始の URL が、Java 版の OidcClient と同じく、接続先のあとに
// client_id、response_type、scope、redirect_uri、state、code_challenge、code_challenge_method をこの順に並べ、
// Spring の UriComponentsBuilder と同じく scope の空白を %20 にし、redirect_uri の : と / を残すことを確かめる。
// code_challenge は code_verifier の SHA-256 の base64url である。provider の大文字と小文字は、
// Java 版の OidcProviderFactory と同じく区別しない(要件1.3)。
func TestStartOIDC_URLParamsOrder(t *testing.T) {
	cases := []struct {
		name, provider, prefix, scope string
	}{
		{"google", "google", "https://accounts.google.com/o/oauth2/v2/auth?client_id=google-client-id", "openid%20email%20profile"},
		{"github", "github", "https://github.com/login/oauth/authorize?client_id=github-client-id", "read:user%20user:email"},
		{"大文字の混じった Google", "Google", "https://accounts.google.com/o/oauth2/v2/auth?client_id=google-client-id", "openid%20email%20profile"},
		{"大文字だけの GITHUB", "GITHUB", "https://github.com/login/oauth/authorize?client_id=github-client-id", "read:user%20user:email"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			random, state := oidcStartRandom()
			s, _ := newOIDCService(t, random)
			got, err := s.StartOIDC(t.Context(), c.provider, testCallbackURI)
			if err != nil {
				t.Fatalf("StartOIDC: %v", err)
			}
			want := c.prefix + "&response_type=code&scope=" + c.scope +
				"&redirect_uri=http://localhost:8080/api/auth/oidc/callback&state=" + state +
				"&code_challenge=" + rfc7636Challenge + "&code_challenge_method=S256"
			if got != want {
				t.Errorf("URL =\n%s\nwant\n%s", got, want)
			}
		})
	}
}

// TestStartOIDC_StoresStateFor10Minutes は、Java 版の RedisOidcAuthorizationSessionStore と同じく、
// oidc:state:<state> に state を、oidc:provider:<state> に受けたままの provider を、oidc:code_verifier:<state> に
// code_verifier を、どれも JSON の文字列で10分置くことを確かめる(要件3.7、要件4.2)。
func TestStartOIDC_StoresStateFor10Minutes(t *testing.T) {
	for _, provider := range []string{"google", "github", "GitHub"} {
		t.Run(provider, func(t *testing.T) {
			random, state := oidcStartRandom()
			s, client := newOIDCService(t, random)
			if _, err := s.StartOIDC(t.Context(), provider, testCallbackURI); err != nil {
				t.Fatalf("StartOIDC: %v", err)
			}
			keys := oidcKeys(state)
			wants := []string{`"` + state + `"`, `"` + provider + `"`, `"` + rfc7636Verifier + `"`}
			for i, key := range keys {
				if got := mustGetRaw(t, client, key); got != wants[i] {
					t.Errorf("%s = %s, want %s", key, got, wants[i])
				}
				assertTTL(t, client, key, 10*time.Minute)
			}
		})
	}
}

// TestStartOIDC_UnknownProvider400 は、Google と GitHub のほかの provider を、Java 版のように記録を置いてから 500 で
// 答えるのではなく、記録を置かずに 400 の「入力エラーがあります。」で断ることを確かめる(要件5.5)。
func TestStartOIDC_UnknownProvider400(t *testing.T) {
	for _, provider := range []string{"twitter", "", "googlee", " google", "git hub"} {
		t.Run("provider="+provider, func(t *testing.T) {
			random, state := oidcStartRandom()
			s, client := newOIDCService(t, random)
			got, err := s.StartOIDC(t.Context(), provider, testCallbackURI)
			wantStatusError(t, err, 400, MessageInvalidInput, "")
			if got != "" {
				t.Errorf("URL = %q, want 空", got)
			}
			for _, key := range oidcKeys(state) {
				if keyExists(t, client, key) {
					t.Errorf("%s の記録が残った", key)
				}
			}
		})
	}
}

// TestStartOIDC_Failures は、乱数を読めないときと Redis に置けないときに、URL を返さず、400 ではない誤りを返すことを確かめる。
func TestStartOIDC_Failures(t *testing.T) {
	t.Run("乱数を読めない", func(t *testing.T) {
		s, _ := newOIDCService(t, func([]byte) (int, error) { return 0, errors.New("乱数の誤り") })
		got, err := s.StartOIDC(t.Context(), "google", testCallbackURI)
		wantServerError(t, got, err)
	})
	t.Run("state を作る乱数を読めない", func(t *testing.T) {
		s, client := newOIDCService(t, fixedRandom(rfc7636Octets))
		got, err := s.StartOIDC(t.Context(), "google", testCallbackURI)
		wantServerError(t, got, err)
		if n, err := client.Exists(t.Context(), "oidc:state:", "oidc:provider:", "oidc:code_verifier:").Result(); err != nil || n != 0 {
			t.Errorf("空の state の記録 = %d, %v, want 0", n, err)
		}
	})
	t.Run("Redis に置けない", func(t *testing.T) {
		random, _ := oidcStartRandom()
		s, client := newOIDCService(t, random)
		_ = client.Close()
		got, err := s.StartOIDC(t.Context(), "google", testCallbackURI)
		wantServerError(t, got, err)
	})
}

// wantServerError は、StartOIDC が URL を返さず、*Error ではない誤り(受け口が 500 で答える誤り)を返したことを確かめる。
func wantServerError(t *testing.T, url string, err error) {
	t.Helper()
	var e *Error
	if err == nil || errors.As(err, &e) {
		t.Errorf("誤り = %v, want *Error ではない誤り", err)
	}
	if url != "" {
		t.Errorf("URL = %q, want 空", url)
	}
}
